import CloudKit
import CoreData
import Foundation
import Testing
@testable import Trio

extension BackupSnapshotTests {
    @MainActor @Test("Only a daily elapsed interval schedules automatic comparison") func dailySchedule() {
        let first = Date(timeIntervalSince1970: 1000)
        #expect(TrioCloudBackupCoordinator.isDailyCheckDue(last: nil, now: first))
        #expect(!TrioCloudBackupCoordinator.isDailyCheckDue(last: first, now: first.addingTimeInterval(23 * 3600)))
        #expect(TrioCloudBackupCoordinator.isDailyCheckDue(last: first, now: first.addingTimeInterval(24 * 3600)))
    }

    @MainActor func coordinator(
        cloud: CloudBackupFakeCloud,
        directory: URL,
        defaults: UserDefaults? = nil,
        capture: ((TrioSettingsBackup.Origin, String?) async throws -> TrioSettingsBackup)? = nil
    ) -> TrioCloudBackupCoordinator {
        TrioCloudBackupCoordinator(
            cloud: cloud,
            defaults: defaults ?? isolatedDefaults(),
            queueURL: directory.appendingPathComponent("queue.json"),
            onboardingInProgress: { false },
            capture: capture ?? { origin, name in
                try makeBackup(validConfiguration(), origin: origin, name: name)
            }
        )
    }

    @MainActor
    @Test("Daily comparisons produce no duplicate backups without changed settings") func dailyNoOp() async throws {
        let cloud = CloudBackupFakeCloud()
        let directory = try directory()
        let baseline = Date(timeIntervalSince1970: 1_700_000_000)
        let prefs = CloudBackupConfigurationBox(value: validConfiguration())
        let coordinator = coordinator(cloud: cloud, directory: directory, capture: { origin, name in
            try makeBackup(prefs.value, origin: origin, name: name)
        })
        await coordinator.runAutomaticBackup(now: baseline)
        await coordinator.runAutomaticBackup(now: baseline.addingTimeInterval(3600))
        await coordinator.runAutomaticBackup(now: baseline.addingTimeInterval(86400))
        #expect(cloud.uploads.count == 1)
        var modified = Preferences()
        modified.maxIOB = 5
        prefs.value = validConfiguration(preferences: modified)
        await coordinator.runAutomaticBackup(now: baseline.addingTimeInterval(2 * 86400))
        #expect(cloud.uploads.count == 2)
        coordinator.automaticEnabled = false
    }

    @MainActor
    @Test("Manual backups are independent even when settings are identical") func manualDuplicates() async throws {
        let cloud = CloudBackupFakeCloud()
        let coordinator = coordinator(cloud: cloud, directory: try directory())
        _ = try await coordinator.createManualBackup(name: "Before")
        _ = try await coordinator.createManualBackup(name: "After")
        #expect(cloud.uploads.count == 2)
        #expect(cloud.uploads[0].fingerprint == cloud.uploads[1].fingerprint)
        #expect(cloud.uploads[0].id != cloud.uploads[1].id)
        coordinator.automaticEnabled = false
    }

    @MainActor
    @Test("Offline uploads survive coordinator recreation with the same snapshot UUID") func durableOfflineQueue() async throws {
        let directory = try directory()
        let cloud = CloudBackupFakeCloud()
        cloud.fail = true
        let defaults = isolatedDefaults()
        func coordinator() -> TrioCloudBackupCoordinator {
            self.coordinator(cloud: cloud, directory: directory, defaults: defaults)
        }
        let original = coordinator()
        await original.runAutomaticBackup()
        #expect(original.lastError != nil)
        let pending = try #require(original.loadQueue().first)
        let recreated = coordinator()
        cloud.fail = false
        await recreated.runAutomaticBackup(capturePending: false)
        #expect(cloud.uploads.last?.id == pending.id)
        #expect(try recreated.loadQueue().isEmpty)
        original.automaticEnabled = false
    }

    @MainActor
    @Test("A corrupt local upload queue is preserved and reported") func corruptQueue() async throws {
        let directory = try directory()
        let queue = directory.appendingPathComponent("queue.json")
        let bytes = Data("invalid queue".utf8)
        try bytes.write(to: queue)
        let coordinator = coordinator(cloud: CloudBackupFakeCloud(), directory: directory)
        await coordinator.runAutomaticBackup()
        #expect(coordinator.lastError != nil)
        #expect(try Data(contentsOf: queue) == bytes)
        coordinator.automaticEnabled = false
    }

    @MainActor
    @Test("Reinstallation checks cloud history before uploading an identical automatic snapshot") func reinstallDeduplication(
    ) async throws {
        let directory = try directory()
        let cloud = CloudBackupFakeCloud()
        let snapshot = try makeBackup(validConfiguration(), origin: .automatic)
        cloud.history = [.init(
            id: snapshot.id.uuidString,
            createdAt: snapshot.createdAt,
            origin: .automatic,
            name: nil,
            fingerprint: snapshot.fingerprint
        )]
        cloud.downloads[snapshot.id.uuidString] = snapshot
        let coordinator = coordinator(
            cloud: cloud,
            directory: directory,
            capture: { _, _ in snapshot }
        )
        await coordinator.runAutomaticBackup()
        #expect(cloud.uploads.isEmpty)
        #expect(try coordinator.loadQueue().isEmpty)
        coordinator.automaticEnabled = false
    }

    @MainActor
    @Test("Retention treats origins separately, ignores unavailable records and retries failed cleanup") func retention() async throws {
        let directory = try directory()
        let cloud = CloudBackupFakeCloud()
        let now = Date()
        cloud.history = TrioSettingsBackup.Origin.allCases.flatMap { origin in
            (0 ..< 5).map { index in
                BackupEntry(
                    id: "\(origin.rawValue)-\(index)",
                    createdAt: now.addingTimeInterval(-Double(index)),
                    origin: origin,
                    fingerprint: "test"
                )
            }
        }
        cloud.history.append(.init(
            id: "unreadable",
            createdAt: .distantPast,
            origin: .manual,
            fingerprint: "",
            validationMessage: "Unavailable"
        ))
        let coordinator = coordinator(cloud: cloud, directory: directory)
        try await coordinator.setRetentionLimit(3, for: .manual)
        #expect(cloud.deleted == ["manual-3", "manual-4"])
        cloud.fail = true
        await #expect(throws: BackupError.iCloudUnavailable) { try await coordinator.setRetentionLimit(3, for: .automatic) }
        #expect(coordinator.retentionLimit(for: .automatic) == 3)
        cloud.fail = false
        await coordinator.runAutomaticBackup(capturePending: false)
        #expect(cloud.deleted == ["manual-3", "manual-4", "automatic-3", "automatic-4"])
        #expect(cloud.history.contains { $0.id == "unreadable" })
        coordinator.automaticEnabled = false
    }

    @MainActor
    @Test("Pending manual backups remain independent of the automatic toggle") func manualRetryWhenAutomaticDisabled() async throws {
        let directory = try directory()
        let cloud = CloudBackupFakeCloud()
        cloud.fail = true
        let coordinator = coordinator(cloud: cloud, directory: directory)
        await #expect(throws: BackupError.iCloudUnavailable) {
            _ = try await coordinator.createManualBackup(name: "Offline manual") }
        coordinator.automaticEnabled = false
        cloud.fail = false
        await coordinator.runAutomaticBackup(capturePending: false)
        #expect(cloud.uploads.count == 1)
        #expect(try coordinator.loadQueue().isEmpty)
    }

    @Test("Cloud records keep every backup field in encrypted values and never use assets") func recordFieldsAreEncrypted() throws {
        let snapshot = try makeBackup(validConfiguration(), name: "Before trip")
        let record = CKRecord(recordType: TrioCloudRecordCodec.recordType, recordID: TrioCloudRecordCodec.recordID(for: snapshot.id))
        try TrioCloudRecordCodec.fill(record, with: snapshot)
        #expect(Set(record.encryptedValues.allKeys()) == ["fingerprint", "name", "snapshot"])
        #expect(Set(record.allKeys()) == ["createdAt", "origin", "appVersion", "schemaVersion"])
        #expect(record.allKeys().allSatisfy { !(record[$0] is CKAsset) })
        #expect(record.recordID.zoneID == TrioCloudRecordCodec.zoneID)
        let decoded = try TrioCloudRecordCodec.snapshot(from: record)
        #expect(decoded.id == snapshot.id && decoded.name == "Before trip")
        let entry = try TrioCloudRecordCodec.entry(from: record)
        #expect(entry.fingerprint == snapshot.fingerprint && entry.origin == .manual && entry.name == "Before trip")
    }

    @Test("Cloud records validate payload, checksum and record identity") func cloudRecordValidation() throws {
        let snapshot = try makeBackup(validConfiguration())
        let bytes = try JSONEncoder().encode(snapshot)
        let id = TrioCloudRecordCodec.recordID(for: snapshot.id)
        let record = CKRecord(recordType: TrioCloudRecordCodec.recordType, recordID: id)
        record.encryptedValues["snapshot"] = bytes as NSData
        record.encryptedValues["fingerprint"] = snapshot.fingerprint as NSString
        #expect(try TrioCloudRecordCodec.snapshot(from: record).id == snapshot.id)
        record.encryptedValues["fingerprint"] = "wrong checksum" as NSString
        #expect(throws: BackupError.integrityCheckFailed) { _ = try TrioCloudRecordCodec.snapshot(from: record) }
        record.encryptedValues["fingerprint"] = snapshot.fingerprint as NSString
        let wrongID = CKRecord(
            recordType: TrioCloudRecordCodec.recordType,
            recordID: TrioCloudRecordCodec.recordID(for: UUID())
        )
        wrongID.encryptedValues["snapshot"] = bytes as NSData
        wrongID.encryptedValues["fingerprint"] = snapshot.fingerprint as NSString
        #expect(throws: BackupError.invalidCloudRecord) { _ = try TrioCloudRecordCodec.snapshot(from: wrongID) }
        // A payload stored as an asset is not accepted.
        let url = try directory().appendingPathComponent("backup.json")
        try bytes.write(to: url)
        record.encryptedValues["snapshot"] = nil
        record["snapshotAsset"] = CKAsset(fileURL: url)
        #expect(throws: BackupError.invalidCloudRecord) { _ = try TrioCloudRecordCodec.snapshot(from: record) }
        record["snapshotAsset"] = nil
        record.encryptedValues["snapshot"] = Data(repeating: 0, count: TrioSettingsBackup.maximumSize + 1) as NSData
        #expect(throws: BackupError.backupTooLarge) { _ = try TrioCloudRecordCodec.snapshot(from: record) }
    }

    @Test("A payload too large for one CloudKit record is refused instead of stored as an asset") func oversizedRecordPayload() throws {
        var configuration = validConfiguration()
        configuration.presets = .init(
            overrides: [],
            tempTargets: [],
            meals: (0 ..< 30000).map { .init(dish: "Meal number \($0)", carbs: 10, fat: 1, protein: 1) }
        )
        let snapshot = try makeBackup(configuration)
        let record = CKRecord(recordType: TrioCloudRecordCodec.recordType, recordID: TrioCloudRecordCodec.recordID(for: snapshot.id))
        #expect(throws: BackupError.backupTooLarge) { try TrioCloudRecordCodec.fill(record, with: snapshot) }
        #expect(record["snapshotAsset"] == nil)
        #expect(record.encryptedValues["snapshot"] == nil)
    }

    @MainActor
    @Test("A build without iCloud never queues or uploads anything") func unavailableStore() async throws {
        let directory = try directory()
        let queue = directory.appendingPathComponent("queue.json")
        let coordinator = TrioCloudBackupCoordinator(
            cloud: UnavailableCloudStore(),
            defaults: isolatedDefaults(),
            queueURL: queue,
            onboardingInProgress: { false },
            capture: { origin, name in try self.makeBackup(self.validConfiguration(), origin: origin, name: name) }
        )
        #expect(!coordinator.isAvailable)
        await coordinator.runAutomaticBackup()
        #expect(coordinator.lastError == nil)
        #expect(!FileManager.default.fileExists(atPath: queue.path))
        await #expect(throws: BackupError.iCloudUnavailable) { _ = try await coordinator.listBackups() }
    }

    @MainActor
    @Test("Automatic backups wait while a restore awaits review") func automaticBackupWaitsForReview() async throws {
        let cloud = CloudBackupFakeCloud()
        let defaults = isolatedDefaults()
        defaults.set(true, forKey: SettingsBackupRestore.reviewPendingKey)
        let coordinator = coordinator(cloud: cloud, directory: try directory(), defaults: defaults)
        await coordinator.runAutomaticBackup()
        #expect(cloud.uploads.isEmpty)
        defaults.removeObject(forKey: SettingsBackupRestore.reviewPendingKey)
        await coordinator.runAutomaticBackup()
        #expect(cloud.uploads.count == 1)
        coordinator.automaticEnabled = false
    }
}

@MainActor
final class CloudBackupConfigurationBox {
    var value: TrioSettingsBackup.Configuration
    init(value: TrioSettingsBackup.Configuration) { self.value = value }
}

final class CloudBackupFakeCloud: TrioCloudBackupStoring {
    var fail = false
    var uploads: [TrioSettingsBackup] = []
    var history: [BackupEntry] = []
    var downloads: [String: TrioSettingsBackup] = [:]
    var deleted: Set<String> = []
    func upload(_ snapshot: TrioSettingsBackup) async throws -> BackupEntry {
        if fail { throw BackupError.iCloudUnavailable }
        if !uploads.contains(where: { $0.id == snapshot.id }) { uploads.append(snapshot) }
        downloads[snapshot.id.uuidString] = snapshot
        return .init(
            id: snapshot.id.uuidString,
            createdAt: snapshot.createdAt,
            origin: snapshot.origin,
            name: snapshot.name,
            fingerprint: snapshot.fingerprint
        )
    }

    func list() async throws -> [BackupEntry] { if fail { throw BackupError.iCloudUnavailable }
        return history }

    func download(id: String) async throws -> TrioSettingsBackup {
        if fail { throw BackupError.iCloudUnavailable }
        guard let snapshot = downloads[id] else { throw BackupError.invalidCloudRecord }
        return snapshot
    }

    func delete(id: String) async throws {
        if fail { throw BackupError.iCloudUnavailable }
        deleted.insert(id)
        history.removeAll { $0.id == id }
        downloads.removeValue(forKey: id)
    }

    func rename(id _: String, name _: String) async throws -> BackupEntry { throw BackupError.invalidCloudRecord }
}

