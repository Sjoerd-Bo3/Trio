import Foundation

/// What a backup is compared against in the change overview.
struct BackupCurrentState {
    var settings: TrioSettings
    var preferences: Preferences
    var pumpSettings: PumpSettings
    var basalProfile: [BasalProfileEntry]
    var carbRatios: CarbRatios?
    var insulinSensitivities: InsulinSensitivities?
    var glucoseTargets: BGTargets?
    var presets: TrioSettingsBackup.Presets
}

extension SettingsImportApplier {
    /// Clamps every guarded value to the limits the settings screens enforce and, when the pump's
    /// supported rates are known, snaps basal rates to them. Returns one warning per adjustment.
    static func applyGuardrails(
        to configuration: TrioSettingsBackup.Configuration,
        supportedBasalRates: [Decimal]? = nil
    ) -> (configuration: TrioSettingsBackup.Configuration, warnings: [String]) {
        var result = configuration
        let units = configuration.settings.units
        let all = Set(SettingsBackupCategory.allCases)
        var warnings: [String] = []

        let settings = merge(
            trioSettingsFields,
            current: configuration.settings,
            imported: configuration.settings,
            categories: all,
            units: units
        )
        result.settings = settings.result
        warnings.append(contentsOf: settings.warnings)

        let preferences = merge(
            preferencesFields,
            current: configuration.preferences,
            imported: configuration.preferences,
            categories: all,
            units: units
        )
        result.preferences = preferences.result
        warnings.append(contentsOf: preferences.warnings)

        let pump = mergePumpSettings(
            current: configuration.pumpSettings,
            imported: configuration.pumpSettings,
            units: units
        )
        result.pumpSettings = pump.result
        warnings.append(contentsOf: pump.warnings)

        if let supported = supportedBasalRates, supported.isNotEmpty {
            var snappedCount = 0
            result.basalProfile = result.basalProfile.map { entry in
                // A zero-rate segment is deliberate; only real rates move to a supported step.
                guard entry.rate > 0 else { return entry }
                let rate = snap(entry.rate, toSupported: supported)
                if rate != entry.rate { snappedCount += 1 }
                return BasalProfileEntry(start: entry.start, minutes: entry.minutes, rate: rate)
            }
            if snappedCount > 0 {
                warnings.append(
                    String(localized: "\(snappedCount) basal rate(s) adjusted to the nearest rate supported by your pump.")
                )
            }
        }
        return (result, warnings)
    }

    /// The per-category overview of what restoring `configuration` changes on this device. Built
    /// from the same tables and guardrails `applyGuardrails` uses, so the overview matches the restore.
    static func changeSet(
        restoring configuration: TrioSettingsBackup.Configuration,
        current: BackupCurrentState
    ) -> ImportChangeSet {
        var changeSet = ImportChangeSet()
        let units = configuration.settings.units

        changeSet.settingChanges.merge(settingChanges(
            trioSettingsFields,
            current: current.settings,
            imported: configuration.settings,
            units: units
        )) { $0 + $1 }
        changeSet.settingChanges.merge(settingChanges(
            preferencesFields,
            current: current.preferences,
            imported: configuration.preferences,
            units: units
        )) { $0 + $1 }

        let pump = mergePumpSettings(
            current: current.pumpSettings,
            imported: configuration.pumpSettings,
            units: units
        )
        if pump.changes.isNotEmpty {
            changeSet.settingChanges[.therapy, default: []].append(contentsOf: pump.changes)
        }

        let perHour = String(localized: "U/hr", comment: "Insulin unit per hour abbreviation")
        let gramsPerUnit = String(localized: "g/U")
        func glucose(_ value: Decimal) -> String { BackupDisplay.glucose(value, units) }
        let schedules: [TherapyScheduleChange?] = [
            therapyScheduleChange(
                label: String(localized: "Basal Rates"),
                current: current.basalProfile.map { ($0.minutes, "\($0.rate) \(perHour)") },
                imported: configuration.basalProfile.map { ($0.minutes, "\($0.rate) \(perHour)") }
            ),
            therapyScheduleChange(
                label: String(localized: "Glucose Targets"),
                current: (current.glucoseTargets?.targets ?? []).map { ($0.offset, glucose($0.low)) },
                imported: configuration.glucoseTargets.targets.map { ($0.offset, glucose($0.low)) }
            ),
            therapyScheduleChange(
                label: String(localized: "Carb Ratios"),
                current: (current.carbRatios?.schedule ?? []).map { ($0.offset, "\($0.ratio) \(gramsPerUnit)") },
                imported: configuration.carbRatios.schedule.map { ($0.offset, "\($0.ratio) \(gramsPerUnit)") }
            ),
            therapyScheduleChange(
                label: String(localized: "Insulin Sensitivities"),
                current: (current.insulinSensitivities?.sensitivities ?? []).map { ($0.offset, glucose($0.sensitivity)) },
                imported: configuration.insulinSensitivities.sensitivities.map { ($0.offset, glucose($0.sensitivity)) }
            )
        ]
        changeSet.therapyChanges = schedules.compactMap { $0 }

        // A restore replaces all saved presets, so the overview reads like a "replace all" merge.
        changeSet.presetChanges[.tempTargetPresets] = presetChanges(
            imported: configuration.presets.tempTargets,
            existing: current.presets.tempTargets,
            name: { $0.name ?? "" }
        )
        changeSet.presetChanges[.overridePresets] = presetChanges(
            imported: configuration.presets.overrides,
            existing: current.presets.overrides,
            name: { $0.name ?? "" }
        )
        changeSet.presetChanges[.mealPresets] = presetChanges(
            imported: configuration.presets.meals,
            existing: current.presets.meals,
            name: { $0.dish ?? "" }
        )
        return changeSet
    }

    /// Added, replaced and removed presets; a preset with the same name and identical contents counts as kept.
    private static func presetChanges<Preset: Encodable>(
        imported: [Preset],
        existing: [Preset],
        name: (Preset) -> String
    ) -> [PresetChange] {
        let resolution = resolvePresetConflicts(
            imported: imported,
            existingNames: existing.map(name),
            activeNames: [],
            strategy: .replaceAll,
            name: name
        )
        var before: [String: Data] = [:]
        for preset in existing {
            if let data = try? TrioSettingsBackup.encoded(preset) { before[name(preset)] = data }
        }
        var after: [String: Data] = [:]
        for preset in imported {
            if let data = try? TrioSettingsBackup.encoded(preset) { after[name(preset)] = data }
        }
        return resolution.changes.map { change in
            guard change.kind == .replaced, let old = before[change.name], old == after[change.name] else { return change }
            return PresetChange(name: change.name, kind: .keptExisting)
        }
    }
}

/// Categories a settings backup is summarized by. Mirrors the sections of the CSV export,
/// minus metadata (which is always displayed but never "applied").
enum SettingsBackupCategory: String, CaseIterable, Identifiable {
    var id: String { rawValue }

    case devices
    case therapy
    case algorithm
    case features
    case notifications
    case services
    case tempTargetPresets
    case overridePresets
    case mealPresets
    case history

    var displayName: String {
        switch self {
        case .devices:
            return String(localized: "Devices", comment: "Devices menu item in the Settings main view.")
        case .therapy:
            return String(localized: "Therapy", comment: "Therapy menu item in the Settings main view.")
        case .algorithm:
            return String(localized: "Algorithm", comment: "Algorithm menu item in the Settings main view.")
        case .features:
            return String(localized: "Features", comment: "Features menu item in the Settings main view.")
        case .notifications:
            return String(localized: "Notifications", comment: "Notifications menu item in the Settings main view.")
        case .services:
            return String(localized: "Services", comment: "Services menu item in the Settings main view.")
        case .tempTargetPresets:
            return String(localized: "Temp Target Presets")
        case .overridePresets:
            return String(localized: "Override Presets")
        case .mealPresets:
            return String(localized: "Meal Presets")
        case .history:
            return String(localized: "History")
        }
    }
}
