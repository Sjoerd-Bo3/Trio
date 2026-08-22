import Foundation

/// How imported presets are reconciled with presets that already exist on the device.
enum PresetConflictStrategy: String, CaseIterable, Identifiable {
    var id: String { rawValue }

    case replaceSameNamed
    case keepExisting
    case replaceAll

    var displayName: String {
        switch self {
        case .replaceSameNamed:
            return String(localized: "Replace Same-Named")
        case .keepExisting:
            return String(localized: "Keep Existing")
        case .replaceAll:
            return String(localized: "Replace All")
        }
    }

    var explanation: String {
        switch self {
        case .replaceSameNamed:
            return String(
                localized: "Imported presets replace same-named existing ones. New names are added, other presets are kept."
            )
        case .keepExisting:
            return String(localized: "Only presets with names that do not exist yet are added.")
        case .replaceAll:
            return String(localized: "All existing presets in the imported categories are deleted and replaced by the file's presets.")
        }
    }
}

/// One value shown in the change overview: current → imported.
struct ImportChange: Identifiable, Equatable {
    let id = UUID()
    let label: String
    let oldDisplay: String
    let newDisplay: String

    static func == (lhs: ImportChange, rhs: ImportChange) -> Bool {
        lhs.label == rhs.label && lhs.oldDisplay == rhs.oldDisplay && lhs.newDisplay == rhs.newDisplay
    }
}

enum PresetChangeKind: Equatable {
    case added
    case replaced
    case keptExisting
    case removed
    case activeSkipped

    var displayName: String {
        switch self {
        case .added: return String(localized: "added")
        case .replaced: return String(localized: "replaced")
        case .keptExisting: return String(localized: "kept")
        case .removed: return String(localized: "removed")
        case .activeSkipped: return String(localized: "skipped (currently running)")
        }
    }
}

struct PresetChange: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let kind: PresetChangeKind

    static func == (lhs: PresetChange, rhs: PresetChange) -> Bool {
        lhs.name == rhs.name && lhs.kind == rhs.kind
    }
}

/// A therapy schedule whose imported entries differ from the current ones.
struct TherapyScheduleChange: Identifiable {
    let id = UUID()
    let label: String
    let entryChanges: [ImportChange]
}

/// Everything the preview shows and the apply pipeline executes. Built from the SAME field
/// tables that drive `merge`, so the overview always matches what apply will do.
struct ImportChangeSet {
    var settingChanges: [SettingsBackupCategory: [ImportChange]] = [:]
    var therapyChanges: [TherapyScheduleChange] = []
    var presetChanges: [SettingsBackupCategory: [PresetChange]] = [:]

    func changeCount(for category: SettingsBackupCategory) -> Int {
        var count = settingChanges[category]?.count ?? 0
        if category == .therapy {
            count += therapyChanges.reduce(0) { $0 + $1.entryChanges.count }
        }
        count += (presetChanges[category] ?? []).filter { $0.kind != .keptExisting }.count
        return count
    }
}

/// Declarative description of one importable setting: which category it belongs to, how to copy
/// it (guardrail-clamped where a `PickerSetting` exists), how to detect a difference, and how to
/// render it for the change overview. The guardrail is referenced by key path into
/// `DecimalPickerSettings` and resolved from `PickerSettingsProvider.shared` at apply time, so
/// limits have a single source of truth and are never copied here.
struct BackupField<Root> {
    let label: String
    let category: SettingsBackupCategory

    private let applyClosure: (inout Root, Root, GlucoseUnits) -> String?
    private let differsClosure: (Root, Root, GlucoseUnits) -> Bool
    private let displayCurrentClosure: (Root, GlucoseUnits) -> String
    private let displayImportedClosure: (Root, GlucoseUnits) -> String

    /// Field without numeric guardrails (bools, enums, strings, unguarded numbers).
    init<Value: Equatable>(
        _ label: String,
        _ category: SettingsBackupCategory,
        _ keyPath: WritableKeyPath<Root, Value>,
        display: @escaping (Value, GlucoseUnits) -> String
    ) {
        self.label = label
        self.category = category
        applyClosure = { target, imported, _ in
            target[keyPath: keyPath] = imported[keyPath: keyPath]
            return nil
        }
        differsClosure = { current, imported, _ in
            current[keyPath: keyPath] != imported[keyPath: keyPath]
        }
        displayCurrentClosure = { display($0[keyPath: keyPath], $1) }
        displayImportedClosure = { display($0[keyPath: keyPath], $1) }
    }

    /// Decimal field guarded by an existing `PickerSetting`. The imported value is clamped and
    /// snapped to the nearest value the settings UI can represent; a change caused by that
    /// adjustment is reported as a warning.
    init(
        _ label: String,
        _ category: SettingsBackupCategory,
        _ keyPath: WritableKeyPath<Root, Decimal>,
        picker: KeyPath<DecimalPickerSettings, PickerSetting>,
        display: @escaping (Decimal, GlucoseUnits) -> String
    ) {
        self.label = label
        self.category = category
        applyClosure = { target, imported, units in
            let setting = PickerSettingsProvider.shared.settings[keyPath: picker]
            let raw = imported[keyPath: keyPath]
            let adjusted = SettingsImportApplier.clampAndSnap(raw, to: setting, units: units)
            target[keyPath: keyPath] = adjusted
            guard adjusted != raw else { return nil }
            return String(
                localized: "\(label): \(display(raw, units)) adjusted to \(display(adjusted, units)) to respect limits"
            )
        }
        differsClosure = { current, imported, units in
            let setting = PickerSettingsProvider.shared.settings[keyPath: picker]
            let adjusted = SettingsImportApplier.clampAndSnap(imported[keyPath: keyPath], to: setting, units: units)
            return current[keyPath: keyPath] != adjusted
        }
        displayCurrentClosure = { display($0[keyPath: keyPath], $1) }
        displayImportedClosure = { root, units in
            let setting = PickerSettingsProvider.shared.settings[keyPath: picker]
            return display(SettingsImportApplier.clampAndSnap(root[keyPath: keyPath], to: setting, units: units), units)
        }
    }

    func differs(current: Root, imported: Root, units: GlucoseUnits) -> Bool {
        differsClosure(current, imported, units)
    }

    /// Copies the imported value onto `target`, returning a warning when guardrails adjusted it.
    func apply(into target: inout Root, from imported: Root, units: GlucoseUnits) -> String? {
        applyClosure(&target, imported, units)
    }

    func displayCurrent(_ root: Root, units: GlucoseUnits) -> String {
        displayCurrentClosure(root, units)
    }

    func displayImported(_ root: Root, units: GlucoseUnits) -> String {
        displayImportedClosure(root, units)
    }
}

/// Display helpers for the change overview. Raw stored values in, user-facing strings out —
/// glucose is rendered in the given display units, fractions as percentages, matching the CSV export.
enum BackupDisplay {
    static func bool(_ value: Bool, _: GlucoseUnits) -> String {
        value ? String(localized: "Enabled") : String(localized: "Disabled")
    }

    static func glucose(_ value: Decimal, _ units: GlucoseUnits) -> String {
        units == .mgdL ? "\(value) \(units.rawValue)" : "\(value.formattedAsMmolL) \(units.rawValue)"
    }

    static func percent(_ value: Decimal, _: GlucoseUnits) -> String {
        String(format: "%.0f%%", (value as NSDecimalNumber).doubleValue * 100)
    }

    static func plain(_ value: Decimal, _: GlucoseUnits) -> String {
        String(describing: value)
    }

    static func decimal(unit: String) -> (Decimal, GlucoseUnits) -> String {
        { value, _ in "\(value) \(unit)" }
    }

    static func int(_ value: Int, _: GlucoseUnits) -> String {
        String(describing: value)
    }

    static func text(_ value: String, _: GlucoseUnits) -> String {
        value
    }
}

enum TherapyValidationError: LocalizedError, Equatable {
    case emptySchedule(String)
    case nonPositiveValue(String)
    case zeroTotalBasal
    case looksLikeMmolL(String)

    var errorDescription: String? {
        switch self {
        case let .emptySchedule(schedule):
            return String(localized: "Invalid \(schedule) in backup: schedule is empty.")
        case let .nonPositiveValue(schedule):
            return String(localized: "Invalid \(schedule) in backup: values must be greater than 0.")
        case .zeroTotalBasal:
            return String(localized: "Invalid basal rates in backup: total basal must be greater than 0.")
        case let .looksLikeMmolL(schedule):
            return String(localized: "Invalid \(schedule) in backup: values look like mmol/L, but backups must store mg/dL.")
        }
    }
}

/// Validated, normalized therapy schedules ready to persist (units forced to mg/dL, entries
/// deduplicated, sorted, aligned to the 30-minute grid, first entry at midnight).
struct NormalizedTherapy {
    var basalProfile: [BasalProfileEntry]?
    var insulinSensitivities: InsulinSensitivities?
    var carbRatios: CarbRatios?
    var bgTargets: BGTargets?
    var warnings: [String] = []
}

/// Pure import logic: field→category tables, guardrail-respecting merge, change-set computation,
/// therapy validation, and preset conflict resolution. No dependency injection — fully unit-testable.
enum SettingsImportApplier {
    // MARK: - Field tables

    /// Every stored property of `TrioSettings` must appear here exactly once, or in
    /// `excludedTrioSettingsFields` — enforced by the mapping totality test.
    static let trioSettingsFields: [BackupField<TrioSettings>] = [
        // Devices
        BackupField(String(localized: "CGM"), .devices, \.cgm, display: { v, _ in v.displayName }),
        BackupField(String(localized: "CGM Plugin"), .devices, \.cgmPluginIdentifier, display: BackupDisplay.text),
        BackupField(String(localized: "Smooth Glucose Value"), .devices, \.smoothGlucose, display: BackupDisplay.bool),
        BackupField(String(localized: "Use Local Glucose Server"), .devices, \.useLocalGlucoseSource, display: BackupDisplay.bool),
        BackupField(String(localized: "Local Glucose Server Port"), .devices, \.localGlucosePort, display: BackupDisplay.int),

        // Therapy
        BackupField(String(localized: "Glucose Units"), .therapy, \.units, display: { v, _ in v.rawValue }),

        // Features — Treatments
        BackupField(String(localized: "Display Meal Presets"), .features, \.displayPresets, display: BackupDisplay.bool),
        BackupField(
            String(localized: "Recommended Bolus Percentage"),
            .features,
            \.overrideFactor,
            picker: \.overrideFactor,
            display: BackupDisplay.percent
        ),
        BackupField(String(localized: "Enable Reduced Bolus Option"), .features, \.fattyMeals, display: BackupDisplay.bool),
        BackupField(
            String(localized: "Reduced Bolus Percentage"),
            .features,
            \.fattyMealFactor,
            picker: \.fattyMealFactor,
            display: BackupDisplay.percent
        ),
        BackupField(String(localized: "Enable Super Bolus Option"), .features, \.sweetMeals, display: BackupDisplay.bool),
        BackupField(
            String(localized: "Super Bolus Percentage"),
            .features,
            \.sweetMealFactor,
            picker: \.sweetMealFactor,
            display: BackupDisplay.percent
        ),
        BackupField(String(localized: "Very Low Glucose Warning"), .features, \.confirmBolus, display: BackupDisplay.bool),
        BackupField(String(localized: "Faster Bolus Confirmation"), .features, \.confirmBolusFaster, display: BackupDisplay.bool),
        BackupField(String(localized: "Enable Quick-Pick Boluses"), .features, \.enableQuickBolus, display: BackupDisplay.bool),
        BackupField(
            String(localized: "Max Carbs"),
            .features,
            \.maxCarbs,
            picker: \.maxCarbs,
            display: BackupDisplay.decimal(unit: String(localized: "g", comment: "Units for carbs"))
        ),
        BackupField(
            String(localized: "Max Fat"),
            .features,
            \.maxFat,
            picker: \.maxFat,
            display: BackupDisplay.decimal(unit: String(localized: "g", comment: "Units for carbs"))
        ),
        BackupField(
            String(localized: "Max Protein"),
            .features,
            \.maxProtein,
            picker: \.maxProtein,
            display: BackupDisplay.decimal(unit: String(localized: "g", comment: "Units for carbs"))
        ),
        BackupField(String(localized: "Enable Fat and Protein Entries"), .features, \.useFPUconversion, display: BackupDisplay.bool),
        BackupField(
            String(localized: "Fat and Protein Delay"),
            .features,
            \.delay,
            picker: \.delay,
            display: BackupDisplay.decimal(unit: String(localized: "minutes"))
        ),
        BackupField(
            String(localized: "Spread Interval"),
            .features,
            \.minuteInterval,
            picker: \.minuteInterval,
            display: BackupDisplay.decimal(unit: String(localized: "minutes"))
        ),
        BackupField(
            String(localized: "Fat and Protein Percentage"),
            .features,
            \.individualAdjustmentFactor,
            picker: \.individualAdjustmentFactor,
            display: BackupDisplay.percent
        ),
        BackupField(
            String(localized: "Allow Bolusing with Shortcuts"),
            .features,
            \.bolusShortcut,
            display: { v, _ in v.displayName }
        ),

        // Features — User Interface
        BackupField(String(localized: "Show X-Axis Grid Lines"), .features, \.xGridLines, display: BackupDisplay.bool),
        BackupField(String(localized: "Show Y-Axis Grid Lines"), .features, \.yGridLines, display: BackupDisplay.bool),
        BackupField(String(localized: "Show Low and High Thresholds"), .features, \.rulerMarks, display: BackupDisplay.bool),
        BackupField(String(localized: "Low Threshold"), .features, \.low, picker: \.low, display: BackupDisplay.glucose),
        BackupField(String(localized: "High Threshold"), .features, \.high, picker: \.high, display: BackupDisplay.glucose),
        BackupField(String(localized: "eA1c/GMI Display Unit"), .features, \.eA1cDisplayUnit, display: { v, _ in v.rawValue }),
        BackupField(
            String(localized: "Show Carbs Required Badge"),
            .features,
            \.showCarbsRequiredBadge,
            display: BackupDisplay.bool
        ),
        BackupField(
            String(localized: "Carbs Required Threshold"),
            .features,
            \.carbsRequiredThreshold,
            picker: \.carbsRequiredThreshold,
            display: BackupDisplay.decimal(unit: String(localized: "g", comment: "Units for carbs"))
        ),
        BackupField(String(localized: "Forecast Display Type"), .features, \.forecastDisplayType, display: { v, _ in v.rawValue }),
        BackupField(String(localized: "Glucose Color Scheme"), .features, \.glucoseColorScheme, display: { v, _ in v.rawValue }),
        BackupField(String(localized: "Time in Range Type"), .features, \.timeInRangeType, display: { v, _ in v.rawValue }),
        BackupField(
            String(localized: "Require Adjustments Confirmation"),
            .features,
            \.requireAdjustmentsConfirmation,
            display: BackupDisplay.bool
        ),
        BackupField(String(localized: "Show COB/IOB Chart"), .features, \.showCobIobChart, display: BackupDisplay.bool),
        BackupField(String(localized: "Hide Insulin Badge"), .features, \.hideInsulinBadge, display: BackupDisplay.bool),
        BackupField(String(localized: "Bolus Display Threshold"), .features, \.bolusDisplayThreshold, display: { v, _ in v.displayName }),

        // Features — Insulin
        BackupField(String(localized: "Allow Insulin Dilution"), .features, \.allowDilution, display: BackupDisplay.bool),
        BackupField(String(localized: "Insulin Concentration"), .features, \.insulinConcentration, display: BackupDisplay.plain),

        // Features — Debug & Watch
        BackupField(String(localized: "Debug Options"), .features, \.debugOptions, display: BackupDisplay.bool),
        BackupField(String(localized: "Garmin Watchface"), .features, \.garminWatchface, display: { v, _ in v.rawValue }),
        BackupField(String(localized: "Garmin Datafield"), .features, \.garminDatafield, display: { v, _ in v.rawValue }),
        BackupField(
            String(localized: "Garmin Primary Attribute"),
            .features,
            \.primaryAttributeChoice,
            display: { v, _ in v.rawValue }
        ),
        BackupField(
            String(localized: "Garmin Secondary Attribute"),
            .features,
            \.secondaryAttributeChoice,
            display: { v, _ in v.rawValue }
        ),
        BackupField(
            String(localized: "Garmin Watchface Data"),
            .features,
            \.isWatchfaceDataEnabled,
            display: BackupDisplay.bool
        ),

        // Notifications
        BackupField(String(localized: "Show Glucose App Badge"), .notifications, \.glucoseBadge, display: BackupDisplay.bool),
        BackupField(String(localized: "Enable Live Activity"), .notifications, \.useLiveActivity, display: BackupDisplay.bool),
        BackupField(
            String(localized: "Lock Screen Widget Style"),
            .notifications,
            \.lockScreenView,
            display: { v, _ in v.rawValue }
        ),
        BackupField(String(localized: "Smart Stack Widget Style"), .notifications, \.smartStackView, display: { v, _ in v.rawValue }),
        BackupField(
            String(localized: "Display Glucose Forecasts"),
            .notifications,
            \.displayGlucoseForecasts,
            display: BackupDisplay.bool
        ),
        BackupField(String(localized: "Add Glucose to Calendar"), .notifications, \.useCalendar, display: BackupDisplay.bool),
        BackupField(
            String(localized: "Display IOB and COB in Calendar"),
            .notifications,
            \.displayCalendarIOBandCOB,
            display: BackupDisplay.bool
        ),
        BackupField(
            String(localized: "Display Emojis in Calendar"),
            .notifications,
            \.displayCalendarEmojis,
            display: BackupDisplay.bool
        ),

        // Services
        BackupField(
            String(localized: "Allow Uploading to Nightscout"),
            .services,
            \.isUploadEnabled,
            display: BackupDisplay.bool
        ),
        BackupField(String(localized: "Upload Glucose"), .services, \.uploadGlucose, display: BackupDisplay.bool),
        BackupField(
            String(localized: "Allow Fetching From Nightscout"),
            .services,
            \.isDownloadEnabled,
            display: BackupDisplay.bool
        ),
        BackupField(String(localized: "Apple Health"), .services, \.useAppleHealth, display: BackupDisplay.bool)
    ]

    /// Deliberately never imported from a backup:
    /// - `closedLoop`: the looping mode must never silently change through a file import.
    static let excludedTrioSettingsFieldCount = 1

    /// Every stored property of `Preferences` must appear here exactly once, or in the exclusions —
    /// enforced by the mapping totality test.
    static let preferencesFields: [BackupField<Preferences>] = [
        // Devices
        BackupField(String(localized: "Insulin Type"), .devices, \.curve, display: { v, _ in v.rawValue }),

        // Therapy — Units and Limits
        BackupField(
            String(localized: "Maximum Insulin on Board (IOB)"),
            .therapy,
            \.maxIOB,
            picker: \.maxIOB,
            display: BackupDisplay.decimal(unit: "U")
        ),
        BackupField(
            String(localized: "Maximum Carbs on Board (COB)"),
            .therapy,
            \.maxCOB,
            picker: \.maxCOB,
            display: BackupDisplay.decimal(unit: String(localized: "g", comment: "Units for carbs"))
        ),
        BackupField(
            String(localized: "Minimum Safety Threshold"),
            .therapy,
            \.threshold_setting,
            picker: \.threshold_setting,
            display: BackupDisplay.glucose
        ),

        // Features
        BackupField(
            String(localized: "Max Meal Absorption Time"),
            .features,
            \.maxMealAbsorptionTime,
            picker: \.maxMealAbsorptionTime,
            display: BackupDisplay.decimal(unit: String(localized: "hours"))
        ),

        // Algorithm — Autosens
        BackupField(
            String(localized: "Autosens Max"),
            .algorithm,
            \.autosensMax,
            picker: \.autosensMax,
            display: BackupDisplay.percent
        ),
        BackupField(
            String(localized: "Autosens Min"),
            .algorithm,
            \.autosensMin,
            picker: \.autosensMin,
            display: BackupDisplay.percent
        ),
        BackupField(String(localized: "Rewind Resets Autosens"), .algorithm, \.rewindResetsAutosens, display: BackupDisplay.bool),

        // Algorithm — SMB
        BackupField(String(localized: "Enable SMB Always"), .algorithm, \.enableSMBAlways, display: BackupDisplay.bool),
        BackupField(String(localized: "Enable SMB With COB"), .algorithm, \.enableSMBWithCOB, display: BackupDisplay.bool),
        BackupField(
            String(localized: "Enable SMB With Temptarget"),
            .algorithm,
            \.enableSMBWithTemptarget,
            display: BackupDisplay.bool
        ),
        BackupField(String(localized: "Enable SMB After Carbs"), .algorithm, \.enableSMBAfterCarbs, display: BackupDisplay.bool),
        BackupField(
            String(localized: "Enable SMB With High Glucose"),
            .algorithm,
            \.enableSMB_high_bg,
            display: BackupDisplay.bool
        ),
        BackupField(
            String(localized: "High Glucose Target"),
            .algorithm,
            \.enableSMB_high_bg_target,
            picker: \.enableSMB_high_bg_target,
            display: BackupDisplay.glucose
        ),
        BackupField(
            String(localized: "Allow SMB With High Temptarget"),
            .algorithm,
            \.allowSMBWithHighTemptarget,
            display: BackupDisplay.bool
        ),
        BackupField(String(localized: "Enable UAM"), .algorithm, \.enableUAM, display: BackupDisplay.bool),
        BackupField(
            String(localized: "Max SMB Basal Minutes"),
            .algorithm,
            \.maxSMBBasalMinutes,
            picker: \.maxSMBBasalMinutes,
            display: BackupDisplay.decimal(unit: String(localized: "minutes"))
        ),
        BackupField(
            String(localized: "Max UAM Basal Minutes"),
            .algorithm,
            \.maxUAMSMBBasalMinutes,
            picker: \.maxUAMSMBBasalMinutes,
            display: BackupDisplay.decimal(unit: String(localized: "minutes"))
        ),
        BackupField(
            String(localized: "Max Allowed Glucose Rise for SMB"),
            .algorithm,
            \.maxDeltaBGthreshold,
            picker: \.maxDeltaBGthreshold,
            display: BackupDisplay.percent
        ),

        // Algorithm — Dynamic Settings
        BackupField(String(localized: "Dynamic ISF"), .algorithm, \.useNewFormula, display: BackupDisplay.bool),
        BackupField(String(localized: "Sigmoid Formula"), .algorithm, \.sigmoid, display: BackupDisplay.bool),
        BackupField(
            String(localized: "Adjustment Factor (AF)"),
            .algorithm,
            \.adjustmentFactor,
            picker: \.adjustmentFactor,
            display: BackupDisplay.percent
        ),
        BackupField(
            String(localized: "Sigmoid Adjustment Factor"),
            .algorithm,
            \.adjustmentFactorSigmoid,
            picker: \.adjustmentFactorSigmoid,
            display: BackupDisplay.percent
        ),
        BackupField(String(localized: "Use Weighted Average of TDD"), .algorithm, \.useWeightedAverage, display: BackupDisplay.bool),
        BackupField(
            String(localized: "Weighted Average of TDD"),
            .algorithm,
            \.weightPercentage,
            picker: \.weightPercentage,
            display: BackupDisplay.percent
        ),
        BackupField(String(localized: "Adjust Basal"), .algorithm, \.tddAdjBasal, display: BackupDisplay.bool),

        // Algorithm — Target Behavior
        BackupField(
            String(localized: "High Temptarget Raises Sensitivity"),
            .algorithm,
            \.highTemptargetRaisesSensitivity,
            display: BackupDisplay.bool
        ),
        BackupField(
            String(localized: "Low Temptarget Lowers Sensitivity"),
            .algorithm,
            \.lowTemptargetLowersSensitivity,
            display: BackupDisplay.bool
        ),
        BackupField(
            String(localized: "Sensitivity Raises Target"),
            .algorithm,
            \.sensitivityRaisesTarget,
            display: BackupDisplay.bool
        ),
        BackupField(
            String(localized: "Resistance Lowers Target"),
            .algorithm,
            \.resistanceLowersTarget,
            display: BackupDisplay.bool
        ),
        BackupField(
            String(localized: "Advanced Target Adjustments"),
            .algorithm,
            \.advTargetAdjustments,
            display: BackupDisplay.bool
        ),
        BackupField(String(localized: "Exercise Mode"), .algorithm, \.exerciseMode, display: BackupDisplay.bool),
        BackupField(
            String(localized: "Half Basal Exercise Target"),
            .algorithm,
            \.halfBasalExerciseTarget,
            picker: \.halfBasalExerciseTarget,
            display: BackupDisplay.glucose
        ),
        BackupField(String(localized: "Wide BG Target Range"), .algorithm, \.wideBGTargetRange, display: BackupDisplay.bool),

        // Algorithm — Additionals
        BackupField(
            String(localized: "Max Daily Safety Multiplier"),
            .algorithm,
            \.maxDailySafetyMultiplier,
            picker: \.maxDailySafetyMultiplier,
            display: BackupDisplay.percent
        ),
        BackupField(
            String(localized: "Current Basal Safety Multiplier"),
            .algorithm,
            \.currentBasalSafetyMultiplier,
            picker: \.currentBasalSafetyMultiplier,
            display: BackupDisplay.percent
        ),
        BackupField(String(localized: "Use Custom Peak Time"), .algorithm, \.useCustomPeakTime, display: BackupDisplay.bool),
        BackupField(
            String(localized: "Insulin Peak Time"),
            .algorithm,
            \.insulinPeakTime,
            picker: \.insulinPeakTime,
            display: BackupDisplay.decimal(unit: String(localized: "minutes"))
        ),
        BackupField(String(localized: "Skip Neutral Temps"), .algorithm, \.skipNeutralTemps, display: BackupDisplay.bool),
        BackupField(String(localized: "Unsuspend If No Temp"), .algorithm, \.unsuspendIfNoTemp, display: BackupDisplay.bool),
        BackupField(String(localized: "Suspend Zeros IOB"), .algorithm, \.suspendZerosIOB, display: BackupDisplay.bool),
        BackupField(
            String(localized: "SMB Delivery Ratio"),
            .algorithm,
            \.smbDeliveryRatio,
            picker: \.smbDeliveryRatio,
            display: BackupDisplay.percent
        ),
        BackupField(
            String(localized: "SMB Interval"),
            .algorithm,
            \.smbInterval,
            picker: \.smbInterval,
            display: BackupDisplay.decimal(unit: String(localized: "minutes"))
        ),
        BackupField(
            String(localized: "Min 5m Carb Impact"),
            .algorithm,
            \.min5mCarbimpact,
            picker: \.min5mCarbimpact,
            display: BackupDisplay.glucose
        ),
        BackupField(
            String(localized: "Remaining Carbs Percentage"),
            .algorithm,
            \.remainingCarbsFraction,
            picker: \.remainingCarbsFraction,
            display: BackupDisplay.percent
        ),
        BackupField(
            String(localized: "Remaining Carbs Cap"),
            .algorithm,
            \.remainingCarbsCap,
            picker: \.remainingCarbsCap,
            display: BackupDisplay.decimal(unit: String(localized: "g", comment: "Units for carbs"))
        ),
        BackupField(
            String(localized: "Noisy CGM Target Increase"),
            .algorithm,
            \.noisyCGMTargetMultiplier,
            picker: \.noisyCGMTargetMultiplier,
            display: BackupDisplay.percent
        ),
        BackupField(String(localized: "A52 Risk Enable"), .algorithm, \.a52RiskEnable, display: BackupDisplay.bool),
        BackupField(
            String(localized: "Update Interval"),
            .algorithm,
            \.updateInterval,
            picker: \.updateInterval,
            display: BackupDisplay.decimal(unit: String(localized: "minutes"))
        ),
        BackupField(String(localized: "Carbs Required Threshold"), .algorithm, \.carbsReqThreshold, picker: \.carbsReqThreshold, display: BackupDisplay.decimal(unit: String(localized: "g", comment: "Units for carbs")))
    ]

    /// Deliberately never imported from a backup:
    /// - `bolusIncrement`: the pump overwrites it on attach — pump-authoritative.
    /// - `timestamp`: runtime bookkeeping, not configuration.
    static let excludedPreferencesFieldCount = 2

    // MARK: - Merge

    /// Copies all fields of the selected categories from `imported` onto a copy of `current`,
    /// clamping/snapping guarded values. Returns the merged value plus one warning per adjustment.
    static func merge<Root>(
        _ fields: [BackupField<Root>],
        current: Root,
        imported: Root,
        categories: Set<SettingsBackupCategory>,
        units: GlucoseUnits
    ) -> (result: Root, warnings: [String]) {
        var result = current
        var warnings: [String] = []
        for field in fields where categories.contains(field.category) {
            if let warning = field.apply(into: &result, from: imported, units: units) {
                warnings.append(warning)
            }
        }
        return (result, warnings)
    }

    /// The per-field differences the selected categories would apply, keyed by category.
    /// Uses the same tables and the same clamp/snap as `merge`, so the preview matches the apply.
    static func settingChanges<Root>(
        _ fields: [BackupField<Root>],
        current: Root,
        imported: Root,
        units: GlucoseUnits
    ) -> [SettingsBackupCategory: [ImportChange]] {
        var changes: [SettingsBackupCategory: [ImportChange]] = [:]
        for field in fields where field.differs(current: current, imported: imported, units: units) {
            changes[field.category, default: []].append(ImportChange(
                label: field.label,
                oldDisplay: field.displayCurrent(current, units: units),
                newDisplay: field.displayImported(imported, units: units)
            ))
        }
        return changes
    }

    // MARK: - Guardrails

    /// Clamps to the guardrail bounds resolved from `PickerSettingsProvider` — the same limits the
    /// settings screens enforce. Values inside the bounds are preserved exactly as exported (Trio
    /// itself stores values that sit between picker steps, e.g. defaults).
    static func clampAndSnap(_ value: Decimal, to setting: PickerSetting, units _: GlucoseUnits) -> Decimal {
        value.clamp(to: setting)
    }

    /// Snaps a value to the nearest entry of an arbitrary supported list (e.g. pump-supported
    /// basal rates). Returns the value unchanged when the list is empty.
    static func snap(_ value: Decimal, toSupported supported: [Decimal]) -> Decimal {
        supported.min(by: { abs($0 - value) < abs($1 - value) }) ?? value
    }

    // MARK: - Therapy validation

    /// Values below this are unmistakably mmol/L; backups must store mg/dL.
    private static let glucoseMmolThreshold: Decimal = 39
    private static let isfMmolThreshold: Decimal = 9
    private static let scheduleGridMinutes = 30

    /// Validates and normalizes the therapy section: positive values, mg/dL sanity, entries
    /// deduplicated onto the 30-minute grid, sorted, first entry forced to midnight, and basal
    /// rates snapped to the pump's supported rates when a pump is connected.
    static func validateTherapy(
        _ therapy: SettingsBackup.Therapy,
        supportedBasalRates: [Decimal]? = nil
    ) throws -> NormalizedTherapy {
        var normalized = NormalizedTherapy()

        if let basalProfile = therapy.basalProfile {
            guard basalProfile.isNotEmpty else { throw TherapyValidationError.emptySchedule(String(localized: "basal rates")) }
            guard basalProfile.allSatisfy({ $0.rate > 0 }) else {
                throw TherapyValidationError.nonPositiveValue(String(localized: "basal rates"))
            }
            var entries = normalizedMinutes(basalProfile.map { ($0.rate, $0.minutes) })
            if let supported = supportedBasalRates, supported.isNotEmpty {
                var snappedCount = 0
                entries = entries.map { value, minutes in
                    let snapped = snap(value, toSupported: supported)
                    if snapped != value { snappedCount += 1 }
                    return (snapped, minutes)
                }
                if snappedCount > 0 {
                    normalized.warnings.append(
                        String(localized: "\(snappedCount) basal rate(s) adjusted to the nearest rate supported by your pump.")
                    )
                }
            }
            guard entries.map(\.0).reduce(0, +) > 0 else { throw TherapyValidationError.zeroTotalBasal }
            normalized.basalProfile = entries.map {
                BasalProfileEntry(start: startString(forMinutes: $0.1), minutes: $0.1, rate: $0.0)
            }
        }

        if let sensitivities = therapy.insulinSensitivities {
            let entries = sensitivities.sensitivities
            guard entries.isNotEmpty else {
                throw TherapyValidationError.emptySchedule(String(localized: "insulin sensitivities"))
            }
            guard entries.allSatisfy({ $0.sensitivity > 0 }) else {
                throw TherapyValidationError.nonPositiveValue(String(localized: "insulin sensitivities"))
            }
            guard entries.allSatisfy({ $0.sensitivity >= isfMmolThreshold }) else {
                throw TherapyValidationError.looksLikeMmolL(String(localized: "insulin sensitivities"))
            }
            let normalizedEntries = normalizedMinutes(entries.map { ($0.sensitivity, $0.offset) })
            normalized.insulinSensitivities = InsulinSensitivities(
                units: .mgdL,
                userPreferredUnits: .mgdL,
                sensitivities: normalizedEntries.map {
                    InsulinSensitivityEntry(sensitivity: $0.0, offset: $0.1, start: startString(forMinutes: $0.1))
                }
            )
        }

        if let carbRatios = therapy.carbRatios {
            let entries = carbRatios.schedule
            guard entries.isNotEmpty else { throw TherapyValidationError.emptySchedule(String(localized: "carb ratios")) }
            guard entries.allSatisfy({ $0.ratio > 0 }) else {
                throw TherapyValidationError.nonPositiveValue(String(localized: "carb ratios"))
            }
            let normalizedEntries = normalizedMinutes(entries.map { ($0.ratio, $0.offset) })
            normalized.carbRatios = CarbRatios(
                units: carbRatios.units,
                schedule: normalizedEntries.map {
                    CarbRatioEntry(start: startString(forMinutes: $0.1), offset: $0.1, ratio: $0.0)
                }
            )
        }

        if let bgTargets = therapy.bgTargets {
            let entries = bgTargets.targets
            guard entries.isNotEmpty else { throw TherapyValidationError.emptySchedule(String(localized: "glucose targets")) }
            guard entries.allSatisfy({ $0.low > 0 }) else {
                throw TherapyValidationError.nonPositiveValue(String(localized: "glucose targets"))
            }
            guard entries.allSatisfy({ $0.low >= glucoseMmolThreshold }) else {
                throw TherapyValidationError.looksLikeMmolL(String(localized: "glucose targets"))
            }
            let normalizedEntries = normalizedMinutes(entries.map { ($0.low, $0.offset) })
            // Trio uses a single target value: high always equals low.
            normalized.bgTargets = BGTargets(
                units: .mgdL,
                userPreferredUnits: .mgdL,
                targets: normalizedEntries.map {
                    BGTargetEntry(low: $0.0, high: $0.0, start: startString(forMinutes: $0.1), offset: $0.1)
                }
            )
        }

        return normalized
    }

    /// Aligns entries to the 30-minute grid, clamps into a single day, deduplicates by time
    /// (last one wins), sorts, and forces the first entry to midnight.
    private static func normalizedMinutes(_ entries: [(Decimal, Int)]) -> [(Decimal, Int)] {
        var byMinutes: [Int: Decimal] = [:]
        for (value, minutes) in entries {
            let clamped = Swift.min(Swift.max(minutes, 0), 24 * 60 - 1)
            let aligned = (clamped / scheduleGridMinutes) * scheduleGridMinutes
            byMinutes[aligned] = value
        }
        var sorted = byMinutes.sorted { $0.key < $1.key }.map { ($0.value, $0.key) }
        if let first = sorted.first, first.1 != 0 {
            sorted[0] = (first.0, 0)
        }
        return sorted
    }

    static func startString(forMinutes minutes: Int) -> String {
        String(format: "%02d:%02d:00", minutes / 60, minutes % 60)
    }

    /// Per-entry changes for one therapy schedule (label, e.g. "Basal Rates"), rendering each
    /// slot's current → imported value. Slots present on only one side show "—" on the other.
    static func therapyScheduleChange(
        label: String,
        current: [(minutes: Int, display: String)],
        imported: [(minutes: Int, display: String)]
    ) -> TherapyScheduleChange? {
        let currentByMinutes = Dictionary(current.map { ($0.minutes, $0.display) }, uniquingKeysWith: { _, last in last })
        let importedByMinutes = Dictionary(imported.map { ($0.minutes, $0.display) }, uniquingKeysWith: { _, last in last })
        let allMinutes = Set(currentByMinutes.keys).union(importedByMinutes.keys).sorted()

        let entryChanges: [ImportChange] = allMinutes.compactMap { minutes in
            let old = currentByMinutes[minutes]
            let new = importedByMinutes[minutes]
            guard old != new else { return nil }
            return ImportChange(
                label: String(format: "%02d:%02d", minutes / 60, minutes % 60),
                oldDisplay: old ?? "—",
                newDisplay: new ?? "—"
            )
        }

        guard entryChanges.isNotEmpty else { return nil }
        return TherapyScheduleChange(label: label, entryChanges: entryChanges)
    }

    // MARK: - Preset conflict resolution

    struct PresetResolution<Preset> {
        var namesToDelete: [String] = []
        var toStore: [Preset] = []
        var changes: [PresetChange] = []
        var warnings: [String] = []
    }

    /// Resolves imported presets against the existing ones according to the chosen strategy.
    /// Presets that are currently running (`enabled == true`) are never deleted or replaced.
    /// Duplicate names inside the file collapse to the last occurrence.
    static func resolvePresetConflicts<Preset>(
        imported: [Preset],
        existingNames: [String],
        activeNames: Set<String>,
        strategy: PresetConflictStrategy,
        name: (Preset) -> String
    ) -> PresetResolution<Preset> {
        var resolution = PresetResolution<Preset>()

        var importedByName: [String: Preset] = [:]
        var importedOrder: [String] = []
        for preset in imported {
            let presetName = name(preset)
            if importedByName[presetName] != nil {
                resolution.warnings.append(
                    String(localized: "Duplicate preset name \"\(presetName)\" in backup — the last occurrence is used.")
                )
            } else {
                importedOrder.append(presetName)
            }
            importedByName[presetName] = preset
        }

        let existing = Set(existingNames)

        for presetName in importedOrder {
            guard let preset = importedByName[presetName] else { continue }

            if activeNames.contains(presetName) {
                resolution.changes.append(PresetChange(name: presetName, kind: .activeSkipped))
                continue
            }

            if existing.contains(presetName) {
                switch strategy {
                case .replaceSameNamed,
                     .replaceAll:
                    resolution.namesToDelete.append(presetName)
                    resolution.toStore.append(preset)
                    resolution.changes.append(PresetChange(name: presetName, kind: .replaced))
                case .keepExisting:
                    resolution.changes.append(PresetChange(name: presetName, kind: .keptExisting))
                }
            } else {
                resolution.toStore.append(preset)
                resolution.changes.append(PresetChange(name: presetName, kind: .added))
            }
        }

        if strategy == .replaceAll {
            let importedNames = Set(importedOrder)
            for existingName in existingNames where !importedNames.contains(existingName) {
                if activeNames.contains(existingName) {
                    resolution.changes.append(PresetChange(name: existingName, kind: .activeSkipped))
                } else {
                    resolution.namesToDelete.append(existingName)
                    resolution.changes.append(PresetChange(name: existingName, kind: .removed))
                }
            }
        }

        return resolution
    }
}

extension SettingsImportApplier {
    struct PumpSettingsMergeResult {
        let result: PumpSettings
        let warnings: [String]
        let changes: [ImportChange]
    }

    /// `PumpSettings` has `let` members, so it is merged as a whole rather than via the field
    /// tables. All three values belong to the therapy category and go through the same guardrail
    /// clamp/snap as everything else.
    static func mergePumpSettings(
        current: PumpSettings,
        imported: PumpSettings,
        units: GlucoseUnits
    ) -> PumpSettingsMergeResult {
        var warnings: [String] = []
        var changes: [ImportChange] = []

        func adjusted(
            _ label: String,
            _ raw: Decimal,
            _ currentValue: Decimal,
            _ picker: KeyPath<DecimalPickerSettings, PickerSetting>,
            unit: String
        ) -> Decimal {
            let setting = PickerSettingsProvider.shared.settings[keyPath: picker]
            let value = clampAndSnap(raw, to: setting, units: units)
            if value != raw {
                warnings.append(String(localized: "\(label): \(raw) \(unit) adjusted to \(value) \(unit) to respect limits"))
            }
            if value != currentValue {
                changes.append(ImportChange(
                    label: label,
                    oldDisplay: "\(currentValue) \(unit)",
                    newDisplay: "\(value) \(unit)"
                ))
            }
            return value
        }

        let dia = adjusted(
            String(localized: "Duration of Insulin Action"),
            imported.insulinActionCurve,
            current.insulinActionCurve,
            \.dia,
            unit: String(localized: "hours")
        )
        let maxBolus = adjusted(
            String(localized: "Maximum Bolus"),
            imported.maxBolus,
            current.maxBolus,
            \.maxBolus,
            unit: "U"
        )
        let maxBasal = adjusted(
            String(localized: "Maximum Basal Rate"),
            imported.maxBasal,
            current.maxBasal,
            \.maxBasal,
            unit: String(localized: "U/hr", comment: "Insulin unit per hour abbreviation")
        )

        return PumpSettingsMergeResult(
            result: PumpSettings(insulinActionCurve: dia, maxBolus: maxBolus, maxBasal: maxBasal),
            warnings: warnings,
            changes: changes
        )
    }
}
