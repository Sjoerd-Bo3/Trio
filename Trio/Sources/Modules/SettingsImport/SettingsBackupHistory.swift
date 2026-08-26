import CoreData
import Foundation

/// Builds and applies the optional treatment-history section of a settings backup.
///
/// Export reads everything the device still holds: all glucose readings, pump events and carb
/// entries in Core Data (Trio's cleanup retains about 90 days of each), TDD downsampled to the
/// newest sample per hour (plenty for Dynamic ISF's 10-day and 2-hour averages), and the
/// daily-TDD archive that feeds the one-year insulin statistics (up to 400 days).
///
/// Import reuses the migration `JSONImporter` with an unbounded window. It deduplicates by
/// date, so importing twice — or importing on a phone that already holds part of the data —
/// never duplicates entries. TDD samples are deduplicated the same way here, and daily TDD
/// totals only fill days the archive does not already cover.
enum SettingsBackupHistory {
    // MARK: - Export

    static func export(
        fileStorage: FileStorage,
        coreDataStack: CoreDataStack = .shared,
        now: Date = Date()
    ) async throws -> SettingsBackup.History {
        let context = coreDataStack.newTaskContext()
        context.name = "settingsBackupHistoryExport"

        var history = SettingsBackup.History()

        let glucose = try await exportGlucose(coreDataStack, context: context, end: now)
        history.glucose = glucose.isEmpty ? nil : glucose

        let pumpHistory = try await exportPumpHistory(coreDataStack, context: context, end: now)
        history.pumpHistory = pumpHistory.isEmpty ? nil : pumpHistory

        let carbs = try await exportCarbs(coreDataStack, context: context, end: now)
        history.carbs = carbs.isEmpty ? nil : carbs

        let tdd = try await exportTDD(coreDataStack, context: context, end: now)
        history.tdd = tdd.isEmpty ? nil : tdd

        if let archive = await fileStorage.retrieveAsync(TDDArchiveStore.fileName, as: TDDArchive.self),
           archive.days.isNotEmpty
        {
            history.tddDaily = archive.days
        }

        return history
    }

    private static func exportGlucose(
        _ coreDataStack: CoreDataStack,
        context: NSManagedObjectContext,
        end: Date
    ) async throws -> [BloodGlucose] {
        let results = try await coreDataStack.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: context,
            predicate: .predicateForDateBetween(start: .distantPast, end: end),
            key: "date",
            ascending: true
        )
        return try await context.perform {
            guard let stored = results as? [GlucoseStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }
            // Mirrors `BaseGlucoseStorage.mapToBloodGlucose`, but always exports the raw glucose
            // value (smoothing is re-applied on the importing phone) and keeps the manual-entry
            // marker: `JSONImporter` restores `isManual` from `type == "Manual"`.
            return stored.compactMap { entry in
                guard let date = entry.date else { return nil }
                let value = Int(entry.glucose)
                return BloodGlucose(
                    id: entry.id?.uuidString ?? UUID().uuidString,
                    sgv: entry.isManual ? nil : value,
                    direction: entry.direction.flatMap { BloodGlucose.Direction(rawValue: $0) },
                    date: Decimal(Int64(date.timeIntervalSince1970 * 1000)),
                    dateString: date,
                    glucose: entry.isManual ? value : nil,
                    type: entry.isManual ? "Manual" : "sgv"
                )
            }
        }
    }

    private static func exportPumpHistory(
        _ coreDataStack: CoreDataStack,
        context: NSManagedObjectContext,
        end: Date
    ) async throws -> [PumpHistoryEvent] {
        let results = try await coreDataStack.fetchEntitiesAsync(
            ofType: PumpEventStored.self,
            onContext: context,
            predicate: .predicateForTimestampBetween(start: .distantPast, end: end),
            key: "timestamp",
            ascending: true
        )
        return try await context.perform {
            guard let stored = results as? [PumpEventStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }
            // The oref event format: temp basals as rate + duration pairs — exactly what
            // `JSONImporter.importPumpHistory` recombines on the other side.
            return sanitizedPumpHistory(stored.flatMap { $0.toPumpHistoryEvents() })
        }
    }

    /// `JSONImporter.importPumpHistory` rejects a whole batch on duplicate (timestamp, type)
    /// pairs or non-alternating suspend/resume sequences. Over months of data a single stored
    /// anomaly would then discard the entire pump history, so those events are dropped here.
    static func sanitizedPumpHistory(_ events: [PumpHistoryEvent]) -> [PumpHistoryEvent] {
        struct TypeTimestamp: Hashable {
            let timestamp: Date
            let type: EventType
        }

        var seen = Set<TypeTimestamp>()
        var lastSuspendResumeType: EventType?
        var sanitized: [PumpHistoryEvent] = []
        sanitized.reserveCapacity(events.count)

        // Events arrive sorted by timestamp (ascending fetch).
        for event in events {
            guard seen.insert(TypeTimestamp(timestamp: event.timestamp, type: event.type)).inserted else { continue }
            if event.type == .pumpSuspend || event.type == .pumpResume {
                guard event.type != lastSuspendResumeType else { continue }
                lastSuspendResumeType = event.type
            }
            sanitized.append(event)
        }
        return sanitized
    }

    private static func exportCarbs(
        _ coreDataStack: CoreDataStack,
        context: NSManagedObjectContext,
        end: Date
    ) async throws -> [CarbsEntry] {
        let results = try await coreDataStack.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: context,
            // The importer skips FPU entries (carb equivalents), so they are not exported either.
            predicate: NSPredicate(format: "date <= %@ AND (isFPU == NO OR isFPU == nil)", end as NSDate),
            key: "date",
            ascending: true
        )
        return try await context.perform {
            guard let stored = results as? [CarbEntryStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }
            // Mirrors `BaseCarbsStorage.mapToCarbsEntry`, but keeps the entry note.
            return stored.compactMap { entry in
                guard let date = entry.date else { return nil }
                return CarbsEntry(
                    id: entry.id?.uuidString,
                    createdAt: date,
                    actualDate: date,
                    carbs: Decimal(algorithmValue: entry.carbs),
                    fat: Decimal(algorithmValue: entry.fat),
                    protein: Decimal(algorithmValue: entry.protein),
                    note: entry.note,
                    enteredBy: CarbsEntry.local,
                    isFPU: false,
                    fpuID: nil
                )
            }
        }
    }

    private static func exportTDD(
        _ coreDataStack: CoreDataStack,
        context: NSManagedObjectContext,
        end: Date
    ) async throws -> [SettingsBackup.TDDEntry] {
        let results = try await coreDataStack.fetchEntitiesAsync(
            ofType: TDDStored.self,
            onContext: context,
            predicate: NSPredicate(format: "date <= %@ AND total > 0", end as NSDate),
            key: "date",
            ascending: true
        )
        return try await context.perform {
            guard let stored = results as? [TDDStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }
            // TDD is stored every loop cycle (~288/day); the newest sample per hour is plenty
            // for Dynamic ISF's 10-day and 2-hour averages and for the daily statistics.
            var newestPerHour: [Date: SettingsBackup.TDDEntry] = [:]
            for entry in stored {
                guard let date = entry.date, let total = entry.total?.decimalValue, total > 0 else { continue }
                let hour = Date(
                    timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 3600).rounded(.down) * 3600
                )
                // Ascending fetch order — a later entry in the same hour replaces the earlier one.
                newestPerHour[hour] = SettingsBackup.TDDEntry(
                    date: date,
                    total: total,
                    bolus: entry.bolus?.decimalValue ?? 0,
                    tempBasal: entry.tempBasal?.decimalValue ?? 0,
                    scheduledBasal: entry.scheduledBasal?.decimalValue ?? 0,
                    weightedAverage: entry.weightedAverage?.decimalValue
                )
            }
            return newestPerHour.values.sorted { $0.date < $1.date }
        }
    }

    // MARK: - Preview

    struct HistoryCount: Identifiable {
        let id = UUID()
        let label: String
        let count: Int
    }

    /// Entry counts the change overview shows. Deduplication can only make the applied number
    /// smaller — entries the device already holds are never duplicated.
    static func previewCounts(_ history: SettingsBackup.History) -> [HistoryCount] {
        var counts: [HistoryCount] = []

        if let glucose = history.glucose, glucose.isNotEmpty {
            counts.append(HistoryCount(label: String(localized: "Glucose Readings"), count: glucose.count))
        }
        if let pumpHistory = history.pumpHistory, pumpHistory.isNotEmpty {
            // Rate + duration pairs merge into one temp basal event, so duration entries
            // are not counted separately.
            let events = pumpHistory.filter { $0.type != .tempBasalDuration }
            counts.append(HistoryCount(label: String(localized: "Pump Events"), count: events.count))
        }
        if let carbs = history.carbs, carbs.isNotEmpty {
            let entries = carbs.filter { $0.isFPU != true }
            counts.append(HistoryCount(label: String(localized: "Carb Entries"), count: entries.count))
        }
        if let tdd = history.tdd, tdd.isNotEmpty {
            counts.append(HistoryCount(label: String(localized: "TDD Samples"), count: tdd.count))
        }
        if let tddDaily = history.tddDaily, tddDaily.isNotEmpty {
            counts.append(HistoryCount(label: String(localized: "Daily TDD Totals"), count: tddDaily.count))
        }
        return counts
    }

    // MARK: - Import

    /// Applies the backup's history through the deduplicating importers. Never throws — every
    /// failed category becomes a warning, matching the rest of the import pipeline.
    static func apply(
        _ history: SettingsBackup.History,
        fileStorage: FileStorage,
        coreDataStack: CoreDataStack = .shared,
        now: Date = Date()
    ) async -> [String] {
        var warnings: [String] = []
        let importer = JSONImporter(context: coreDataStack.newTaskContext(), coreDataStack: coreDataStack)

        // The window start is each category's own oldest entry: nothing is cut off, and the
        // deduplication fetch stays bounded to the range the backup can actually touch.
        if let glucose = history.glucose, glucose.isNotEmpty {
            do {
                let start = glucose.map(\.dateString).min() ?? now
                try await importer.importGlucoseHistory(entries: glucose, now: now, start: start)
            } catch {
                warnings.append(String(localized: "Glucose history could not be imported: \(error.localizedDescription)"))
            }
        }

        if let pumpHistory = history.pumpHistory, pumpHistory.isNotEmpty {
            do {
                let start = pumpHistory.map(\.timestamp).min() ?? now
                // Sanitized again for backups written before export-side sanitization existed.
                try await importer.importPumpHistory(
                    entries: sanitizedPumpHistory(pumpHistory.sorted { $0.timestamp < $1.timestamp }),
                    now: now,
                    start: start
                )
            } catch {
                warnings.append(String(localized: "Pump history could not be imported: \(error.localizedDescription)"))
            }
        }

        if let carbs = history.carbs, carbs.isNotEmpty {
            do {
                let start = carbs.map { $0.actualDate ?? $0.createdAt }.min() ?? now
                try await importer.importCarbHistory(entries: carbs, now: now, start: start)
            } catch {
                warnings.append(String(localized: "Carb history could not be imported: \(error.localizedDescription)"))
            }
        }

        if let tdd = history.tdd, tdd.isNotEmpty {
            do {
                try await importTDD(tdd, coreDataStack: coreDataStack, now: now)
            } catch {
                warnings.append(String(localized: "TDD history could not be imported: \(error.localizedDescription)"))
            }
        }

        if let tddDaily = history.tddDaily, tddDaily.isNotEmpty {
            await importDailyTDD(tddDaily, fileStorage: fileStorage, now: now)
        }

        return warnings
    }

    /// TDD samples have no file-based importer to reuse, so the same recipe is applied here:
    /// date-based deduplication, background insert.
    static func importTDD(
        _ entries: [SettingsBackup.TDDEntry],
        coreDataStack: CoreDataStack = .shared,
        now: Date = Date()
    ) async throws {
        let candidates = entries.filter { $0.date <= now && $0.total > 0 }
        guard candidates.isNotEmpty else { return }
        let start = candidates.map(\.date).min() ?? now

        let context = coreDataStack.newTaskContext()
        context.name = "settingsBackupHistoryImportTDD"

        let results = try await coreDataStack.fetchEntitiesAsync(
            ofType: TDDStored.self,
            onContext: context,
            predicate: NSPredicate(format: "date >= %@ AND date <= %@", start as NSDate, now as NSDate),
            key: "date",
            ascending: false
        )
        let existingDates: Set<Date> = try await context.perform {
            guard let stored = results as? [TDDStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }
            return Set(stored.compactMap(\.date))
        }

        let newEntries = candidates.filter { !existingDates.contains($0.date) }
        guard newEntries.isNotEmpty else { return }

        try await context.perform {
            for entry in newEntries {
                let tddStored = TDDStored(context: context)
                tddStored.id = UUID()
                tddStored.date = entry.date
                tddStored.total = NSDecimalNumber(decimal: entry.total)
                tddStored.bolus = NSDecimalNumber(decimal: entry.bolus)
                tddStored.tempBasal = NSDecimalNumber(decimal: entry.tempBasal)
                tddStored.scheduledBasal = NSDecimalNumber(decimal: entry.scheduledBasal)
                tddStored.weightedAverage = entry.weightedAverage.map { NSDecimalNumber(decimal: $0) }
            }
            guard context.hasChanges else { return }
            try context.save()
        }
    }

    /// Merges imported daily TDD totals into the archive that feeds the one-year statistics.
    /// Same semantics as the Nightscout backfill: only days the archive does not already cover
    /// are filled, then the archive is pruned to its retention window.
    static func importDailyTDD(_ days: [String: Double], fileStorage: FileStorage, now: Date = Date()) async {
        var archive = await fileStorage.retrieveAsync(TDDArchiveStore.fileName, as: TDDArchive.self) ?? TDDArchive()
        for (key, value) in days where value > 0 && archive.days[key] == nil {
            archive.days[key] = value
        }
        archive.days = TDDArchiveStore.pruned(archive.days, now: now)
        await fileStorage.saveAsync(archive, as: TDDArchiveStore.fileName)
    }
}
