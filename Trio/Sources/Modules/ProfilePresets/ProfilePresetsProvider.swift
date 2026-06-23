import Foundation
import Swinject

extension ProfilePresets {
    final class Provider: BaseProvider, ProfilePresetsProvider {
        @Injected() private var profilePresetStorage: ProfilePresetStorage!

        func loadPresets() -> [ProfilePreset] {
            profilePresetStorage.presets()
        }

        func loadCurrentProfile() -> ProfilePreset? {
            profilePresetStorage.currentProfile()
        }

        func saveCurrentAsPreset(name: String, icon: String, includeSMB: Bool, includeDynamic: Bool) -> ProfilePreset? {
            profilePresetStorage.saveCurrentProfileAsPreset(
                name: name,
                icon: icon,
                includeSMB: includeSMB,
                includeDynamic: includeDynamic
            )
        }

        func savePreset(_ preset: ProfilePreset) {
            var existing = profilePresetStorage.presets()
            existing.append(preset)
            profilePresetStorage.savePresets(existing)
        }

        func savePresets(_ presets: [ProfilePreset]) {
            profilePresetStorage.savePresets(presets)
        }

        func activatePreset(_ preset: ProfilePreset) -> Bool {
            profilePresetStorage.activatePreset(preset)
        }

        func deletePreset(id: String) {
            profilePresetStorage.deletePreset(id: id)
        }

        func renamePreset(id: String, newName: String) {
            profilePresetStorage.renamePreset(id: id, newName: newName)
        }

        func loadActivePreset() -> ProfilePreset? {
            profilePresetStorage.activePreset()
        }

        func settingsMatchPreset(_ preset: ProfilePreset) -> Bool {
            profilePresetStorage.settingsMatchPreset(preset)
        }

        func updatePresetToCurrentSettings(id: String) -> ProfilePreset? {
            profilePresetStorage.updatePresetToCurrentSettings(id: id)
        }
    }
}
