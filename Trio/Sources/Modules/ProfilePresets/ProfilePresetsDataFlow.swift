import Foundation

enum ProfilePresets {
    enum Config {}
}

protocol ProfilePresetsProvider: Provider {
    func loadPresets() -> [ProfilePreset]
    func loadCurrentProfile() -> ProfilePreset?
    func saveCurrentAsPreset(name: String, includeSMB: Bool, includeDynamic: Bool) -> ProfilePreset?
    func savePreset(_ preset: ProfilePreset)
    func activatePreset(_ preset: ProfilePreset) -> Bool
    func deletePreset(id: String)
}
