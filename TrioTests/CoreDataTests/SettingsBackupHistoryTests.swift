import CoreData
import Foundation
import Testing

@testable import Trio

/// The history section round-trips through real Core Data stacks: one stack plays the exporting
/// phone, a second freshly created stack plays the restored phone. The importers' date-based
/// deduplication makes a second apply a no-op.
@Suite("Settings Backup History Tests", .serialized) struct SettingsBackupHistoryTests {
    private func count<T: NSManagedObject>(of type: T.Type, in stack: CoreDataStack) async throws -> Int {
        let context = stack.newTaskContext()
        return try await context.perform {
            let request = NSFetchRequest<NSFetchRequestResult>(entityName: String(describing: type))
            return try context.count(for: request)
        }
    }

    private func seedExportStack(_ stack: CoreDataStack, now: Date) async throws {
        let context = stack.newTaskContext()
        try await context.perform {
            let glucose = GlucoseStored(context: context)
            glucose.id = UUID()
            glucose.date = now.addingTimeInterval(-10 * 60)
            glucose.glucose = 120
            glucose.direction = BloodGlucose.Direction.flat.rawValue
            glucose.isManual = false

            let bolusEvent = PumpEventStored(context: context)
            bolusEvent.id = "bolus-1"
            bolusEvent.timestamp = now.addingTimeInterval(-30 * 60)
            bolusEvent.type = PumpEventStored.EventType.bolus.rawValue
            let bolus = BolusStored(context: context)
            bolus.amount = 1.5 as NSDecimalNumber
            bolus.isSMB = true
            bolus.isExternal = false
            bolusEvent.bolus = bolus

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

            // Two TDD samples in the same hour (downsampled to the newer one), one in another
            // hour, and one outside the 10-day window (dropped by the export).
            let tddDates: [(Date, Decimal)] = [
                (now.addingTimeInterval(-2 * 60 * 60), 38),
                (now.addingTimeInterval(-2 * 60 * 60 + 5 * 60), 38.5),
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
        let exportStack = try await CoreDataStack.createForTests()
        try await seedExportStack(exportStack, now: now)

        let history = try await SettingsBackupHistory.export(coreDataStack: exportStack, now: now)

        #expect(history.glucose?.count == 1)
        // One bolus plus the temp basal's rate + duration pair.
        #expect(history.pumpHistory?.count == 3)
        #expect(history.carbs?.count == 1)
        // Same-hour samples collapse to the newest; the 11-day-old sample is dropped.
        #expect(history.tdd?.count == 2)
        #expect(history.tdd?.contains { $0.total == 38.5 } == true)
        #expect(history.tdd?.contains { $0.total == 38 } == false)

        // JSON round trip, exactly like a real backup file.
        let decoded = try JSONCoding.decoder.decode(
            SettingsBackup.History.self,
            from: JSONCoding.encoder.encode(history)
        )

        let importStack = try await CoreDataStack.createForTests()
        let warnings = await SettingsBackupHistory.apply(decoded, coreDataStack: importStack, now: now)
        #expect(warnings.isEmpty)

        #expect(try await count(of: GlucoseStored.self, in: importStack) == 1)
        #expect(try await count(of: PumpEventStored.self, in: importStack) == 2)
        #expect(try await count(of: CarbEntryStored.self, in: importStack) == 1)
        #expect(try await count(of: TDDStored.self, in: importStack) == 2)

        let context = importStack.newTaskContext()
        try await context.perform {
            let glucoseRequest: NSFetchRequest<GlucoseStored> = GlucoseStored.fetchRequest()
            let glucose = try context.fetch(glucoseRequest)
            #expect(glucose.first?.glucose == 120)
            #expect(glucose.first?.isManual == false)

            let pumpRequest: NSFetchRequest<PumpEventStored> = PumpEventStored.fetchRequest()
            let pumpEvents = try context.fetch(pumpRequest)
            let bolus = pumpEvents.first { $0.type == PumpEventStored.EventType.bolus.rawValue }
            #expect(bolus?.bolus?.amount == 1.5 as NSDecimalNumber)
            #expect(bolus?.bolus?.isSMB == true)
            let tempBasal = pumpEvents.first { $0.type == PumpEventStored.EventType.tempBasal.rawValue }
            #expect(tempBasal?.tempBasal?.rate == 0.85 as NSDecimalNumber)
            #expect(tempBasal?.tempBasal?.duration == 30)

            let carbsRequest: NSFetchRequest<CarbEntryStored> = CarbEntryStored.fetchRequest()
            let carbs = try context.fetch(carbsRequest)
            #expect(carbs.first?.carbs == 45)
            #expect(carbs.first?.note == "Lunch")
        }

        // A second apply finds every date already present and imports nothing.
        let secondWarnings = await SettingsBackupHistory.apply(decoded, coreDataStack: importStack, now: now)
        #expect(secondWarnings.isEmpty)
        #expect(try await count(of: GlucoseStored.self, in: importStack) == 1)
        #expect(try await count(of: PumpEventStored.self, in: importStack) == 2)
        #expect(try await count(of: CarbEntryStored.self, in: importStack) == 1)
        #expect(try await count(of: TDDStored.self, in: importStack) == 2)
    }

    @Test("A stale backup skips the 24-hour categories but still imports TDD") func testStaleBackup() async throws {
        let exportDate = Date().addingTimeInterval(-30 * 60 * 60)
        let history = SettingsBackupTestFixtures.history(around: exportDate)

        let importStack = try await CoreDataStack.createForTests()
        let warnings = await SettingsBackupHistory.apply(history, coreDataStack: importStack)

        #expect(warnings.count == 1)
        #expect(warnings.first?.contains("older than 24 hours") == true)
        #expect(try await count(of: GlucoseStored.self, in: importStack) == 0)
        #expect(try await count(of: PumpEventStored.self, in: importStack) == 0)
        #expect(try await count(of: CarbEntryStored.self, in: importStack) == 0)
        #expect(try await count(of: TDDStored.self, in: importStack) == 2)
    }

    @Test("Preview counts respect the import windows") func testPreviewCounts() throws {
        let now = Date()
        let fresh = SettingsBackupTestFixtures.history(around: now)

        let freshCounts = SettingsBackupHistory.previewCounts(fresh, now: now)
        #expect(freshCounts.count == 4)
        // Bolus + temp basal — the duration half of the pair is not its own entry.
        #expect(freshCounts.map(\.count) == [1, 2, 1, 2])

        let staleCounts = SettingsBackupHistory.previewCounts(fresh, now: now.addingTimeInterval(30 * 60 * 60))
        #expect(staleCounts.map(\.count) == [0, 0, 0, 2])
    }
}
