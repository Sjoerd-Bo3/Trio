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

        func saveCurrentAsPreset(name: String, includeSMB: Bool, includeDynamic: Bool) -> ProfilePreset? {
            profilePresetStorage.saveCurrentProfileAsPreset(name: name, includeSMB: includeSMB, includeDynamic: includeDynamic)
        }

        func savePreset(_ preset: ProfilePreset) {
            var existing = profilePresetStorage.presets()
            existing.append(preset)
            profilePresetStorage.savePresets(existing)
        }

        func activatePreset(_ preset: ProfilePreset) -> Bool {
            profilePresetStorage.activatePreset(preset)
        }

        func deletePreset(id: String) {
            profilePresetStorage.deletePreset(id: id)
        }
    }
}
