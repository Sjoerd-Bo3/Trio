import CoreData
import Foundation

/// Builds and applies the optional treatment-history section of a settings backup.
///
/// Export reads Core Data: the last 24 hours of glucose readings, pump events and carb entries
/// (the window the algorithm consumes), plus 10 days of TDD downsampled to the newest sample
/// per hour — enough for Dynamic ISF's weighted average without bloating the file.
///
/// Import reuses the migration `JSONImporter`, which enforces the same 24-hour window and
/// deduplicates by date, so importing twice — or importing on a phone that already holds part
/// of the data — never duplicates entries. TDD is deduplicated the same way here.
enum SettingsBackupHistory {
    static let tddExportDays = 10

    private static var tddWindow: TimeInterval { Double(tddExportDays) * 1.days.timeInterval }

    // MARK: - Export

    static func export(coreDataStack: CoreDataStack = .shared, now: Date = Date()) async throws -> SettingsBackup.History {
        let context = coreDataStack.newTaskContext()
        context.name = "settingsBackupHistoryExport"
        let dayAgo = now - 24.hours.timeInterval

        var history = SettingsBackup.History()

        let glucose = try await exportGlucose(coreDataStack, context: context, start: dayAgo, end: now)
        history.glucose = glucose.isEmpty ? nil : glucose

        let pumpHistory = try await exportPumpHistory(coreDataStack, context: context, start: dayAgo, end: now)
        history.pumpHistory = pumpHistory.isEmpty ? nil : pumpHistory

        let carbs = try await exportCarbs(coreDataStack, context: context, start: dayAgo, end: now)
        history.carbs = carbs.isEmpty ? nil : carbs

        let tdd = try await exportTDD(coreDataStack, context: context, start: now - tddWindow, end: now)
        history.tdd = tdd.isEmpty ? nil : tdd

        return history
    }

    private static func exportGlucose(
        _ coreDataStack: CoreDataStack,
        context: NSManagedObjectContext,
        start: Date,
        end: Date
    ) async throws -> [BloodGlucose] {
        let results = try await coreDataStack.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: context,
            predicate: .predicateForDateBetween(start: start, end: end),
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
        start: Date,
        end: Date
    ) async throws -> [PumpHistoryEvent] {
        let results = try await coreDataStack.fetchEntitiesAsync(
            ofType: PumpEventStored.self,
            onContext: context,
            predicate: .predicateForTimestampBetween(start: start, end: end),
            key: "timestamp",
            ascending: true
        )
        return try await context.perform {
            guard let stored = results as? [PumpEventStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }
            // The oref event format: temp basals as rate + duration pairs — exactly what
            // `JSONImporter.importPumpHistory` recombines on the other side.
            return stored.flatMap { $0.toPumpHistoryEvents() }
        }
    }

    private static func exportCarbs(
        _ coreDataStack: CoreDataStack,
        context: NSManagedObjectContext,
        start: Date,
        end: Date
    ) async throws -> [CarbsEntry] {
        let results = try await coreDataStack.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: context,
            // The importer skips FPU entries (carb equivalents), so they are not exported either.
            predicate: NSPredicate(
                format: "date >= %@ AND date <= %@ AND (isFPU == NO OR isFPU == nil)",
                start as NSDate,
                end as NSDate
            ),
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
        start: Date,
        end: Date
    ) async throws -> [SettingsBackup.TDDEntry] {
        let results = try await coreDataStack.fetchEntitiesAsync(
            ofType: TDDStored.self,
            onContext: context,
            predicate: NSPredicate(format: "date >= %@ AND date <= %@ AND total > 0", start as NSDate, end as NSDate),
            key: "date",
            ascending: true
        )
        return try await context.perform {
            guard let stored = results as? [TDDStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }
            // TDD is stored every loop cycle (~288/day); the newest sample per hour is plenty
            // for the 10-day and 2-hour averages Dynamic ISF computes.
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

    /// Entry counts the change overview shows: how many of the backup's entries are recent
    /// enough to be imported at all. Deduplication can only make the applied number smaller.
    static func previewCounts(_ history: SettingsBackup.History, now: Date = Date()) -> [HistoryCount] {
        let dayAgo = now - 24.hours.timeInterval
        var counts: [HistoryCount] = []

        if let glucose = history.glucose, glucose.isNotEmpty {
            let recent = glucose.filter { $0.dateString >= dayAgo && $0.dateString <= now }
            counts.append(HistoryCount(label: String(localized: "Glucose Readings"), count: recent.count))
        }
        if let pumpHistory = history.pumpHistory, pumpHistory.isNotEmpty {
            // Rate + duration pairs merge into one temp basal event, so duration entries
            // are not counted separately.
            let recent = pumpHistory.filter {
                $0.timestamp >= dayAgo && $0.timestamp <= now && $0.type != .tempBasalDuration
            }
            counts.append(HistoryCount(label: String(localized: "Pump Events"), count: recent.count))
        }
        if let carbs = history.carbs, carbs.isNotEmpty {
            let recent = carbs.filter {
                let date = $0.actualDate ?? $0.createdAt
                return date >= dayAgo && date <= now && $0.isFPU != true
            }
            counts.append(HistoryCount(label: String(localized: "Carb Entries"), count: recent.count))
        }
        if let tdd = history.tdd, tdd.isNotEmpty {
            let recent = tdd.filter { $0.date >= now - tddWindow && $0.date <= now && $0.total > 0 }
            counts.append(HistoryCount(label: String(localized: "TDD Samples"), count: recent.count))
        }
        return counts
    }

    // MARK: - Import

    /// Applies the backup's history through the deduplicating importers. Never throws — every
    /// failed or skipped category becomes a warning, matching the rest of the import pipeline.
    static func apply(
        _ history: SettingsBackup.History,
        coreDataStack: CoreDataStack = .shared,
        now: Date = Date()
    ) async -> [String] {
        var warnings: [String] = []
        var staleCategories: [String] = []
        let dayAgo = now - 24.hours.timeInterval
        let importer = JSONImporter(context: coreDataStack.newTaskContext(), coreDataStack: coreDataStack)

        if let glucose = history.glucose, glucose.isNotEmpty {
            if glucose.contains(where: { $0.dateString >= dayAgo && $0.dateString <= now }) {
                do {
                    try await importer.importGlucoseHistory(entries: glucose, now: now)
                } catch {
                    warnings.append(String(localized: "Glucose history could not be imported: \(error.localizedDescription)"))
                }
            } else {
                staleCategories.append(String(localized: "glucose readings"))
            }
        }

        if let pumpHistory = history.pumpHistory, pumpHistory.isNotEmpty {
            if pumpHistory.contains(where: { $0.timestamp >= dayAgo && $0.timestamp <= now }) {
                do {
                    try await importer.importPumpHistory(entries: pumpHistory, now: now)
                } catch {
                    warnings.append(String(localized: "Pump history could not be imported: \(error.localizedDescription)"))
                }
            } else {
                staleCategories.append(String(localized: "pump events"))
            }
        }

        if let carbs = history.carbs, carbs.isNotEmpty {
            if carbs.contains(where: { ($0.actualDate ?? $0.createdAt) >= dayAgo && ($0.actualDate ?? $0.createdAt) <= now }) {
                do {
                    try await importer.importCarbHistory(entries: carbs, now: now)
                } catch {
                    warnings.append(String(localized: "Carb history could not be imported: \(error.localizedDescription)"))
                }
            } else {
                staleCategories.append(String(localized: "carb entries"))
            }
        }

        if let tdd = history.tdd, tdd.isNotEmpty {
            do {
                try await importTDD(tdd, coreDataStack: coreDataStack, now: now)
            } catch {
                warnings.append(String(localized: "TDD history could not be imported: \(error.localizedDescription)"))
            }
        }

        if staleCategories.isNotEmpty {
            warnings.append(
                String(
                    localized: "The backup is older than 24 hours — its \(staleCategories.joined(separator: ", ")) were skipped."
                )
            )
        }

        return warnings
    }

    /// TDD has no file-based importer to reuse, so the same recipe is applied here: window
    /// filter, date-based deduplication, background insert.
    static func importTDD(
        _ entries: [SettingsBackup.TDDEntry],
        coreDataStack: CoreDataStack = .shared,
        now: Date = Date()
    ) async throws {
        let start = now - tddWindow
        let candidates = entries.filter { $0.date >= start && $0.date <= now && $0.total > 0 }
        guard candidates.isNotEmpty else { return }

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
}
