import CoreData
import Foundation
import Observation
import SwiftUI

extension SettingsAuditLog {
    @Observable final class StateModel: BaseStateModel<Provider> {
        var searchText: String = ""
        var selectedCategory: String? = nil
        var entries: [SettingsChangeStored] = []
        var isLoadingMore: Bool = false
        var hasMore: Bool = true

        private let pageSize = 50
        private var currentOffset = 0

        let viewContext = CoreDataStack.shared.persistentContainer.viewContext

        var allCategories: [String] {
            var cats = Set<String>()
            for entry in entries {
                if let cat = entry.category { cats.insert(cat) }
            }
            return ["All"] + cats.sorted()
        }

        override func subscribe() {
            loadInitial()
        }

        func loadInitial() {
            currentOffset = 0
            hasMore = true
            entries = []
            loadMore()
        }

        func loadMore() {
            guard hasMore, !isLoadingMore else { return }
            isLoadingMore = true
            let loaded = provider.auditStorage.fetchHistory(
                category: selectedCategory == "All" ? nil : selectedCategory,
                since: nil,
                limit: pageSize + currentOffset
            )
            entries = loaded
            hasMore = loaded.count >= pageSize + currentOffset
            currentOffset += pageSize
            isLoadingMore = false
        }

        func updateNote(for entry: SettingsChangeStored, note: String) {
            guard let id = entry.id else { return }
            provider.auditStorage.updateNote(for: id, note: note)
            loadInitial()
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
            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .none
            let grouped = Dictionary(grouping: filteredEntries) { entry -> String in
                guard let date = entry.date else { return "Unknown" }
                return df.string(from: date)
            }
            return grouped.sorted { a, b in
                let dfParse = DateFormatter()
                dfParse.dateStyle = .medium
                let dateA = dfParse.date(from: a.key) ?? .distantPast
                let dateB = dfParse.date(from: b.key) ?? .distantPast
                return dateA > dateB
            }
        }
    }
}
