import CoreData
import CryptoKit
import Foundation

/// The optional treatment-history tier of a backup: glucose readings, pump events, carb entries and
/// total-daily-dose samples. It is off unless the user asks for it when exporting a file.
struct BackupHistoryTier: Codable, Equatable {
    var glucose: [BloodGlucose]?
    var pumpHistory: [PumpHistoryEvent]?
    var carbs: [CarbsEntry]?
    var tdd: [TDDEntry]?

    struct TDDEntry: Codable, Equatable {
        var date: Date
        var total: Decimal
        var bolus: Decimal
        var tempBasal: Decimal
        var scheduledBasal: Decimal
        var weightedAverage: Decimal?
    }

    var isEmpty: Bool {
        (glucose?.isEmpty ?? true) && (pumpHistory?.isEmpty ?? true) && (carbs?.isEmpty ?? true) && (tdd?.isEmpty ?? true)
    }
}

extension TrioSettingsBackup {
    /// Files that carry treatment history may be much larger than a configuration-only backup.
    static let maximumFileSize = 64 * 1024 * 1024

    /// The history tier travels as encoded bytes with their own checksum, so it can be verified exactly as
    /// it was written and never changes the configuration fingerprint.
    func withTreatmentHistory(_ tier: BackupHistoryTier?) throws -> TrioSettingsBackup {
        var result = self
        guard let tier, !tier.isEmpty else {
            result.treatmentHistory = nil
            result.treatmentHistoryChecksum = nil
            return result
        }
        let bytes = try JSONCoding.encoder.encode(tier)
        result.treatmentHistory = bytes
        result.treatmentHistoryChecksum = Self.digest(bytes)
        return result
    }

    func historyTier() throws -> BackupHistoryTier? {
        guard let bytes = treatmentHistory else { return nil }
        guard treatmentHistoryChecksum == Self.digest(bytes) else { throw BackupError.integrityCheckFailed }
        return try JSONCoding.decoder.decode(BackupHistoryTier.self, from: bytes)
    }

    /// Checks the stored bytes against their checksum. The rows are only decoded when they are previewed or restored.
    func validateTreatmentHistory() throws {
        guard let bytes = treatmentHistory else { return }
        guard treatmentHistoryChecksum == Self.digest(bytes) else { throw BackupError.integrityCheckFailed }
    }
}

/// Builds and applies the treatment-history tier.
///
/// Export reads everything the device still holds in Core Data (Trio's cleanup keeps about 90 days). Import
/// reuses the migration importer with an unbounded window; it deduplicates by date, so importing twice, or onto
/// a phone that already holds part of the data, never duplicates an entry.
enum SettingsBackupHistory {
    // MARK: - Export

    static func export(coreDataStack: CoreDataStack = .shared, now: Date = Date()) async throws -> BackupHistoryTier {
        let context = coreDataStack.newTaskContext()
        context.name = "settingsBackupHistoryExport"
        var history = BackupHistoryTier()

        let glucose = try await exportGlucose(coreDataStack, context: context, end: now)
        history.glucose = glucose.isEmpty ? nil : glucose
        let pumpHistory = try await exportPumpHistory(coreDataStack, context: context, end: now)
        history.pumpHistory = pumpHistory.isEmpty ? nil : pumpHistory
        let carbs = try await exportCarbs(coreDataStack, context: context, end: now)
        history.carbs = carbs.isEmpty ? nil : carbs
        let tdd = try await exportTDD(coreDataStack, context: context, end: now)
        history.tdd = tdd.isEmpty ? nil : tdd
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
            // Always the raw value (smoothing is applied again on the restoring phone). Manual entries keep
            // their marker: the importer restores `isManual` from `type == "Manual"`.
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
            // Scheduled-basal rows are derived data, and rows still being delivered are not final.
            predicate: NSPredicate(
                format: "timestamp <= %@ AND (tempBasal == nil OR tempBasal.isScheduledBasal == NO) AND isMutable == NO",
                end as NSDate
            ),
            key: "timestamp",
            ascending: true
        )
        return try await context.perform {
            guard let stored = results as? [PumpEventStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }
            return sanitizedPumpHistory(stored.flatMap { $0.toPumpHistoryEvents() })
        }
    }

    /// The importer rejects a whole batch on duplicate (timestamp, type) pairs or non-alternating
    /// suspend/resume sequences. Over months of data a single stored anomaly would discard the entire pump
    /// history, so those events are dropped here.
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
            // The importer skips fat and protein carb equivalents, so they are not exported either.
            predicate: NSPredicate(format: "date <= %@ AND (isFPU == NO OR isFPU == nil)", end as NSDate),
            key: "date",
            ascending: true
        )
        return try await context.perform {
            guard let stored = results as? [CarbEntryStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }
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
    ) async throws -> [BackupHistoryTier.TDDEntry] {
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
            // TDD is stored every loop cycle (about 288 a day). The newest sample per hour is plenty for
            // Dynamic ISF's averages and the daily statistics.
            var newestPerHour: [Date: BackupHistoryTier.TDDEntry] = [:]
            for entry in stored {
                guard let date = entry.date, let total = entry.total?.decimalValue, total > 0 else { continue }
                let hour = Date(
                    timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 3600).rounded(.down) * 3600
                )
                newestPerHour[hour] = BackupHistoryTier.TDDEntry(
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

    struct HistoryCount: Identifiable, Equatable {
        let label: String
        let count: Int
        var id: String { label }
    }

    /// Entry counts for the overview. Deduplication can only make the applied number smaller.
    static func previewCounts(_ history: BackupHistoryTier) -> [HistoryCount] {
        var counts: [HistoryCount] = []
        if let glucose = history.glucose, glucose.isNotEmpty {
            counts.append(HistoryCount(label: String(localized: "Glucose Readings"), count: glucose.count))
        }
        if let pumpHistory = history.pumpHistory, pumpHistory.isNotEmpty {
            // A temp basal's rate and duration merge into one event.
            let events = pumpHistory.filter { $0.type != .tempBasalDuration }
            counts.append(HistoryCount(label: String(localized: "Pump Events"), count: events.count))
        }
        if let carbs = history.carbs, carbs.isNotEmpty {
            counts.append(HistoryCount(label: String(localized: "Carb Entries"), count: carbs.filter { $0.isFPU != true }.count))
        }
        if let tdd = history.tdd, tdd.isNotEmpty {
            counts.append(HistoryCount(label: String(localized: "TDD Samples"), count: tdd.count))
        }
        return counts
    }

    // MARK: - Import

    /// Applies the history through the deduplicating importers. Never throws: every failed category becomes
    /// a warning and the rest is still imported.
    static func apply(
        _ history: BackupHistoryTier,
        coreDataStack: CoreDataStack = .shared,
        now: Date = Date()
    ) async -> [String] {
        var warnings: [String] = []
        let importer = JSONImporter(context: coreDataStack.newTaskContext(), coreDataStack: coreDataStack)

        // Each category's window starts at its own oldest entry, so nothing is cut off and the duplicate
        // check stays bounded to the range the backup can touch.
        if let glucose = history.glucose, glucose.isNotEmpty {
            do {
                try await importer.importGlucoseHistory(
                    entries: glucose,
                    now: now,
                    start: glucose.map(\.dateString).min() ?? now
                )
            } catch {
                warnings.append(String(localized: "Glucose history could not be imported: \(error.localizedDescription)"))
            }
        }
        if let pumpHistory = history.pumpHistory, pumpHistory.isNotEmpty {
            do {
                try await importer.importPumpHistory(
                    entries: sanitizedPumpHistory(pumpHistory.sorted { $0.timestamp < $1.timestamp }),
                    now: now,
                    start: pumpHistory.map(\.timestamp).min() ?? now
                )
            } catch {
                warnings.append(String(localized: "Pump history could not be imported: \(error.localizedDescription)"))
            }
        }
        if let carbs = history.carbs, carbs.isNotEmpty {
            do {
                try await importer.importCarbHistory(
                    entries: carbs,
                    now: now,
                    start: carbs.map { $0.actualDate ?? $0.createdAt }.min() ?? now
                )
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
        return warnings
    }

    /// TDD samples have no file importer to reuse, so the same recipe is applied: date-based deduplication
    /// and a background insert.
    static func importTDD(
        _ entries: [BackupHistoryTier.TDDEntry],
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
            do { try context.save() } catch {
                context.rollback()
                throw error
            }
        }
    }
}
