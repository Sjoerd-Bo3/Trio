import Foundation

/// Reads schema-1 settings files (the earlier export format) and converts them into the current snapshot.
/// Values in those files are raw (mg/dL, fractions), exactly like the snapshot's, so nothing is rescaled.
enum LegacyBackupAdapter {
    struct Converted {
        let snapshot: TrioSettingsBackup
        /// Parts of the file this version does not restore.
        let warnings: [String]
        /// Sign-in details and pairing the older file carried in the clear; offered as opt-in choices on restore.
        let sensitive: SensitiveTier?
    }

    /// The treatment history of an older file as the current tier. Its daily-TDD archive has no counterpart.
    static func historyTier(from legacy: SettingsBackup.History?) -> BackupHistoryTier? {
        guard let legacy else { return nil }
        let tier = BackupHistoryTier(
            glucose: legacy.glucose,
            pumpHistory: legacy.pumpHistory,
            carbs: legacy.carbs,
            tdd: legacy.tdd?.map {
                BackupHistoryTier.TDDEntry(
                    date: $0.date,
                    total: $0.total,
                    bolus: $0.bolus,
                    tempBasal: $0.tempBasal,
                    scheduledBasal: $0.scheduledBasal,
                    weightedAverage: $0.weightedAverage
                )
            }
        )
        return tier.isEmpty ? nil : tier
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

        var tier = SensitiveTier()
        if let credentials = legacy.credentials {
            tier.credentials = SensitiveTier.Credentials(
                nightscoutURL: credentials.nightscoutURL,
                nightscoutSecret: credentials.nightscoutSecret,
                remoteControlSharedSecret: credentials.remoteControlSharedSecret
            )
        }
        if legacy.devices?.pumpState != nil || legacy.devices?.cgmState != nil {
            tier.devices = SensitiveTier.Devices(pumpState: legacy.devices?.pumpState, cgmState: legacy.devices?.cgmState)
        }
        if legacy.history?.tddDaily?.isEmpty == false {
            warnings.append(String(localized: "The daily insulin totals saved in this file are not restored."))
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
        return Converted(
            snapshot: try snapshot.withTreatmentHistory(historyTier(from: legacy.history)),
            warnings: warnings,
            sensitive: tier.isEmpty ? nil : tier
        )
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
