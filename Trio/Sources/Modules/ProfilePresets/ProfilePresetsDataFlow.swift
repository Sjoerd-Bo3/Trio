import Foundation

enum ProfilePresets {
    enum Config {}
}

protocol ProfilePresetsProvider: Provider {
    func loadPresets() -> [ProfilePreset]
    func loadCurrentProfile() -> ProfilePreset?
    func saveCurrentAsPreset(name: String, icon: String, includeSMB: Bool, includeDynamic: Bool) -> ProfilePreset?
    func savePreset(_ preset: ProfilePreset)
    func savePresets(_ presets: [ProfilePreset])
    func activatePreset(_ preset: ProfilePreset) -> Bool
    func deletePreset(id: String)
    func renamePreset(id: String, newName: String)
    func loadActivePreset() -> ProfilePreset?
    func settingsMatchPreset(_ preset: ProfilePreset) -> Bool
    func updatePresetToCurrentSettings(id: String) -> ProfilePreset?
}
