import CoreData
import Foundation
import OSLog

class CoreDataStack: ObservableObject {
    static let shared = CoreDataStack()
    static let identifier = "CoreDataStack"

    private var notificationToken: NSObjectProtocol?
    private let inMemory: Bool

    private init(inMemory: Bool = false) {
        self.inMemory = inMemory

        // Observe Core Data remote change notifications on the queue where the changes were made
        notificationToken = Foundation.NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: nil
        ) { _ in
            debugPrint("Received a persistent store remote change notification")
            Task {
                await self.fetchPersistentHistory()
            }
        }
    }

    deinit {
        if let observer = notificationToken {
            Foundation.NotificationCenter.default.removeObserver(observer)
        }
    }

    /// A persistent history token used for fetching transactions from the store
    /// Save the last token to User defaults
    private var lastToken: NSPersistentHistoryToken? {
        get {
            UserDefaults.standard.lastHistoryToken
        }
        set {
            UserDefaults.standard.lastHistoryToken = newValue
        }
    }

    /// A persistent container to set up the Core Data Stack
    lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "TrioCoreDataPersistentContainer")

        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("Failed \(DebuggingIdentifiers.failed) to retrieve a persistent store description")
        }

        if inMemory {
            description.url = URL(fileURLWithPath: "/dev/null")
        }

        // Enable persistent store remote change notifications
        /// - Tag: persistentStoreRemoteChange
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        // Enable persistent history tracking
        /// - Tag: persistentHistoryTracking
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)

        // Enable lightweight migration
        /// - Tag: lightweightMigration
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true

        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                fatalError("Unresolved Error \(DebuggingIdentifiers.failed) \(error), \(error.userInfo)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = false
        container.viewContext.name = "viewContext"
        /// - Tag: viewContextmergePolicy
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.undoManager = nil
        container.viewContext.shouldDeleteInaccessibleFaults = true
        return container
    }()

    /// Creates and configures a private queue context
    func newTaskContext() -> NSManagedObjectContext {
        // Create a private queue context
        /// - Tag: newBackgroundContext
        let taskContext = persistentContainer.newBackgroundContext()

        /// ensure that the background contexts stay in sync with the main context
        taskContext.automaticallyMergesChangesFromParent = true
        taskContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        taskContext.undoManager = nil
        return taskContext
    }

    func fetchPersistentHistory() async {
        do {
            try await fetchPersistentHistoryTransactionsAndChanges()
        } catch {
            debugPrint("\(error.localizedDescription)")
        }
    }

    private func fetchPersistentHistoryTransactionsAndChanges() async throws {
        let taskContext = newTaskContext()
        taskContext.name = "persistentHistoryContext"
//        debugPrint("Start fetching persistent history changes from the store ... \(DebuggingIdentifiers.inProgress)")

        try await taskContext.perform {
            // Execute the persistent history change since the last transaction
            /// - Tag: fetchHistory
            let changeRequest = NSPersistentHistoryChangeRequest.fetchHistory(after: self.lastToken)
            let historyResult = try taskContext.execute(changeRequest) as? NSPersistentHistoryResult
            if let history = historyResult?.result as? [NSPersistentHistoryTransaction], !history.isEmpty {
                self.mergePersistentHistoryChanges(from: history)
                return
            }
        }
    }

    private func mergePersistentHistoryChanges(from history: [NSPersistentHistoryTransaction]) {
//        debugPrint("Received \(history.count) persistent history transactions")
        // Update view context with objectIDs from history change request
        /// - Tag: mergeChanges
        let viewContext = persistentContainer.viewContext
        viewContext.perform {
            for transaction in history {
                viewContext.mergeChanges(fromContextDidSave: transaction.objectIDNotification())
                self.lastToken = transaction.token
            }
        }
    }

    // Clean old Persistent History
    /// - Tag: clearHistory
    func cleanupPersistentHistoryTokens(before date: Date) async {
        let taskContext = newTaskContext()
        taskContext.name = "cleanPersistentHistoryTokensContext"

        await taskContext.perform {
            let deleteHistoryTokensRequest = NSPersistentHistoryChangeRequest.deleteHistory(before: date)
            do {
                try taskContext.execute(deleteHistoryTokensRequest)
                debugPrint("\(DebuggingIdentifiers.succeeded) Successfully deleted persistent history before \(date)")
            } catch {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) Failed to delete persistent history before \(date): \(error.localizedDescription)"
                )
            }
        }
    }
}

// MARK: - Delete

extension CoreDataStack {
    /// Synchronously delete entry with specified object IDs
    ///  - Tag: synchronousDelete
    func deleteObject(identifiedBy objectID: NSManagedObjectID) async {
        let viewContext = persistentContainer.viewContext
        debugPrint("Start deleting data from the store ...\(DebuggingIdentifiers.inProgress)")

        await viewContext.perform {
            do {
                let entryToDelete = viewContext.object(with: objectID)
                viewContext.delete(entryToDelete)

                guard viewContext.hasChanges else { return }
                try viewContext.save()
                debugPrint("Successfully deleted data. \(DebuggingIdentifiers.succeeded)")
            } catch {
                debugPrint("Failed to delete data: \(error.localizedDescription)")
            }
        }
    }

    /// Asynchronously deletes records for entities
    ///  - Tag: batchDelete
    func batchDeleteOlderThan<T: NSManagedObject>(
        _ objectType: T.Type,
        dateKey: String,
        days: Int,
        isPresetKey: String? = nil
    ) async throws {
        let taskContext = newTaskContext()
        taskContext.name = "deleteContext"
        taskContext.transactionAuthor = "batchDelete"

        // Get the number of days we want to keep the data
        let targetDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!

        // Fetch all the objects that are older than the specified days
        let fetchRequest = NSFetchRequest<NSManagedObjectID>(entityName: String(describing: objectType))

        // Construct the predicate
        var predicates: [NSPredicate] = [NSPredicate(format: "%K < %@", dateKey, targetDate as NSDate)]
        if let isPresetKey = isPresetKey {
            predicates.append(NSPredicate(format: "%K == NO", isPresetKey))
        }
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        fetchRequest.resultType = .managedObjectIDResultType

        do {
            // Execute the Fetch Request
            let objectIDs = try await taskContext.perform {
                try taskContext.fetch(fetchRequest)
            }

            // Guard check if there are NSManagedObjects older than the specified days
            guard !objectIDs.isEmpty else {
//                debugPrint("No objects found older than \(days) days.")
                return
            }

            // Execute the Batch Delete
            try await taskContext.perform {
                let batchDeleteRequest = NSBatchDeleteRequest(objectIDs: objectIDs)
                guard let fetchResult = try? taskContext.execute(batchDeleteRequest),
                      let batchDeleteResult = fetchResult as? NSBatchDeleteResult,
                      let success = batchDeleteResult.result as? Bool, success
                else {
                    debugPrint("Failed to execute batch delete request \(DebuggingIdentifiers.failed)")
                    throw CoreDataError.batchDeleteError
                }
            }

            debugPrint("Successfully deleted data older than \(days) days. \(DebuggingIdentifiers.succeeded)")
        } catch {
            debugPrint("Failed to fetch or delete data: \(error.localizedDescription) \(DebuggingIdentifiers.failed)")
            throw CoreDataError.batchDeleteError
        }
    }

    func batchDeleteOlderThan<Parent: NSManagedObject, Child: NSManagedObject>(
        parentType: Parent.Type,
        childType: Child.Type,
        dateKey: String,
        days: Int,
        relationshipKey: String // The key of the Child Entity that links to the parent Entity
    ) async throws {
        let taskContext = newTaskContext()
        taskContext.name = "deleteContext"
        taskContext.transactionAuthor = "batchDelete"

        // Get the target date
        let targetDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!

        // Fetch Parent objects older than the target date
        let fetchParentRequest = NSFetchRequest<NSManagedObjectID>(entityName: String(describing: parentType))
        fetchParentRequest.predicate = NSPredicate(format: "%K < %@", dateKey, targetDate as NSDate)
        fetchParentRequest.resultType = .managedObjectIDResultType

        do {
            let parentObjectIDs = try await taskContext.perform {
                try taskContext.fetch(fetchParentRequest)
            }

            guard !parentObjectIDs.isEmpty else {
//                debugPrint("No \(parentType) objects found older than \(days) days.")
                return
            }

            // Fetch Child objects related to the fetched Parent objects
            let fetchChildRequest = NSFetchRequest<NSManagedObjectID>(entityName: String(describing: childType))
            fetchChildRequest.predicate = NSPredicate(format: "ANY %K IN %@", relationshipKey, parentObjectIDs)
            fetchChildRequest.resultType = .managedObjectIDResultType

            let childObjectIDs = try await taskContext.perform {
                try taskContext.fetch(fetchChildRequest)
            }

            guard !childObjectIDs.isEmpty else {
//                debugPrint("No \(childType) objects found related to \(parentType) objects older than \(days) days.")
                return
            }

            // Execute the batch delete for Child objects
            try await taskContext.perform {
                let batchDeleteRequest = NSBatchDeleteRequest(objectIDs: childObjectIDs)
                guard let fetchResult = try? taskContext.execute(batchDeleteRequest),
                      let batchDeleteResult = fetchResult as? NSBatchDeleteResult,
                      let success = batchDeleteResult.result as? Bool, success
                else {
                    debugPrint("Failed to execute batch delete request \(DebuggingIdentifiers.failed)")
                    throw CoreDataError.batchDeleteError
                }
            }

            debugPrint(
                "Successfully deleted \(childType) data related to \(parentType) objects older than \(days) days. \(DebuggingIdentifiers.succeeded)"
            )
        } catch {
            debugPrint("Failed to fetch or delete data: \(error.localizedDescription) \(DebuggingIdentifiers.failed)")
            throw CoreDataError.batchDeleteError
        }
    }
}

// MARK: - Fetch Requests

extension CoreDataStack {
    // Fetch in background thread
    /// - Tag: backgroundFetch
    func fetchEntities<T: NSManagedObject>(
        ofType type: T.Type,
        onContext context: NSManagedObjectContext,
        predicate: NSPredicate,
        key: String,
        ascending: Bool,
        fetchLimit: Int? = nil,
        batchSize: Int? = nil,
        propertiesToFetch: [String]? = nil,
        callingFunction: String = #function,
        callingClass: String = #fileID
    ) -> [T] {
        let request = NSFetchRequest<T>(entityName: String(describing: type))
        request.sortDescriptors = [NSSortDescriptor(key: key, ascending: ascending)]
        request.predicate = predicate
        if let limit = fetchLimit {
            request.fetchLimit = limit
        }
        if let batchSize = batchSize {
            request.fetchBatchSize = batchSize
        }
        if let propertiesTofetch = propertiesToFetch {
            request.propertiesToFetch = propertiesTofetch
            request.resultType = .managedObjectResultType
        } else {
            request.resultType = .managedObjectResultType
        }

        context.name = "fetchContext"
        context.transactionAuthor = "fetchEntities"

        var result: [T]?

        /// we need to ensure that the fetch immediately returns a value as long as the whole app does not use the async await pattern, otherwise we could perform this asynchronously with backgroundContext.perform and not block the thread
        context.performAndWait {
            do {
//                debugPrint(
//                    "Fetching \(T.self) in \(callingFunction) from \(callingClass): \(DebuggingIdentifiers.succeeded) on Thread: \(Thread.current)"
//                )
                result = try context.fetch(request)
            } catch let error as NSError {
                debugPrint(
                    "Fetching \(T.self) in \(callingFunction) from \(callingClass): \(DebuggingIdentifiers.failed) \(error) on Thread: \(Thread.current)"
                )
            }
        }

        return result ?? []
    }

    // Fetch Async
    func fetchEntitiesAsync<T: NSManagedObject>(
        ofType type: T.Type,
        onContext context: NSManagedObjectContext,
        predicate: NSPredicate,
        key: String,
        ascending: Bool,
        fetchLimit: Int? = nil,
        batchSize: Int? = nil,
        propertiesToFetch: [String]? = nil,
        callingFunction: String = #function,
        callingClass: String = #fileID
    ) async -> Any {
        let request: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: String(describing: type))
        request.sortDescriptors = [NSSortDescriptor(key: key, ascending: ascending)]
        request.predicate = predicate
        if let limit = fetchLimit {
            request.fetchLimit = limit
        }
        if let batchSize = batchSize {
            request.fetchBatchSize = batchSize
        }
        if let propertiesToFetch = propertiesToFetch {
            request.propertiesToFetch = propertiesToFetch
            request.resultType = .dictionaryResultType
        } else {
            request.resultType = .managedObjectResultType
        }

        context.name = "fetchContext"
        context.transactionAuthor = "fetchEntities"

        return await context.perform {
            do {
//                debugPrint("Fetching \(T.self) in \(callingFunction) from \(callingClass): \(DebuggingIdentifiers.succeeded) on Thread: \(Thread.current)")
                if propertiesToFetch != nil {
                    return try context.fetch(request) as? [[String: Any]] ?? []
                } else {
                    return try context.fetch(request) as? [T] ?? []
                }
            } catch let error as NSError {
                debugPrint(
                    "Fetching \(T.self) in \(callingFunction) from \(callingClass): \(DebuggingIdentifiers.failed) \(error) on Thread: \(Thread.current)"
                )
                return []
            }
        }
    }

    // Get NSManagedObject
    func getNSManagedObject<T: NSManagedObject>(
        with ids: [NSManagedObjectID],
        context: NSManagedObjectContext
    ) async -> [T] {
        await Task { () -> [T] in
            var objects = [T]()
            do {
                for id in ids {
                    if let object = try context.existingObject(with: id) as? T {
                        objects.append(object)
                    }
                }
            } catch {
                debugPrint("Failed to fetch objects: \(error.localizedDescription)")
            }
            return objects
        }.value
    }
}

// MARK: - Save

/// This function is used when terminating the App to ensure any unsaved changes on the view context made their way to the persistent container
extension CoreDataStack {
    func save() {
        let context = persistentContainer.viewContext

        guard context.hasChanges else { return }

        do {
            try context.save()
        } catch {
            debugPrint("Error saving context \(DebuggingIdentifiers.failed): \(error)")
        }
    }
}

extension NSManagedObjectContext {
    // takes a context as a parameter to be executed either on the main thread or on a background thread
    /// - Tag: save
    func saveContext(
        onContext: NSManagedObjectContext,
        callingFunction: String = #function,
        callingClass: String = #fileID
    ) throws {
        do {
            guard onContext.hasChanges else { return }
            try onContext.save()
//            debugPrint(
//                "Saving to Core Data successful in \(callingFunction) in \(callingClass): \(DebuggingIdentifiers.succeeded)"
//            )
        } catch let error as NSError {
            debugPrint(
                "Saving to Core Data failed in \(callingFunction) in \(callingClass): \(DebuggingIdentifiers.failed) with error \(error), \(error.userInfo)"
            )
            throw error
        }
    }
}
