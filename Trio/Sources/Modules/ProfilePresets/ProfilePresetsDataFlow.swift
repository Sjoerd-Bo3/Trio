import Foundation

enum ProfilePresets {
    enum Config {}
}

protocol ProfilePresetsProvider: Provider {
    func loadPresets() -> [ProfilePreset]
    func saveCurrentAsPreset(name: String) -> ProfilePreset?
    func activatePreset(_ preset: ProfilePreset) -> Bool
    func deletePreset(id: String)
}
