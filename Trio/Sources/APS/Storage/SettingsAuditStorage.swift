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
    func updateNote(for entryId: UUID, note: String)
    func deleteOldEntries(olderThan date: Date)
}

final class BaseSettingsAuditStorage: SettingsAuditStorage, Injectable {
    private let viewContext = CoreDataStack.shared.persistentContainer.viewContext
    private let backgroundContext = CoreDataStack.shared.newTaskContext()

    init(resolver: Resolver) {
        injectServices(resolver)
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

    func updateNote(for entryId: UUID, note: String) {
        backgroundContext.perform { [weak self] in
            guard let self else { return }
            let request = SettingsChangeStored.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", entryId as CVarArg)
            request.fetchLimit = 1
            if let entry = (try? self.backgroundContext.fetch(request))?.first {
                entry.note = note
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
