import Foundation
import Swinject

protocol ProfilePresetStorage {
    func presets() -> [ProfilePreset]
    func savePresets(_ presets: [ProfilePreset])
    func saveCurrentProfileAsPreset(name: String) -> ProfilePreset?
    func activatePreset(_ preset: ProfilePreset) -> Bool
    func deletePreset(id: String)
}

final class BaseProfilePresetStorage: ProfilePresetStorage, Injectable {
    @Injected() private var storage: FileStorage!
    @Injected() private var broadcaster: Broadcaster!

    init(resolver: Resolver) {
        injectServices(resolver)
    }

    func presets() -> [ProfilePreset] {
        storage.retrieve(OpenAPS.Trio.profilePresets, as: [ProfilePreset].self) ?? []
    }

    func savePresets(_ presets: [ProfilePreset]) {
        storage.save(presets, as: OpenAPS.Trio.profilePresets)
    }

    func saveCurrentProfileAsPreset(name: String) -> ProfilePreset? {
        let basalProfile = storage.retrieve(OpenAPS.Settings.basalProfile, as: [BasalProfileEntry].self)
            ?? [BasalProfileEntry](from: OpenAPS.defaults(for: OpenAPS.Settings.basalProfile))
            ?? []

        let insulinSensitivities = storage.retrieve(OpenAPS.Settings.insulinSensitivities, as: InsulinSensitivities.self)
            ?? InsulinSensitivities(from: OpenAPS.defaults(for: OpenAPS.Settings.insulinSensitivities))
            ?? InsulinSensitivities(units: .mgdL, userPreferredUnits: .mgdL, sensitivities: [])

        let carbRatios = storage.retrieve(OpenAPS.Settings.carbRatios, as: CarbRatios.self)
            ?? CarbRatios(from: OpenAPS.defaults(for: OpenAPS.Settings.carbRatios))
            ?? CarbRatios(units: .grams, schedule: [])

        let bgTargets = storage.retrieve(OpenAPS.Settings.bgTargets, as: BGTargets.self)
            ?? BGTargets(from: OpenAPS.defaults(for: OpenAPS.Settings.bgTargets))
            ?? BGTargets(units: .mgdL, userPreferredUnits: .mgdL, targets: [])

        guard !basalProfile.isEmpty,
              !insulinSensitivities.sensitivities.isEmpty,
              !carbRatios.schedule.isEmpty,
              !bgTargets.targets.isEmpty
        else {
            return nil
        }

        let preset = ProfilePreset(
            name: name,
            basalProfile: basalProfile,
            insulinSensitivities: insulinSensitivities,
            carbRatios: carbRatios,
            bgTargets: bgTargets
        )

        var existingPresets = presets()
        existingPresets.append(preset)
        savePresets(existingPresets)

        return preset
    }

    func activatePreset(_ preset: ProfilePreset) -> Bool {
        guard !preset.basalProfile.isEmpty,
              !preset.insulinSensitivities.sensitivities.isEmpty,
              !preset.carbRatios.schedule.isEmpty,
              !preset.bgTargets.targets.isEmpty
        else {
            return false
        }

        storage.save(preset.basalProfile, as: OpenAPS.Settings.basalProfile)
        storage.save(preset.insulinSensitivities, as: OpenAPS.Settings.insulinSensitivities)
        storage.save(preset.carbRatios, as: OpenAPS.Settings.carbRatios)
        storage.save(preset.bgTargets, as: OpenAPS.Settings.bgTargets)

        broadcaster.notify(BasalProfileObserver.self, on: .main) {
            $0.basalProfileDidChange(preset.basalProfile)
        }

        broadcaster.notify(BGTargetsObserver.self, on: .main) {
            $0.bgTargetsDidChange(preset.bgTargets)
        }

        return true
    }

    func deletePreset(id: String) {
        var existingPresets = presets()
        existingPresets.removeAll { $0.id == id }
        savePresets(existingPresets)
    }
}
