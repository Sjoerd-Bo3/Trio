import CoreData
import Foundation

extension Home.StateModel {
    func setupProfilePresetRunStored() {
        Task {
            do {
                let ids = try await self.fetchProfilePresetRunStored()
                let profilePresetRunObjects: [ProfilePresetRunStored] = try await CoreDataStack.shared
                    .getNSManagedObject(with: ids, context: viewContext)
                await updateProfilePresetRunStoredArray(with: profilePresetRunObjects)
            } catch {
                debug(
                    .default,
                    "\(DebuggingIdentifiers.failed) Error setting up profilePresetRunStored: \(error)"
                )
            }
        }
    }

    private func fetchProfilePresetRunStored() async throws -> [NSManagedObjectID] {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: ProfilePresetRunStored.self,
            onContext: profilePresetFetchContext,
            predicate: NSPredicate.profilePresetRunStoredFromOneDayAgo,
            key: "startDate",
            ascending: false
        )

        return try await profilePresetFetchContext.perform {
            guard let fetchedResults = results as? [ProfilePresetRunStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }
            return fetchedResults.map(\.objectID)
        }
    }

    @MainActor private func updateProfilePresetRunStoredArray(with objects: [ProfilePresetRunStored]) {
        profilePresetRunStored = objects
    }
}
