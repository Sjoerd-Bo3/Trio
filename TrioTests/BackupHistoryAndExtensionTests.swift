import CoreData
import Foundation
import Testing
@testable import Trio

private struct RecordingProvider: BackupExtensionProvider {
    let id: String
    var captured: Data?
    var failing = false
    let log: ExtensionLog

    func capture() async -> Data? { captured }

    func restore(_ data: Data, context: BackupExtensionRestoreContext) async throws {
        if failing { throw BackupError.restoreFailed }
        log.restored.append((id, data, context.isOnboarding))
    }

    func preview(_ data: Data) -> [ImportChange] {
        [ImportChange(label: id, oldDisplay: "—", newDisplay: "\(data.count) bytes")]
    }
}

private final class ExtensionLog: @unchecked Sendable {
    var restored: [(String, Data, Bool)] = []
}

@Suite("Backup History And Extensions", .serialized) struct BackupHistoryAndExtensionTests {
    private func tier(around date: Date = Date()) -> BackupHistoryTier {
        let glucoseDate = date.addingTimeInterval(-600)
        return BackupHistoryTier(
            glucose: [BloodGlucose(
                id: "11111111-1111-1111-1111-111111111111",
                sgv: 120,
                direction: .flat,
                date: Decimal(Int64(glucoseDate.timeIntervalSince1970 * 1000)),
                dateString: glucoseDate,
                glucose: nil,
                type: "sgv"
            )],
            pumpHistory: nil,
            carbs: [CarbsEntry(
                id: "22222222-2222-2222-2222-222222222222",
                createdAt: date.addingTimeInterval(-2700),
                actualDate: date.addingTimeInterval(-2700),
                carbs: 45,
                fat: 10,
                protein: 5,
                note: "Lunch",
                enteredBy: CarbsEntry.local,
                isFPU: false,
                fpuID: nil
            )],
            tdd: [BackupHistoryTier.TDDEntry(
                date: date.addingTimeInterval(-7200),
                total: 38.5,
                bolus: 20,
                tempBasal: 10,
                scheduledBasal: 8.5,
                weightedAverage: 37.2
            )]
        )
    }

    private func count<T: NSManagedObject>(of type: T.Type, in stack: CoreDataStack) async throws -> Int {
        let context = stack.newTaskContext()
        return try await context.perform {
            try context.count(for: NSFetchRequest<NSFetchRequestResult>(entityName: String(describing: type)))
        }
    }

    // MARK: - Tier in the snapshot

    @Test("The history tier travels as checked bytes and leaves the configuration fingerprint alone") func tierChecksum() throws {
        let base = BackupSnapshotTests()
        let plain = try base.makeBackup(base.validConfiguration())
        let withHistory = try plain.withTreatmentHistory(tier())
        #expect(withHistory.fingerprint == plain.fingerprint)
        #expect(withHistory.treatmentHistoryChecksum != nil)

        let opened = try BackupFileService.open(JSONEncoder().encode(withHistory)).snapshot
        let decoded = try #require(try opened.historyTier())
        #expect(decoded.glucose?.count == 1 && decoded.carbs?.first?.note == "Lunch")
        #expect(decoded.tdd?.first?.total == 38.5)

        var tampered = withHistory
        tampered.treatmentHistory = Data("{}".utf8)
        #expect(throws: BackupError.integrityCheckFailed) { _ = try tampered.validated() }
    }

    @Test("An empty tier is dropped and a backup without history reads as before") func emptyTier() throws {
        let base = BackupSnapshotTests()
        let plain = try base.makeBackup(base.validConfiguration())
        let none = try plain.withTreatmentHistory(BackupHistoryTier())
        #expect(none.treatmentHistory == nil && none.treatmentHistoryChecksum == nil)
        #expect(try none.historyTier() == nil)
    }

    @Test("Only a backup with history may exceed the configuration size limit") func sizeLimits() throws {
        let base = BackupSnapshotTests()
        let plain = try base.makeBackup(base.validConfiguration())
        var padded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(plain)) as? [String: Any] ?? [:]
        padded["futureTier"] = String(repeating: "x", count: TrioSettingsBackup.maximumSize)
        let large = try JSONSerialization.data(withJSONObject: padded)
        #expect(throws: BackupError.backupTooLarge) { _ = try BackupFileService.open(large) }
        #expect(TrioSettingsBackup.maximumFileSize > TrioSettingsBackup.maximumSize)
    }

    @Test("An older file's history becomes the history tier") func legacyHistory() throws {
        var legacy = SettingsBackupTestFixtures.fullBackup()
        let date = Date(timeIntervalSince1970: 1_750_000_000)
        let current = tier(around: date)
        legacy.history = SettingsBackup.History(
            glucose: current.glucose,
            pumpHistory: nil,
            carbs: current.carbs,
            tdd: [SettingsBackup.TDDEntry(
                date: date,
                total: 40,
                bolus: 20,
                tempBasal: 10,
                scheduledBasal: 10,
                weightedAverage: nil
            )],
            tddDaily: ["2025-06-01": 39.5]
        )
        let opened = try BackupFileService.open(JSONCoding.encoder.encode(legacy))
        let restored = try #require(try opened.snapshot.historyTier())
        #expect(restored.glucose?.count == 1 && restored.tdd?.count == 1)
        #expect(!opened.warnings.isEmpty)
    }

    // MARK: - Core Data

    @Test("History round-trips between two stacks and importing again changes nothing") func roundTripAndDedup() async throws {
        let now = Date()
        let source = try await CoreDataStack.createForTests()
        let seed = source.newTaskContext()
        try await seed.perform {
            let glucose = GlucoseStored(context: seed)
            glucose.id = UUID()
            glucose.date = now.addingTimeInterval(-600)
            glucose.glucose = 120
            glucose.direction = BloodGlucose.Direction.flat.rawValue
            glucose.isManual = false
            let carbs = CarbEntryStored(context: seed)
            carbs.id = UUID()
            carbs.date = now.addingTimeInterval(-2700)
            carbs.carbs = 45
            carbs.fat = 10
            carbs.protein = 5
            carbs.isFPU = false
            let tdd = TDDStored(context: seed)
            tdd.id = UUID()
            tdd.date = now.addingTimeInterval(-7200)
            tdd.total = 38.5 as NSDecimalNumber
            tdd.bolus = 20
            tdd.tempBasal = 10
            tdd.scheduledBasal = 8.5 as NSDecimalNumber
            try seed.save()
        }
        let exported = try await SettingsBackupHistory.export(coreDataStack: source, now: now)
        #expect(exported.glucose?.count == 1 && exported.carbs?.count == 1 && exported.tdd?.count == 1)

        let target = try await CoreDataStack.createForTests()
        #expect(await SettingsBackupHistory.apply(exported, coreDataStack: target, now: now).isEmpty)
        let afterFirst = try await (
            count(of: GlucoseStored.self, in: target),
            count(of: CarbEntryStored.self, in: target),
            count(of: TDDStored.self, in: target)
        )
        #expect(afterFirst == (1, 1, 1))
        #expect(await SettingsBackupHistory.apply(exported, coreDataStack: target, now: now).isEmpty)
        let afterSecond = try await (
            count(of: GlucoseStored.self, in: target),
            count(of: CarbEntryStored.self, in: target),
            count(of: TDDStored.self, in: target)
        )
        #expect(afterSecond == afterFirst)
    }

    // MARK: - Extensions

    @Test("The registry ships empty and restores only the data of registered providers") func registry() async throws {
        BackupExtensionRegistry.unregisterAll()
        defer { BackupExtensionRegistry.unregisterAll() }
        #expect(BackupExtensionRegistry.providers.isEmpty)
        #expect(await BackupExtensionRegistry.captureAll().isEmpty)

        let log = ExtensionLog()
        BackupExtensionRegistry.register(RecordingProvider(id: "profiles", captured: Data("abc".utf8), log: log))
        BackupExtensionRegistry.register(RecordingProvider(id: "broken", captured: Data("x".utf8), failing: true, log: log))
        BackupExtensionRegistry.register(RecordingProvider(id: "empty", captured: nil, log: log))
        BackupExtensionRegistry.register(RecordingProvider(id: "profiles", captured: Data("abcd".utf8), log: log))
        #expect(BackupExtensionRegistry.providers.count == 3)

        let captured = await BackupExtensionRegistry.captureAll()
        #expect(captured == ["profiles": Data("abcd".utf8), "broken": Data("x".utf8)])

        var saved = captured
        saved["unknown"] = Data("ignored".utf8)
        let warnings = await BackupExtensionRegistry.restoreAll(
            saved,
            context: BackupExtensionRestoreContext(snapshotID: UUID(), isOnboarding: true)
        )
        #expect(warnings.count == 1)
        #expect(log.restored.map(\.0) == ["profiles"] && log.restored.first?.2 == true)
        #expect(BackupExtensionRegistry.preview(saved).map(\.label).sorted() == ["broken", "profiles"])
    }

    @Test("Extension data travels in the snapshot without touching the fingerprint") func extensionsInSnapshot() throws {
        let base = BackupSnapshotTests()
        var snapshot = try base.makeBackup(base.validConfiguration())
        snapshot.extensions = ["profiles": Data("abc".utf8)]
        let decoded = try BackupFileService.open(JSONEncoder().encode(snapshot)).snapshot
        #expect(decoded.extensions == ["profiles": Data("abc".utf8)])
        #expect(decoded.fingerprint == snapshot.fingerprint)
    }
}
