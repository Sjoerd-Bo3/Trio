import CoreData
import Foundation

extension Home.StateModel {
    // MARK: - Profile Preset Runs

    @MainActor func setupProfilePresetRunController() {
        profilePresetRunControllerDelegate.onContentChange = { [weak self] in
            Task { @MainActor in
                self?.updateProfilePresetRunsFromController()
            }
        }

        do {
            try profilePresetRunController.performFetch()
            updateProfilePresetRunsFromController()
        } catch {
            debug(.default, "\(DebuggingIdentifiers.failed) Failed to perform profile preset run fetch: \(error)")
        }
    }

    @MainActor private func updateProfilePresetRunsFromController() {
        guard let objects = profilePresetRunController.fetchedObjects else { return }
        profilePresetRunStored = objects
    }
}
