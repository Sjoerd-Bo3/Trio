import CoreData
import Foundation
import Observation
import SwiftUI

extension SettingsAuditLog {
    /// A single change event that groups all individual setting changes sharing the same `groupId`.
    struct ChangeEvent: Identifiable {
        let id: UUID // groupId
        let date: Date
        let entries: [SettingsChangeStored]
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
            let cats = Set(entries.compactMap(\.category))
            return cats.sorted()
        }
    }

    @Observable final class StateModel: BaseStateModel<Provider> {
        var searchText: String = ""
        var selectedCategory: String? = nil
        var entries: [SettingsChangeStored] = []

        private static let groupingCalendar: Calendar = .current

        private static let groupingFormatter: DateFormatter = {
            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .none
            return df
        }()

        /// Distinct categories from loaded entries. Recomputed only when entries change.
        var allCategories: [String] {
            var cats = Set<String>()
            for entry in entries {
                if let cat = entry.category { cats.insert(cat) }
            }
            return ["All"] + cats.sorted()
        }

        override func subscribe() {
            loadEntries()
        }

        func loadEntries() {
            entries = provider.auditStorage.fetchHistory(
                category: selectedCategory,
                since: nil,
                limit: 500
            )
        }

        func updateNote(forGroup groupId: UUID, note: String) {
            provider.auditStorage.updateNote(forGroup: groupId, note: note)
            loadEntries()
        }

        var filteredEntries: [SettingsChangeStored] {
            guard !searchText.isEmpty else { return entries }
            let lower = searchText.lowercased()
            return entries.filter {
                ($0.settingName?.lowercased().contains(lower) ?? false) ||
                    ($0.category?.lowercased().contains(lower) ?? false) ||
                    ($0.oldValue?.lowercased().contains(lower) ?? false) ||
                    ($0.newValue?.lowercased().contains(lower) ?? false) ||
                    ($0.note?.lowercased().contains(lower) ?? false)
            }
        }

        /// Groups filtered entries by `groupId` into `ChangeEvent`s, then groups those by day.
        var groupedEvents: [(String, [ChangeEvent])] {
            let cal = Self.groupingCalendar
            let df = Self.groupingFormatter

            // Build ChangeEvents from groupId
            let byGroup = Dictionary(grouping: filteredEntries) { entry -> UUID in
                entry.groupId ?? entry.id ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
            }
            let events: [ChangeEvent] = byGroup.map { groupId, groupEntries in
                let sorted = groupEntries.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
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
