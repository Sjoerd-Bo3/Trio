import CloudKit
import Foundation

/// Whether iCloud backups can be used on this build and this phone.
enum CloudBackupAvailability {
    enum Status: Equatable {
        /// This build was made without the iCloud capability (`ENABLE_ICLOUD_BACKUP = NO`).
        case notBuilt
        case noAccount
        case available
    }

    /// True when the app was built with the CloudKit entitlement. Everything cloud related stays hidden otherwise.
    static var isBuiltWithCloudKit: Bool {
        #if TRIO_ICLOUD_BACKUP
            true
        #else
            false
        #endif
    }

    static func status() async -> Status {
        #if TRIO_ICLOUD_BACKUP
            let status = try? await CKContainer.default().accountStatus()
            return status == .available ? .available : .noAccount
        #else
            return .notBuilt
        #endif
    }
}

/// Private CloudKit storage with encrypted payload, fingerprint, and name fields.
protocol TrioCloudBackupStoring {
    /// False for builds without the iCloud capability; nothing is queued or uploaded then.
    var isAvailable: Bool { get }
    func upload(_ snapshot: TrioSettingsBackup) async throws -> BackupEntry
    func list() async throws -> [BackupEntry]
    func download(id: String) async throws -> TrioSettingsBackup
    func delete(id: String) async throws
    func rename(id: String, name: String) async throws -> BackupEntry
}

extension TrioCloudBackupStoring {
    var isAvailable: Bool { true }
}

/// Stands in for the real store in builds without the iCloud capability.
struct UnavailableCloudStore: TrioCloudBackupStoring {
    var isAvailable: Bool { false }
    func upload(_: TrioSettingsBackup) async throws -> BackupEntry { throw BackupError.iCloudUnavailable }
    func list() async throws -> [BackupEntry] { throw BackupError.iCloudUnavailable }
    func download(id _: String) async throws -> TrioSettingsBackup { throw BackupError.iCloudUnavailable }
    func delete(id _: String) async throws { throw BackupError.iCloudUnavailable }
    func rename(id _: String, name _: String) async throws -> BackupEntry { throw BackupError.iCloudUnavailable }
}

/// Record encoding shared by every build, so it can be tested without an iCloud account.
enum TrioCloudRecordCodec {
    static let recordType = "TrioSettingsBackup"
    static let zoneName = "TrioBackups"
    static let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
    /// A CloudKit record is limited to 1 MB in total.
    static let maximumPayloadSize = 750_000

    static func recordID(for id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
    }

    /// Every payload field lives in `encryptedValues`; only the fields the list needs for ordering and
    /// display are stored in the clear. Backups are never stored as assets, which CloudKit does not encrypt.
    static func fill(_ record: CKRecord, with candidate: TrioSettingsBackup) throws {
        let snapshot = try candidate.validated()
        let bytes = try JSONEncoder().encode(snapshot)
        guard bytes.count <= TrioSettingsBackup.maximumSize, bytes.count <= maximumPayloadSize else {
            throw BackupError.backupTooLarge
        }
        record["createdAt"] = snapshot.createdAt as NSDate
        record["origin"] = snapshot.origin.rawValue as NSString
        record["appVersion"] = snapshot.appVersion as NSString
        record["schemaVersion"] = snapshot.schemaVersion as NSNumber
        record.encryptedValues["fingerprint"] = snapshot.fingerprint as NSString
        record.encryptedValues["name"] = snapshot.name as NSString?
        record.encryptedValues["snapshot"] = bytes as NSData
    }

    static func snapshot(from record: CKRecord) throws -> TrioSettingsBackup {
        guard let fingerprint = record.encryptedValues["fingerprint"] as? String,
              let bytes = record.encryptedValues["snapshot"] as? Data
        else { throw BackupError.invalidCloudRecord }
        guard bytes.count <= TrioSettingsBackup.maximumSize else { throw BackupError.backupTooLarge }
        let snapshot = try TrioSettingsBackup.decode(bytes, expectedFingerprint: fingerprint)
        guard snapshot.id.uuidString == record.recordID.recordName else { throw BackupError.invalidCloudRecord }
        return snapshot
    }

    static func entry(from record: CKRecord) throws -> BackupEntry {
        guard let date = record["createdAt"] as? Date,
              let originName = record["origin"] as? String,
              let origin = TrioSettingsBackup.Origin(rawValue: originName),
              let fingerprint = record.encryptedValues["fingerprint"] as? String
        else { throw BackupError.invalidCloudRecord }
        return BackupEntry(
            id: record.recordID.recordName,
            createdAt: date,
            origin: origin,
            name: record.encryptedValues["name"] as? String,
            fingerprint: fingerprint,
            appVersion: record["appVersion"] as? String,
            schemaVersion: (record["schemaVersion"] as? NSNumber)?.intValue
        )
    }
}

#if TRIO_ICLOUD_BACKUP
    /// Private-database storage in a dedicated record zone.
    final class TrioCloudBackupStore: TrioCloudBackupStoring {
        private let container: CKContainer
        private var zoneReady = false

        init(container: CKContainer = .default()) {
            self.container = container
        }

        private var database: CKDatabase { container.privateCloudDatabase }

        func checkAvailability() async throws {
            let status = try await container.accountStatus()
            guard status == .available else { throw BackupError.iCloudUnavailable }
            if !zoneReady {
                _ = try await database.save(CKRecordZone(zoneID: TrioCloudRecordCodec.zoneID))
                zoneReady = true
            }
        }

        func upload(_ snapshot: TrioSettingsBackup) async throws -> BackupEntry {
            try await checkAvailability()
            let record = CKRecord(recordType: TrioCloudRecordCodec.recordType, recordID: TrioCloudRecordCodec.recordID(for: snapshot.id))
            do {
                try TrioCloudRecordCodec.fill(record, with: snapshot)
                return try TrioCloudRecordCodec.entry(from: await database.save(record))
            } catch let error as CKError where error.code == .serverRecordChanged {
                // Retries reuse the UUID and preserve any server-side rename.
                let existing = try await database.record(for: record.recordID)
                let saved = try TrioCloudRecordCodec.snapshot(from: existing)
                guard try saved.matchesUploadedSnapshot(snapshot.validated()) else { throw BackupError.integrityCheckFailed }
                return try TrioCloudRecordCodec.entry(from: existing)
            }
        }

        func rename(id: String, name: String) async throws -> BackupEntry {
            try await checkAvailability()
            guard let name = TrioSettingsBackup.normalizedName(name) else { throw BackupError.backupNameRequired }
            let record = try await database.record(for: CKRecord.ID(recordName: id, zoneID: TrioCloudRecordCodec.zoneID))
            var snapshot = try TrioCloudRecordCodec.snapshot(from: record)
            guard snapshot.origin == .manual else { throw BackupError.invalidCloudRecord }
            snapshot.name = name
            // The record's change tag prevents overwriting concurrent renames.
            try TrioCloudRecordCodec.fill(record, with: snapshot)
            return try TrioCloudRecordCodec.entry(from: await database.save(record))
        }

        func list() async throws -> [BackupEntry] {
            try await checkAvailability()
            let query = CKQuery(recordType: TrioCloudRecordCodec.recordType, predicate: NSPredicate(value: true))
            let keys = ["createdAt", "origin", "fingerprint", "name", "appVersion", "schemaVersion"]
            var page = try await database.records(matching: query, inZoneWith: TrioCloudRecordCodec.zoneID, desiredKeys: keys)
            var entries: [BackupEntry] = []
            while true {
                for (id, result) in page.matchResults {
                    do {
                        entries.append(try TrioCloudRecordCodec.entry(from: result.get()))
                    } catch {
                        // Keep an unavailable/corrupt record visible instead of hiding history.
                        entries.append(BackupEntry(
                            id: id.recordName,
                            createdAt: .distantPast,
                            origin: .automatic,
                            name: "Unavailable Backup",
                            fingerprint: "",
                            validationMessage: error.localizedDescription
                        ))
                    }
                }
                guard let cursor = page.queryCursor else { break }
                page = try await database.records(continuingMatchFrom: cursor, desiredKeys: keys)
            }
            return entries.sorted { $0.createdAt > $1.createdAt }
        }

        func download(id: String) async throws -> TrioSettingsBackup {
            try await checkAvailability()
            let record = try await database.record(for: CKRecord.ID(recordName: id, zoneID: TrioCloudRecordCodec.zoneID))
            return try TrioCloudRecordCodec.snapshot(from: record)
        }

        func delete(id: String) async throws {
            try await checkAvailability()
            do { _ = try await database.deleteRecord(withID: CKRecord.ID(recordName: id, zoneID: TrioCloudRecordCodec.zoneID)) }
            catch let error as CKError where error.code == .unknownItem { /* Already deleted by another device. */ }
        }
    }
#endif
