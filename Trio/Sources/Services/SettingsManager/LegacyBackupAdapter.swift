import Foundation

/// Reads schema-1 settings files (the earlier export format) and converts them into the current snapshot.
/// Values in those files are raw (mg/dL, fractions), exactly like the snapshot's, so nothing is rescaled.
enum LegacyBackupAdapter {
    struct Converted {
        let snapshot: TrioSettingsBackup
        /// Parts of the file this version does not restore.
        let warnings: [String]
    }

    /// A schema-1 file has no `configuration` object; the snapshot format always does.
    static func isLegacy(_ raw: [String: Any]) -> Bool {
        raw["configuration"] == nil && (raw["schemaVersion"] as? Int) == 1
    }

    static func convert(_ legacy: SettingsBackup, now: Date = Date()) throws -> Converted {
        guard let settings = legacy.trioSettings,
              let preferences = legacy.preferences,
              let pumpSettings = legacy.pumpSettings,
              let therapy = legacy.therapy,
              therapy.basalProfile != nil, therapy.carbRatios != nil,
              therapy.insulinSensitivities != nil, therapy.bgTargets != nil
        else { throw BackupError.incompleteBackup }

        // Schedules are validated, aligned to the 30-minute grid and sorted exactly like the original import did.
        let normalized: NormalizedTherapy
        do {
            normalized = try SettingsImportApplier.validateTherapy(therapy)
        } catch {
            throw BackupError.invalidTherapyConfiguration
        }
        guard let basal = normalized.basalProfile, let carbs = normalized.carbRatios,
              let sensitivities = normalized.insulinSensitivities, let targets = normalized.bgTargets
        else { throw BackupError.incompleteBackup }

        var warnings = normalized.warnings
        var appConfiguration: TrioSettingsBackup.AppConfiguration?
        if let appearance = legacy.userDefaults?.colorSchemePreference.flatMap(ColorSchemeOption.init(rawValue:)) {
            // The older format carried no alert settings, so those stay as they are on this phone.
            let current = TrioSettingsBackup.AppConfiguration.capture()
            appConfiguration = TrioSettingsBackup.AppConfiguration(
                appearance: appearance,
                liveActivityOrder: current.liveActivityOrder,
                glucoseAlerts: current.glucoseAlerts,
                glucoseAlertConfiguration: current.glucoseAlertConfiguration,
                deviceAlertConfigurations: current.deviceAlertConfigurations
            )
        }

        let configuration = TrioSettingsBackup.Configuration(
            settings: settings,
            preferences: preferences,
            pumpSettings: pumpSettings,
            basalProfile: basal,
            carbRatios: carbs,
            insulinSensitivities: sensitivities,
            glucoseTargets: targets,
            presets: presets(from: legacy.presets),
            appConfiguration: appConfiguration
        )
        let safe = try TrioSettingsBackup.normalized(configuration)
        try TrioSettingsBackup.validate(safe)

        if legacy.credentials != nil {
            warnings.append(String(localized: "Saved Nightscout and remote control credentials in this file are not restored."))
        }
        if legacy.devices?.pumpState != nil || legacy.devices?.cgmState != nil {
            warnings.append(String(localized: "Saved pump and CGM pairing in this file is not restored."))
        }
        if legacy.history != nil {
            warnings.append(String(localized: "Saved treatment history in this file is not restored."))
        }

        let version = [legacy.appVersion, legacy.buildNumber.map { "(\($0))" }].compactMap { $0 }.joined(separator: " ")
        let snapshot = try TrioSettingsBackup(
            schemaVersion: TrioSettingsBackup.currentSchema,
            id: UUID(),
            createdAt: legacy.exportDate ?? now,
            appVersion: version.isEmpty ? "Unknown" : version,
            origin: .manual,
            name: nil,
            configuration: safe,
            fingerprint: TrioSettingsBackup.normalizedFingerprint(safe),
            deviceInfo: legacy.devices.map {
                TrioSettingsBackup.DeviceInfo(
                    pumpType: $0.pumpType,
                    insulinType: $0.insulinType,
                    cgmDisplayName: $0.cgmDisplayName
                )
            }
        )
        return Converted(snapshot: snapshot, warnings: warnings)
    }

    private static func presets(from legacy: SettingsBackup.Presets?) -> TrioSettingsBackup.Presets {
        let overrides = (legacy?.overrides ?? []).enumerated().map { index, preset in
            TrioSettingsBackup.OverridePreset(
                name: preset.name,
                order: Int16(clamping: preset.orderPosition ?? index),
                percentage: preset.percentage,
                duration: preset.duration,
                indefinite: preset.indefinite,
                target: preset.target,
                isf: preset.isf,
                cr: preset.cr,
                isfAndCr: preset.isfAndCr,
                advancedSettings: preset.advancedSettings,
                smbIsScheduledOff: preset.smbIsScheduledOff,
                smbIsOff: preset.smbIsOff,
                smbMinutes: preset.smbMinutes,
                uamMinutes: preset.uamMinutes,
                start: preset.start,
                end: preset.end
            )
        }
        let tempTargets = (legacy?.tempTargets ?? []).enumerated().map { index, preset in
            TrioSettingsBackup.TempTargetPreset(
                name: preset.name,
                order: Int16(clamping: preset.orderPosition ?? index),
                duration: preset.duration,
                target: preset.target,
                halfBasalTarget: preset.halfBasalTarget
            )
        }
        let meals = (legacy?.meals ?? []).map {
            TrioSettingsBackup.MealPreset(dish: $0.dish, carbs: $0.carbs, fat: $0.fat, protein: $0.protein)
        }
        return TrioSettingsBackup.Presets(overrides: overrides, tempTargets: tempTargets, meals: meals)
    }
}
