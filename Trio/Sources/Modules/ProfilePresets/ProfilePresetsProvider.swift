import Foundation
import Swinject

extension ProfilePresets {
    final class Provider: BaseProvider, ProfilePresetsProvider {
        @Injected() private var profilePresetStorage: ProfilePresetStorage!

        func loadPresets() -> [ProfilePreset] {
            profilePresetStorage.presets()
        }

        func saveCurrentAsPreset(name: String) -> ProfilePreset {
            profilePresetStorage.saveCurrentProfileAsPreset(name: name)
        }

        func activatePreset(_ preset: ProfilePreset) {
            profilePresetStorage.activatePreset(preset)
        }

        func deletePreset(id: String) {
            profilePresetStorage.deletePreset(id: id)
        }
    }
}
