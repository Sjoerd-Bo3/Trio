import CoreData
import Foundation
import Observation
import SwiftUI

extension SettingsAuditLog {
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

        func updateNote(for entry: SettingsChangeStored, note: String) {
            guard let id = entry.id else { return }
            provider.auditStorage.updateNote(for: id, note: note)
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

        var groupedEntries: [(String, [SettingsChangeStored])] {
            let cal = Self.groupingCalendar
            let df = Self.groupingFormatter
            // Group by (year, month, day) components to avoid parsing formatted strings for sorting
            let grouped = Dictionary(grouping: filteredEntries) { entry -> DateComponents in
                guard let date = entry.date else { return DateComponents() }
                return cal.dateComponents([.year, .month, .day], from: date)
            }
            return grouped
                .sorted { a, b in
                    // Sort descending by date components
                    let aDate = cal.date(from: a.key) ?? .distantPast
                    let bDate = cal.date(from: b.key) ?? .distantPast
                    return aDate > bDate
                }
                .map { components, dayEntries in
                    let label: String
                    if let date = cal.date(from: components) {
                        label = df.string(from: date)
                    } else {
                        label = "Unknown"
                    }
                    return (label, dayEntries)
                }
        }
    }
}
