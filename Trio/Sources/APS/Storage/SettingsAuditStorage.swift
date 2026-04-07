import CoreData
import Foundation
import Swinject

protocol SettingsAuditStorage: AnyObject {
    func logChange(
        category: String,
        subcategory: String,
        settingName: String,
        settingKey: String,
        oldValue: String,
        newValue: String,
        unit: String?,
        note: String?,
        source: String
    )
    func fetchHistory(for settingKey: String?, limit: Int, offset: Int) -> [SettingsChangeStored]
    func fetchHistory(category: String?, since: Date?, limit: Int) -> [SettingsChangeStored]
    /// Fetches history and converts managed objects to value types atomically inside performAndWait,
    /// preventing use-after-free when Core Data merges background changes.
    func fetchChangeEntries(category: String?, since: Date?, limit: Int) -> [SettingsAuditLog.ChangeEntry]
    func updateNote(forGroup groupId: UUID, note: String)
    func deleteOldEntries(olderThan date: Date)

    /// Convenience for logging therapy profile changes (Basal, ISF, CR, BG Targets).
    /// Formats old/new arrays into summary strings and delegates to `logChange`.
    func logTherapyProfileChange(
        subcategory: String,
        settingName: String,
        settingKey: String,
        oldEntries: [String],
        newEntries: [String],
        unit: String
    )
}

extension SettingsAuditStorage {
    func logTherapyProfileChange(
        subcategory: String,
        settingName: String,
        settingKey: String,
        oldEntries: [String],
        newEntries: [String],
        unit: String
    ) {
        let oldStr = oldEntries.joined(separator: ", ")
        let newStr = newEntries.joined(separator: ", ")
        guard oldStr != newStr else { return }
        logChange(
            category: "Therapy",
            subcategory: subcategory,
            settingName: settingName,
            settingKey: settingKey,
            oldValue: oldStr.isEmpty ? "(empty)" : oldStr,
            newValue: newStr.isEmpty ? "(empty)" : newStr,
            unit: unit,
            note: nil,
            source: "manual"
        )
    }
}

final class BaseSettingsAuditStorage: SettingsAuditStorage, Injectable {
    private let viewContext = CoreDataStack.shared.persistentContainer.viewContext
    private let backgroundContext = CoreDataStack.shared.newTaskContext()

    /// 10-minute grouping window in seconds.
    private static let groupingWindow: TimeInterval = 10 * 60

    /// Tracks the current group: (groupId, groupStartDate).
    /// Changes logged within `groupingWindow` of `groupStartDate` share the same `groupId`.
    private var currentGroup: (id: UUID, start: Date)?

    /// Serial queue protecting `currentGroup` from concurrent access.
    private let groupLock = NSLock()

    init(resolver: Resolver) {
        injectServices(resolver)
        viewContext.automaticallyMergesChangesFromParent = true
        viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    /// Returns the group ID to use for a new entry. If the most recent group is still within
    /// the 10-minute window, reuses that group; otherwise creates a new one.
    private func resolveGroupId(now: Date = Date()) -> UUID {
        groupLock.lock()
        defer { groupLock.unlock() }
        if let group = currentGroup, now.timeIntervalSince(group.start) < Self.groupingWindow {
            return group.id
        }
        let newId = UUID()
        currentGroup = (id: newId, start: now)
        return newId
    }

    func logChange(
        category: String,
        subcategory: String,
        settingName: String,
        settingKey: String,
        oldValue: String,
        newValue: String,
        unit: String? = nil,
        note: String? = nil,
        source: String = "manual"
    ) {
        guard oldValue != newValue else { return }

        let groupId = resolveGroupId()

        backgroundContext.perform { [weak self] in
            guard let self else { return }
            let entry = SettingsChangeStored(context: self.backgroundContext)
            entry.id = UUID()
            entry.date = Date()
            entry.category = category
            entry.subcategory = subcategory
            entry.settingName = settingName
            entry.settingKey = settingKey
            entry.oldValue = oldValue
            entry.newValue = newValue
            entry.unit = unit
            entry.note = note
            entry.source = source
            entry.groupId = groupId

            do {
                try self.backgroundContext.save()
            } catch {
                debug(.default, "SettingsAuditStorage: Failed to save change log entry: \(error)")
            }
        }
    }

    func fetchHistory(for settingKey: String?, limit: Int = 100, offset: Int = 0) -> [SettingsChangeStored] {
        var result: [SettingsChangeStored] = []
        viewContext.performAndWait {
            let request = SettingsChangeStored.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(keyPath: \SettingsChangeStored.date, ascending: false)]
            if let key = settingKey {
                request.predicate = NSPredicate(format: "settingKey == %@", key)
            }
            request.fetchLimit = limit
            request.fetchOffset = offset
            result = (try? viewContext.fetch(request)) ?? []
        }
        return result
    }

    func fetchHistory(category: String?, since: Date?, limit: Int = 200) -> [SettingsChangeStored] {
        var result: [SettingsChangeStored] = []
        viewContext.performAndWait {
            let request = SettingsChangeStored.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(keyPath: \SettingsChangeStored.date, ascending: false)]

            var predicates: [NSPredicate] = []
            if let cat = category {
                predicates.append(NSPredicate(format: "category == %@", cat))
            }
            if let since = since {
                predicates.append(NSPredicate(format: "date >= %@", since as NSDate))
            }
            if !predicates.isEmpty {
                request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            }
            request.fetchLimit = limit
            result = (try? viewContext.fetch(request)) ?? []
        }
        return result
    }

    func fetchChangeEntries(
        category: String?,
        since: Date?,
        limit: Int = 200
    ) -> [SettingsAuditLog.ChangeEntry] {
        var result: [SettingsAuditLog.ChangeEntry] = []
        viewContext.performAndWait {
            let request = SettingsChangeStored.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(keyPath: \SettingsChangeStored.date, ascending: false)]

            var predicates: [NSPredicate] = []
            if let cat = category {
                predicates.append(NSPredicate(format: "category == %@", cat))
            }
            if let since = since {
                predicates.append(NSPredicate(format: "date >= %@", since as NSDate))
            }
            if !predicates.isEmpty {
                request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            }
            request.fetchLimit = limit
            let stored = (try? viewContext.fetch(request)) ?? []
            // Convert managed objects → value types inside performAndWait so the
            // managed objects cannot be faulted/invalidated between fetch and access
            result = stored.map { SettingsAuditLog.ChangeEntry(from: $0) }
        }
        return result
    }

    func updateNote(forGroup groupId: UUID, note: String) {
        backgroundContext.perform { [weak self] in
            guard let self else { return }
            let request = SettingsChangeStored.fetchRequest()
            request.predicate = NSPredicate(format: "groupId == %@", groupId as CVarArg)
            if let entries = try? self.backgroundContext.fetch(request) {
                for entry in entries {
                    entry.note = note
                }
                try? self.backgroundContext.save()
            }
        }
    }

    func deleteOldEntries(olderThan date: Date) {
        backgroundContext.perform { [weak self] in
            guard let self else { return }
            let request = NSFetchRequest<NSFetchRequestResult>(entityName: "SettingsChangeStored")
            request.predicate = NSPredicate(format: "date < %@", date as NSDate)
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
            try? self.backgroundContext.execute(deleteRequest)
            try? self.backgroundContext.save()
        }
    }
}
