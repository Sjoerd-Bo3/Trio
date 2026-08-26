import CoreData
import Foundation
import Testing

@testable import Trio

/// The history section round-trips through real Core Data stacks: one stack plays the exporting
/// phone, a second freshly created stack plays the restored phone. The importers' date-based
/// deduplication makes a second apply a no-op. The daily-TDD archive file in the documents
/// directory is snapshotted and restored around the tests that touch it.
@Suite("Settings Backup History Tests", .serialized) struct SettingsBackupHistoryTests {
    private let fileStorage = BaseFileStorage()

    private func count<T: NSManagedObject>(of type: T.Type, in stack: CoreDataStack) async throws -> Int {
        let context = stack.newTaskContext()
        return try await context.perform {
            let request = NSFetchRequest<NSFetchRequestResult>(entityName: String(describing: type))
            return try context.count(for: request)
        }
    }

    /// Runs `body` with the daily-TDD archive replaced by `archive` (nil = no file), restoring
    /// the pre-test archive afterwards.
    private func withArchive(_ archive: TDDArchive?, _ body: () async throws -> Void) async rethrows {
        let snapshot = fileStorage.retrieve(TDDArchiveStore.fileName, as: TDDArchive.self)
        if let archive = archive {
            fileStorage.save(archive, as: TDDArchiveStore.fileName)
        } else {
            fileStorage.remove(TDDArchiveStore.fileName)
        }
        defer {
            if let snapshot = snapshot {
                fileStorage.save(snapshot, as: TDDArchiveStore.fileName)
            } else {
                fileStorage.remove(TDDArchiveStore.fileName)
            }
        }
        try await body()
    }

    private func seedExportStack(_ stack: CoreDataStack, now: Date) async throws {
        let context = stack.newTaskContext()
        try await context.perform {
            // Recent and weeks-old entries — the export carries everything the stack holds.
            let glucoseDates = [now.addingTimeInterval(-10 * 60), now.addingTimeInterval(-40 * 24 * 60 * 60)]
            for (index, date) in glucoseDates.enumerated() {
                let glucose = GlucoseStored(context: context)
                glucose.id = UUID()
                glucose.date = date
                glucose.glucose = Int16(120 + index)
                glucose.direction = BloodGlucose.Direction.flat.rawValue
                glucose.isManual = false
            }

            let bolusDates = [now.addingTimeInterval(-30 * 60), now.addingTimeInterval(-5 * 24 * 60 * 60)]
            for (index, date) in bolusDates.enumerated() {
                let bolusEvent = PumpEventStored(context: context)
                bolusEvent.id = "bolus-\(index)"
                bolusEvent.timestamp = date
                bolusEvent.type = PumpEventStored.EventType.bolus.rawValue
                let bolus = BolusStored(context: context)
                bolus.amount = 1.5 as NSDecimalNumber
                bolus.isSMB = index == 0
                bolus.isExternal = false
                bolusEvent.bolus = bolus
            }

            // Exact duplicate of the first bolus (same timestamp, same type, different row) —
            // export sanitization must drop it or the strict importer would reject the batch.
            let duplicateBolusEvent = PumpEventStored(context: context)
            duplicateBolusEvent.id = "bolus-duplicate"
            duplicateBolusEvent.timestamp = bolusDates[0]
            duplicateBolusEvent.type = PumpEventStored.EventType.bolus.rawValue
            let duplicateBolus = BolusStored(context: context)
            duplicateBolus.amount = 1.5 as NSDecimalNumber
            duplicateBolus.isSMB = false
            duplicateBolus.isExternal = false
            duplicateBolusEvent.bolus = duplicateBolus

            let tempBasalEvent = PumpEventStored(context: context)
            tempBasalEvent.id = "temp-1"
            tempBasalEvent.timestamp = now.addingTimeInterval(-60 * 60)
            tempBasalEvent.type = PumpEventStored.EventType.tempBasal.rawValue
            let tempBasal = TempBasalStored(context: context)
            tempBasal.rate = 0.85 as NSDecimalNumber
            tempBasal.duration = 30
            tempBasal.tempType = PumpEventStored.TempType.absolute.rawValue
            tempBasalEvent.tempBasal = tempBasal

            let carbs = CarbEntryStored(context: context)
            carbs.id = UUID()
            carbs.date = now.addingTimeInterval(-45 * 60)
            carbs.carbs = 45
            carbs.fat = 10
            carbs.protein = 5
            carbs.note = "Lunch"
            carbs.isFPU = false

            // Two TDD samples in the same clock hour (downsampled to the newer one) and two
            // older samples — the export has no date cutoff. Anchored to an hour boundary so
            // the pair can never straddle two buckets.
            let hourAnchor = Date(
                timeIntervalSinceReferenceDate: (now.timeIntervalSinceReferenceDate / 3600).rounded(.down) * 3600
            )
            let tddDates: [(Date, Decimal)] = [
                (hourAnchor.addingTimeInterval(-90 * 60), 38),
                (hourAnchor.addingTimeInterval(-85 * 60), 38.5),
                (now.addingTimeInterval(-26 * 60 * 60), 41),
                (now.addingTimeInterval(-11 * 24 * 60 * 60), 44)
            ]
            for (date, total) in tddDates {
                let tdd = TDDStored(context: context)
                tdd.id = UUID()
                tdd.date = date
                tdd.total = NSDecimalNumber(decimal: total)
                tdd.bolus = 20
                tdd.tempBasal = 10
                tdd.scheduledBasal = NSDecimalNumber(decimal: total - 30)
                tdd.weightedAverage = 37.2 as NSDecimalNumber
            }

            try context.save()
        }
    }

    @Test("History round-trips between two Core Data stacks and re-import is a no-op") func testRoundTrip() async throws {
        let now = Date()
        let seededDayKey = TDDArchiveStore.dayKey(for: now.addingTimeInterval(-8 * 24 * 60 * 60))

        try await withArchive(TDDArchive(days: [seededDayKey: 40.5])) {
            let exportStack = try await CoreDataStack.createForTests()
            try await seedExportStack(exportStack, now: now)

            let history = try await SettingsBackupHistory.export(fileStorage: fileStorage, coreDataStack: exportStack, now: now)

            #expect(history.glucose?.count == 2)
            // Two boluses plus the temp basal's rate + duration pair; the duplicate is dropped.
            #expect(history.pumpHistory?.count == 4)
            #expect(history.carbs?.count == 1)
            // Same-hour samples collapse to the newest; the older samples are all kept.
            #expect(history.tdd?.count == 3)
            #expect(history.tdd?.contains { $0.total == 38.5 } == true)
            #expect(history.tdd?.contains { $0.total == 38 } == false)
            #expect(history.tddDaily?[seededDayKey] == 40.5)

            // JSON round trip, exactly like a real backup file.
            let decoded = try JSONCoding.decoder.decode(
                SettingsBackup.History.self,
                from: JSONCoding.encoder.encode(history)
            )

            // The restored phone starts with an empty archive and an empty Core Data stack.
            fileStorage.remove(TDDArchiveStore.fileName)
            let importStack = try await CoreDataStack.createForTests()
            let warnings = await SettingsBackupHistory.apply(
                decoded,
                fileStorage: fileStorage,
                coreDataStack: importStack,
                now: now
            )
            #expect(warnings.isEmpty)

            #expect(try await count(of: GlucoseStored.self, in: importStack) == 2)
            #expect(try await count(of: PumpEventStored.self, in: importStack) == 3)
            #expect(try await count(of: CarbEntryStored.self, in: importStack) == 1)
            #expect(try await count(of: TDDStored.self, in: importStack) == 3)
            let restoredArchive = fileStorage.retrieve(TDDArchiveStore.fileName, as: TDDArchive.self)
            #expect(restoredArchive?.days[seededDayKey] == 40.5)

            let context = importStack.newTaskContext()
            try await context.perform {
                let glucoseRequest: NSFetchRequest<GlucoseStored> = GlucoseStored.fetchRequest()
                let glucose = try context.fetch(glucoseRequest)
                #expect(glucose.map(\.glucose).sorted() == [120, 121])
                #expect(glucose.allSatisfy { !$0.isManual })

                let pumpRequest: NSFetchRequest<PumpEventStored> = PumpEventStored.fetchRequest()
                let pumpEvents = try context.fetch(pumpRequest)
                let boluses = pumpEvents.filter { $0.type == PumpEventStored.EventType.bolus.rawValue }
                #expect(boluses.count == 2)
                #expect(boluses.allSatisfy { $0.bolus?.amount == 1.5 as NSDecimalNumber })
                let tempBasal = pumpEvents.first { $0.type == PumpEventStored.EventType.tempBasal.rawValue }
                #expect(tempBasal?.tempBasal?.rate == 0.85 as NSDecimalNumber)
                #expect(tempBasal?.tempBasal?.duration == 30)

                let carbsRequest: NSFetchRequest<CarbEntryStored> = CarbEntryStored.fetchRequest()
                let carbs = try context.fetch(carbsRequest)
                #expect(carbs.first?.carbs == 45)
                #expect(carbs.first?.note == "Lunch")
            }

            // A second apply finds every date already present and imports nothing.
            let secondWarnings = await SettingsBackupHistory.apply(
                decoded,
                fileStorage: fileStorage,
                coreDataStack: importStack,
                now: now
            )
            #expect(secondWarnings.isEmpty)
            #expect(try await count(of: GlucoseStored.self, in: importStack) == 2)
            #expect(try await count(of: PumpEventStored.self, in: importStack) == 3)
            #expect(try await count(of: CarbEntryStored.self, in: importStack) == 1)
            #expect(try await count(of: TDDStored.self, in: importStack) == 3)
        }
    }

    @Test("A backup from days ago still imports in full") func testOldBackupImportsInFull() async throws {
        let exportDate = Date().addingTimeInterval(-30 * 60 * 60)
        let history = SettingsBackupTestFixtures.history(around: exportDate)

        try await withArchive(nil) {
            let importStack = try await CoreDataStack.createForTests()
            let warnings = await SettingsBackupHistory.apply(history, fileStorage: fileStorage, coreDataStack: importStack)

            #expect(warnings.isEmpty)
            #expect(try await count(of: GlucoseStored.self, in: importStack) == 2)
            // Bolus + combined temp basal.
            #expect(try await count(of: PumpEventStored.self, in: importStack) == 2)
            #expect(try await count(of: CarbEntryStored.self, in: importStack) == 1)
            #expect(try await count(of: TDDStored.self, in: importStack) == 2)
            let archive = fileStorage.retrieve(TDDArchiveStore.fileName, as: TDDArchive.self)
            #expect(archive?.days.count == 2)
        }
    }

    @Test("Daily TDD totals only fill days the archive does not cover") func testDailyTDDMerge() async throws {
        let now = Date()
        let existingDayKey = TDDArchiveStore.dayKey(for: now.addingTimeInterval(-3 * 24 * 60 * 60))
        let newDayKey = TDDArchiveStore.dayKey(for: now.addingTimeInterval(-4 * 24 * 60 * 60))
        let ancientDayKey = TDDArchiveStore.dayKey(for: now.addingTimeInterval(-500 * 24 * 60 * 60))

        try await withArchive(TDDArchive(days: [existingDayKey: 36.0])) {
            await SettingsBackupHistory.importDailyTDD(
                [existingDayKey: 99.0, newDayKey: 41.0, ancientDayKey: 44.0],
                fileStorage: fileStorage,
                now: now
            )

            let archive = try #require(fileStorage.retrieve(TDDArchiveStore.fileName, as: TDDArchive.self))
            // The device's own value wins; the missing day is filled; days beyond the
            // 400-day retention are pruned.
            #expect(archive.days[existingDayKey] == 36.0)
            #expect(archive.days[newDayKey] == 41.0)
            #expect(archive.days[ancientDayKey] == nil)
        }
    }

    @Test("Pump history sanitization drops duplicates and unpaired suspend/resume") func testSanitizedPumpHistory() {
        let base = Date(timeIntervalSince1970: 1_750_000_000)
        let events = [
            PumpHistoryEvent(id: "a", type: .bolus, timestamp: base, amount: 1, duration: 0),
            PumpHistoryEvent(id: "b", type: .bolus, timestamp: base, amount: 2, duration: 0),
            PumpHistoryEvent(id: "c", type: .pumpResume, timestamp: base.addingTimeInterval(60)),
            PumpHistoryEvent(id: "d", type: .pumpSuspend, timestamp: base.addingTimeInterval(120)),
            PumpHistoryEvent(id: "e", type: .pumpSuspend, timestamp: base.addingTimeInterval(180)),
            PumpHistoryEvent(id: "f", type: .pumpResume, timestamp: base.addingTimeInterval(240))
        ]

        let sanitized = SettingsBackupHistory.sanitizedPumpHistory(events)

        #expect(sanitized.map(\.id) == ["a", "c", "d", "f"])
    }

    @Test("Preview counts cover every history category") func testPreviewCounts() {
        let history = SettingsBackupTestFixtures.history(around: Date())

        let counts = SettingsBackupHistory.previewCounts(history)

        #expect(counts.count == 5)
        // Glucose readings, pump events (bolus + temp basal — the duration half of the pair is
        // not its own entry), carb entries, TDD samples, daily TDD totals.
        #expect(counts.map(\.count) == [2, 2, 1, 2, 2])
    }
}
