import Foundation
import Observation
import SwiftUI

extension SettingsAuditLog {
    /// Plain-value snapshot of a single `SettingsChangeStored` managed object.
    /// Capturing values eagerly avoids Core Data threading / faulting crashes.
    struct ChangeEntry: Identifiable {
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
            loadEntries()
        }

        func loadEntries() {
            let stored = provider.auditStorage.fetchHistory(
                category: selectedCategory,
                since: nil,
                limit: 500
            )
            // Convert managed objects → value types immediately, inside the fetch context
            entries = stored.map { ChangeEntry(from: $0) }
        }

        func updateNote(forGroup groupId: UUID, note: String) {
            provider.auditStorage.updateNote(forGroup: groupId, note: note)
            loadEntries()
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
    }
}
