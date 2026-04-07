import Foundation
import Observation
import SwiftUI

extension SettingsAuditLog {
    /// Plain-value snapshot of a single `SettingsChangeStored` managed object.
    /// Capturing values eagerly avoids Core Data threading / faulting crashes.
    struct ChangeEntry: Identifiable, Sendable {
        let id: UUID
        let date: Date
        let category: String
        let subcategory: String
        let settingName: String
        let settingKey: String
        let oldValue: String
        let newValue: String
        let unit: String?
        let note: String
        let source: String
        let groupId: UUID

        init(
            id: UUID,
            date: Date,
            category: String,
            subcategory: String,
            settingName: String,
            settingKey: String,
            oldValue: String,
            newValue: String,
            unit: String?,
            note: String,
            source: String,
            groupId: UUID
        ) {
            self.id = id
            self.date = date
            self.category = category
            self.subcategory = subcategory
            self.settingName = settingName
            self.settingKey = settingKey
            self.oldValue = oldValue
            self.newValue = newValue
            self.unit = unit
            self.note = note
            self.source = source
            self.groupId = groupId
        }

        init(from stored: SettingsChangeStored) {
            id = stored.id ?? UUID()
            date = stored.date ?? .distantPast
            category = stored.category ?? ""
            subcategory = stored.subcategory ?? ""
            settingName = stored.settingName ?? ""
            settingKey = stored.settingKey ?? ""
            oldValue = stored.oldValue ?? ""
            newValue = stored.newValue ?? ""
            unit = stored.unit
            note = stored.note ?? ""
            source = stored.source ?? "manual"
            groupId = stored.groupId ?? stored.id ?? UUID()
        }

        /// Returns the display string for a value, stripping seconds from time prefixes
        /// and converting mg/dL → mmol/L when needed.
        func displayValue(_ raw: String, units: GlucoseUnits) -> String {
            let cleaned = Self.stripTimeSeconds(raw)
            guard units == .mmolL, let u = unit, Self.glucoseConvertibleUnits.contains(u) else { return cleaned }
            return Self.convertGlucoseString(cleaned, to: units)
        }

        /// Regex to match time prefixes with seconds: "HH:mm:ss: " → captures "HH:mm" and ": "
        private static let timeSecondsRegex = try! NSRegularExpression(pattern: #"(\d{1,2}:\d{2}):\d{2}(: )"#)

        /// Strips seconds from time prefixes in therapy profile value strings.
        /// e.g. "06:00:00: 1.0 U/hr" → "06:00: 1.0 U/hr"
        private static func stripTimeSeconds(_ raw: String) -> String {
            timeSecondsRegex.stringByReplacingMatches(
                in: raw,
                range: NSRange(raw.startIndex..., in: raw),
                withTemplate: "$1$2"
            )
        }

        /// Returns the daily basal total string (e.g. "18.4 U") for basal profile entries,
        /// or nil if the entry is not a basal profile change.
        func dailyBasalTotal(from raw: String) -> String? {
            guard settingKey == "therapy.basalProfile" else { return nil }
            guard let total = Self.calculateDailyBasalTotal(from: raw) else { return nil }
            let nf = NumberFormatter()
            nf.minimumFractionDigits = 1
            nf.maximumFractionDigits = 2
            return (nf.string(from: total as NSDecimalNumber) ?? "\(total)") + " U"
        }

        /// Parses a basal profile string like "0:00: 0.8 U/hr, 06:00: 1.0 U/hr" and
        /// calculates the 24h total insulin delivery.
        private static func calculateDailyBasalTotal(from raw: String) -> Decimal? {
            let segments = raw.components(separatedBy: ", ")
            var entries: [(minuteStart: Int, rate: Decimal)] = []

            for segment in segments {
                let trimmed = segment.trimmingCharacters(in: .whitespaces)
                // Expected format: "HH:mm: X.X U/hr" or "HH:mm:ss: X.X U/hr"
                guard let colonSpaceRange = trimmed.range(of: ": ") else { continue }
                let timeStr = String(trimmed[trimmed.startIndex ..< colonSpaceRange.lowerBound])
                let valueStr = String(trimmed[colonSpaceRange.upperBound...])
                    .replacingOccurrences(of: " U/hr", with: "")
                    .trimmingCharacters(in: .whitespaces)

                // Parse time "HH:mm" or "HH:mm:ss" → minutes since midnight
                let timeParts = timeStr.components(separatedBy: ":")
                guard timeParts.count >= 2,
                      let hours = Int(timeParts[0].trimmingCharacters(in: .whitespaces)),
                      let mins = Int(timeParts[1].trimmingCharacters(in: .whitespaces))
                else { continue }

                guard let rate = Decimal(string: valueStr) else { continue }
                entries.append((minuteStart: hours * 60 + mins, rate: rate))
            }

            guard !entries.isEmpty else { return nil }

            // Sort by start time
            entries.sort { $0.minuteStart < $1.minuteStart }

            var total: Decimal = 0
            for (index, entry) in entries.enumerated() {
                let nextStart: Int
                if index + 1 < entries.count {
                    nextStart = entries[index + 1].minuteStart
                } else {
                    nextStart = 24 * 60 // end of day
                }
                let durationMinutes = nextStart - entry.minuteStart
                guard durationMinutes > 0 else { continue }
                let durationHours = Decimal(durationMinutes) / Decimal(60)
                total += entry.rate * durationHours
            }

            return total
        }

        /// The display unit label, adjusted for the user's preferred glucose unit.
        func displayUnit(units: GlucoseUnits) -> String? {
            guard let u = unit, !u.isEmpty else { return nil }
            if units == .mmolL, Self.glucoseConvertibleUnits.contains(u) {
                return u.replacingOccurrences(of: "mg/dL", with: units.rawValue)
            }
            return u
        }

        /// Units whose numeric values are stored in mg/dL and should be converted for display.
        private static let glucoseConvertibleUnits: Set<String> = ["mg/dL", "mg/dL/U"]

        /// Converts a string that may contain one or more mg/dL numeric values to the target unit.
        /// Handles both single values ("120"), ranges ("100-120"), and comma-separated lists
        /// like "08:00: 100, 12:00: 90" or "08:00: 100-120 mg/dL, 12:00: 90-110 mg/dL".
        private static func convertGlucoseString(_ raw: String, to units: GlucoseUnits) -> String {
            guard units == .mmolL else { return raw }

            // Handle comma-separated therapy profile entries
            if raw.contains(",") {
                let parts = raw.components(separatedBy: ", ")
                let converted = parts.map { convertSingleSegment($0, to: units) }
                return converted.joined(separator: ", ")
            }
            return convertSingleSegment(raw, to: units)
        }

        /// Converts a single segment like "120", "100-120", "08:00: 100" or "08:00: 100-120 mg/dL"
        /// from mg/dL to mmol/L.
        private static func convertSingleSegment(_ segment: String, to units: GlucoseUnits) -> String {
            let trimmed = segment.trimmingCharacters(in: .whitespaces)

            // Pattern: optional time prefix "HH:mm: " followed by the value part
            let prefix: String
            let valuePart: String
            if let colonRange = trimmed.range(of: ": ", options: .backwards) {
                prefix = String(trimmed[trimmed.startIndex ..< colonRange.upperBound])
                valuePart = String(trimmed[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            } else {
                prefix = ""
                valuePart = trimmed
            }

            // Strip trailing unit label (e.g. " mg/dL" or " mg/dL/U") for parsing
            let stripped = valuePart
                .replacingOccurrences(of: " mg/dL/U", with: "")
                .replacingOccurrences(of: " mg/dL", with: "")
                .trimmingCharacters(in: .whitespaces)

            // Handle range format "100-120"
            if stripped.contains("-") {
                let rangeParts = stripped.components(separatedBy: "-")
                if rangeParts.count == 2,
                   let low = Decimal(string: rangeParts[0].trimmingCharacters(in: .whitespaces)),
                   let high = Decimal(string: rangeParts[1].trimmingCharacters(in: .whitespaces))
                {
                    return prefix + low.formatted(for: units) + "-" + high.formatted(for: units)
                }
            }

            // Plain number
            if let decimal = Decimal(string: stripped) {
                return prefix + decimal.formatted(for: units)
            }
            return segment
        }
    }

    /// A single change event that groups all individual setting changes sharing the same `groupId`.
    struct ChangeEvent: Identifiable {
        let id: UUID // groupId
        let date: Date
        let entries: [ChangeEntry]
        let note: String

        /// Summary label, e.g. "3 settings changed" or the single setting name.
        var summaryLabel: String {
            if entries.count == 1 {
                return entries.first?.settingName ?? "1 setting changed"
            }
            return "\(entries.count) settings changed"
        }

        /// Distinct categories across all entries.
        var categories: [String] {
            let cats = Set(entries.map(\.category)).filter { !$0.isEmpty }
            return cats.sorted()
        }
    }

    @Observable final class StateModel: BaseStateModel<Provider> {
        var searchText: String = ""
        var selectedCategory: String? = nil
        var entries: [ChangeEntry] = []
        var units: GlucoseUnits = .mgdL

        private static let groupingCalendar: Calendar = .current

        private static let groupingFormatter: DateFormatter = {
            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .none
            return df
        }()

        /// Distinct categories from loaded entries.
        var allCategories: [String] {
            var cats = Set<String>()
            for entry in entries {
                if !entry.category.isEmpty { cats.insert(entry.category) }
            }
            return ["All"] + cats.sorted()
        }

        override func subscribe() {
            units = settingsManager.settings.units
            loadEntries()
        }

        func loadEntries() {
            entries = provider.auditStorage.fetchChangeEntries(
                category: selectedCategory,
                since: nil,
                limit: 500
            )
        }

        func updateNote(forGroup groupId: UUID, note: String) {
            provider.auditStorage.updateNote(forGroup: groupId, note: note)
            // Update in-memory entries immediately without refetching from Core Data
            // to avoid race conditions with the background context save
            entries = entries.map { entry in
                guard entry.groupId == groupId else { return entry }
                return ChangeEntry(
                    id: entry.id,
                    date: entry.date,
                    category: entry.category,
                    subcategory: entry.subcategory,
                    settingName: entry.settingName,
                    settingKey: entry.settingKey,
                    oldValue: entry.oldValue,
                    newValue: entry.newValue,
                    unit: entry.unit,
                    note: note,
                    source: entry.source,
                    groupId: entry.groupId
                )
            }
        }

        var filteredEntries: [ChangeEntry] {
            guard !searchText.isEmpty else { return entries }
            let lower = searchText.lowercased()
            return entries.filter {
                $0.settingName.lowercased().contains(lower) ||
                    $0.category.lowercased().contains(lower) ||
                    $0.oldValue.lowercased().contains(lower) ||
                    $0.newValue.lowercased().contains(lower) ||
                    $0.note.lowercased().contains(lower)
            }
        }

        /// Groups filtered entries by `groupId` into `ChangeEvent`s, then groups those by day.
        var groupedEvents: [(String, [ChangeEvent])] {
            let cal = Self.groupingCalendar
            let df = Self.groupingFormatter

            // Build ChangeEvents from groupId
            let byGroup = Dictionary(grouping: filteredEntries, by: \.groupId)
            let events: [ChangeEvent] = byGroup.map { groupId, groupEntries in
                let sorted = groupEntries.sorted { $0.date > $1.date }
                let date = sorted.first?.date ?? .distantPast
                let note = sorted.first?.note ?? ""
                return ChangeEvent(id: groupId, date: date, entries: sorted, note: note)
            }

            // Group events by day
            let byDay = Dictionary(grouping: events) { event -> DateComponents in
                cal.dateComponents([.year, .month, .day], from: event.date)
            }
            return byDay
                .sorted { a, b in
                    let aDate = cal.date(from: a.key) ?? .distantPast
                    let bDate = cal.date(from: b.key) ?? .distantPast
                    return aDate > bDate
                }
                .map { components, dayEvents in
                    let label: String
                    if let date = cal.date(from: components) {
                        label = df.string(from: date)
                    } else {
                        label = "Unknown"
                    }
                    let sorted = dayEvents.sorted { $0.date > $1.date }
                    return (label, sorted)
                }
        }

        // MARK: - Delete all entries

        func deleteAllEntries() {
            provider.auditStorage.deleteAllEntries()
            entries = []
        }

        // MARK: - CSV Export

        private static let csvDateFormatter: DateFormatter = {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return df
        }()

        /// Generates a CSV string of all filtered entries grouped by time.
        func generateCSV() -> String {
            var csv = "Date,Category,Subcategory,Setting,Old Value,New Value,Unit,Note\n"
            for entry in filteredEntries {
                let date = Self.csvDateFormatter.string(from: entry.date)
                let oldVal = entry.displayValue(entry.oldValue, units: units)
                let newVal = entry.displayValue(entry.newValue, units: units)
                let unit = entry.displayUnit(units: units) ?? ""
                csv += "\(csvEscape(date)),\(csvEscape(entry.category)),\(csvEscape(entry.subcategory)),"
                csv += "\(csvEscape(entry.settingName)),\(csvEscape(oldVal)),\(csvEscape(newVal)),"
                csv += "\(csvEscape(unit)),\(csvEscape(entry.note))\n"
            }
            return csv
        }

        /// Generates a CSV string of all filtered entries grouped by change event.
        func generateGroupedCSV() -> String {
            var csv = "Group Date,Group ID,Setting,Category,Subcategory,Old Value,New Value,Unit,Note\n"
            for (_, dayEvents) in groupedEvents {
                for event in dayEvents {
                    for entry in event.entries {
                        let date = Self.csvDateFormatter.string(from: entry.date)
                        let oldVal = entry.displayValue(entry.oldValue, units: units)
                        let newVal = entry.displayValue(entry.newValue, units: units)
                        let unit = entry.displayUnit(units: units) ?? ""
                        csv += "\(csvEscape(date)),\(csvEscape(event.id.uuidString)),"
                        csv += "\(csvEscape(entry.settingName)),\(csvEscape(entry.category)),"
                        csv += "\(csvEscape(entry.subcategory)),\(csvEscape(oldVal)),"
                        csv += "\(csvEscape(newVal)),\(csvEscape(unit)),\(csvEscape(event.note))\n"
                    }
                }
            }
            return csv
        }

        private func csvEscape(_ value: String) -> String {
            let needsQuoting = value.contains(",") || value.contains("\"") || value.contains("\n")
            if needsQuoting {
                return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }
            return value
        }
    }
}
