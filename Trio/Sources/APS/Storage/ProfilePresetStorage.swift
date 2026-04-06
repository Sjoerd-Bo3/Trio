import Foundation
import Swinject

protocol ProfilePresetStorage {
    func presets() -> [ProfilePreset]
    func savePresets(_ presets: [ProfilePreset])
    func saveCurrentProfileAsPreset(name: String, includeSMB: Bool, includeDynamic: Bool) -> ProfilePreset?
    func currentProfile() -> ProfilePreset?
    func activatePreset(_ preset: ProfilePreset) -> Bool
    func deletePreset(id: String)
}

final class BaseProfilePresetStorage: ProfilePresetStorage, Injectable {
    @Injected() private var storage: FileStorage!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var settingsManager: SettingsManager!

    init(resolver: Resolver) {
        injectServices(resolver)
    }

    func presets() -> [ProfilePreset] {
        storage.retrieve(OpenAPS.Trio.profilePresets, as: [ProfilePreset].self) ?? []
    }

    func savePresets(_ presets: [ProfilePreset]) {
        storage.save(presets, as: OpenAPS.Trio.profilePresets)
    }

    // MARK: - Private Helpers

    private struct CurrentTherapySettings {
        let basalProfile: [BasalProfileEntry]
        let insulinSensitivities: InsulinSensitivities
        let carbRatios: CarbRatios
        let bgTargets: BGTargets
    }

    private func loadCurrentTherapySettings() -> CurrentTherapySettings? {
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

        return CurrentTherapySettings(
            basalProfile: basalProfile,
            insulinSensitivities: insulinSensitivities,
            carbRatios: carbRatios,
            bgTargets: bgTargets
        )
    }

    private func currentSMBSettings() -> SMBPresetSettings {
        let prefs = settingsManager.preferences
        return SMBPresetSettings(
            enableSMBAlways: prefs.enableSMBAlways,
            enableSMBWithCOB: prefs.enableSMBWithCOB,
            enableSMBWithTemptarget: prefs.enableSMBWithTemptarget,
            enableSMBAfterCarbs: prefs.enableSMBAfterCarbs,
            allowSMBWithHighTemptarget: prefs.allowSMBWithHighTemptarget,
            enableSMBHighBG: prefs.enableSMB_high_bg,
            enableSMBHighBGTarget: prefs.enableSMB_high_bg_target,
            maxSMBBasalMinutes: prefs.maxSMBBasalMinutes,
            maxUAMSMBBasalMinutes: prefs.maxUAMSMBBasalMinutes,
            enableUAM: prefs.enableUAM,
            maxDeltaBGthreshold: prefs.maxDeltaBGthreshold
        )
    }

    private func currentDynamicSettings() -> DynamicPresetSettings {
        let prefs = settingsManager.preferences
        return DynamicPresetSettings(
            useNewFormula: prefs.useNewFormula,
            sigmoid: prefs.sigmoid,
            adjustmentFactor: prefs.adjustmentFactor,
            adjustmentFactorSigmoid: prefs.adjustmentFactorSigmoid,
            weightPercentage: prefs.weightPercentage,
            tddAdjBasal: prefs.tddAdjBasal
        )
    }

    // MARK: - Public API

    func currentProfile() -> ProfilePreset? {
        guard let therapy = loadCurrentTherapySettings() else { return nil }

        return ProfilePreset(
            name: String(localized: "Current Profile", comment: "ProfilePresets: name for the current active profile"),
            basalProfile: therapy.basalProfile,
            insulinSensitivities: therapy.insulinSensitivities,
            carbRatios: therapy.carbRatios,
            bgTargets: therapy.bgTargets,
            smbSettings: currentSMBSettings(),
            dynamicSettings: currentDynamicSettings()
        )
    }

    func saveCurrentProfileAsPreset(name: String, includeSMB: Bool, includeDynamic: Bool) -> ProfilePreset? {
        guard let therapy = loadCurrentTherapySettings() else { return nil }

        let preset = ProfilePreset(
            name: name,
            basalProfile: therapy.basalProfile,
            insulinSensitivities: therapy.insulinSensitivities,
            carbRatios: therapy.carbRatios,
            bgTargets: therapy.bgTargets,
            smbSettings: includeSMB ? currentSMBSettings() : nil,
            dynamicSettings: includeDynamic ? currentDynamicSettings() : nil
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

        if preset.smbSettings != nil || preset.dynamicSettings != nil {
            var prefs = settingsManager.preferences

            if let smb = preset.smbSettings {
                prefs.enableSMBAlways = smb.enableSMBAlways
                prefs.enableSMBWithCOB = smb.enableSMBWithCOB
                prefs.enableSMBWithTemptarget = smb.enableSMBWithTemptarget
                prefs.enableSMBAfterCarbs = smb.enableSMBAfterCarbs
                prefs.allowSMBWithHighTemptarget = smb.allowSMBWithHighTemptarget
                prefs.enableSMB_high_bg = smb.enableSMBHighBG
                prefs.enableSMB_high_bg_target = smb.enableSMBHighBGTarget
                prefs.maxSMBBasalMinutes = smb.maxSMBBasalMinutes
                prefs.maxUAMSMBBasalMinutes = smb.maxUAMSMBBasalMinutes
                prefs.enableUAM = smb.enableUAM
                prefs.maxDeltaBGthreshold = smb.maxDeltaBGthreshold
            }

            if let dynamic = preset.dynamicSettings {
                prefs.useNewFormula = dynamic.useNewFormula
                prefs.sigmoid = dynamic.sigmoid
                prefs.adjustmentFactor = dynamic.adjustmentFactor
                prefs.adjustmentFactorSigmoid = dynamic.adjustmentFactorSigmoid
                prefs.weightPercentage = dynamic.weightPercentage
                prefs.tddAdjBasal = dynamic.tddAdjBasal
            }

            settingsManager.preferences = prefs
        }

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
