import Foundation

/// Metadata for a single setting field, used by the audit log
struct SettingMetadata {
    let key: String
    let name: String
    let category: String
    let subcategory: String
    let unit: String?
}

/// Registry mapping TrioSettings and Preferences field names to human-readable metadata
enum SettingsMetadataRegistry {
    // MARK: - TrioSettings metadata

    static let trioSettingsMap: [String: SettingMetadata] = {
        var map: [String: SettingMetadata] = [:]
        for m in trioSettingsMetadata { map[m.key] = m }
        return map
    }()

    static let preferencesMap: [String: SettingMetadata] = {
        var map: [String: SettingMetadata] = [:]
        for m in preferencesMetadata { map[m.key] = m }
        return map
    }()

    // MARK: - Profile Presets metadata keys

    /// Well-known setting keys for profile preset lifecycle events.
    enum ProfileKeys {
        static let activeProfile = "profile.active"
        static let presetCreated = "profile.created"
        static let presetDeleted = "profile.deleted"
        static let presetUpdated = "profile.updated"
    }

    private static let trioSettingsMetadata: [SettingMetadata] = [
        // Units & Basics
        .init(key: "units", name: "Glucose Units", category: "Therapy", subcategory: "Units & Limits", unit: nil),
        .init(key: "closedLoop", name: "Closed Loop", category: "Features", subcategory: "Automated Insulin Delivery", unit: nil),
        .init(key: "debugOptions", name: "Debug Options", category: "Features", subcategory: "Developer", unit: nil),
        // CGM
        .init(key: "cgm", name: "CGM Type", category: "Devices", subcategory: "CGM", unit: nil),
        .init(key: "cgmPluginIdentifier", name: "CGM Plugin", category: "Devices", subcategory: "CGM", unit: nil),
        .init(key: "smoothGlucose", name: "Smooth Glucose", category: "Devices", subcategory: "CGM", unit: nil),
        .init(key: "uploadGlucose", name: "Upload Glucose", category: "Services", subcategory: "Nightscout", unit: nil),
        // Nightscout
        .init(key: "isUploadEnabled", name: "Upload Enabled", category: "Services", subcategory: "Nightscout", unit: nil),
        .init(key: "isDownloadEnabled", name: "Download Enabled", category: "Services", subcategory: "Nightscout", unit: nil),
        // Notifications
        .init(key: "notificationsPump", name: "Pump Notifications", category: "Notifications", subcategory: "General", unit: nil),
        .init(key: "notificationsCgm", name: "CGM Notifications", category: "Notifications", subcategory: "General", unit: nil),
        .init(key: "notificationsCarb", name: "Carb Notifications", category: "Notifications", subcategory: "General", unit: nil),
        .init(key: "notificationsAlgorithm", name: "Algorithm Notifications", category: "Notifications", subcategory: "General", unit: nil),
        .init(key: "glucoseNotificationsOption", name: "Glucose Notification Option", category: "Notifications", subcategory: "Glucose", unit: nil),
        .init(key: "addSourceInfoToGlucoseNotifications", name: "Add Source Info to Notifications", category: "Notifications", subcategory: "Glucose", unit: nil),
        // Glucose Thresholds
        .init(key: "lowGlucose", name: "Low Glucose Alert", category: "Notifications", subcategory: "Glucose Alerts", unit: "mg/dL"),
        .init(key: "highGlucose", name: "High Glucose Alert", category: "Notifications", subcategory: "Glucose Alerts", unit: "mg/dL"),
        .init(key: "carbsRequiredThreshold", name: "Carbs Required Threshold", category: "Algorithm", subcategory: "Carbs", unit: "g"),
        .init(key: "showCarbsRequiredBadge", name: "Show Carbs Required Badge", category: "Features", subcategory: "Display", unit: nil),
        // Display
        .init(key: "high", name: "High Glucose Display", category: "Features", subcategory: "Display", unit: "mg/dL"),
        .init(key: "low", name: "Low Glucose Display", category: "Features", subcategory: "Display", unit: "mg/dL"),
        .init(key: "glucoseColorScheme", name: "Glucose Color Scheme", category: "Features", subcategory: "Display", unit: nil),
        .init(key: "xGridLines", name: "X Grid Lines", category: "Features", subcategory: "Display", unit: nil),
        .init(key: "yGridLines", name: "Y Grid Lines", category: "Features", subcategory: "Display", unit: nil),
        .init(key: "bolusDisplayThreshold", name: "Bolus Display Threshold", category: "Features", subcategory: "Display", unit: "U"),
        .init(key: "forecastDisplayType", name: "Forecast Display Type", category: "Features", subcategory: "Display", unit: nil),
        .init(key: "showCobIobChart", name: "Show COB/IOB Chart", category: "Features", subcategory: "Display", unit: nil),
        .init(key: "rulerMarks", name: "Ruler Marks", category: "Features", subcategory: "Display", unit: nil),
        .init(key: "hideInsulinBadge", name: "Hide Insulin Badge", category: "Features", subcategory: "Display", unit: nil),
        // Insulin Concentration
        .init(key: "allowDilution", name: "Allow Dilution", category: "Therapy", subcategory: "Units & Limits", unit: nil),
        .init(key: "insulinConcentration", name: "Insulin Concentration", category: "Therapy", subcategory: "Units & Limits", unit: nil),
        // Bolus
        .init(key: "confirmBolus", name: "Confirm Bolus", category: "Features", subcategory: "Bolus", unit: nil),
        .init(key: "confirmBolusFaster", name: "Confirm Bolus Faster", category: "Features", subcategory: "Bolus", unit: nil),
        // Meal / FPU
        .init(key: "useFPUconversion", name: "Use FPU Conversion", category: "Features", subcategory: "Meals", unit: nil),
        .init(key: "fattyMeals", name: "Fatty Meals", category: "Features", subcategory: "Meals", unit: nil),
        .init(key: "fattyMealFactor", name: "Fatty Meal Factor", category: "Features", subcategory: "Meals", unit: nil),
        .init(key: "sweetMeals", name: "Sweet Meals", category: "Features", subcategory: "Meals", unit: nil),
        .init(key: "sweetMealFactor", name: "Sweet Meal Factor", category: "Features", subcategory: "Meals", unit: nil),
        .init(key: "maxCarbs", name: "Max Carbs", category: "Features", subcategory: "Meals", unit: "g"),
        .init(key: "maxFat", name: "Max Fat", category: "Features", subcategory: "Meals", unit: "g"),
        .init(key: "maxProtein", name: "Max Protein", category: "Features", subcategory: "Meals", unit: "g"),
        .init(key: "individualAdjustmentFactor", name: "Individual Adjustment Factor", category: "Features", subcategory: "Meals", unit: nil),
        .init(key: "minuteInterval", name: "FPU Minute Interval", category: "Features", subcategory: "Meals", unit: "min"),
        .init(key: "delay", name: "FPU Delay", category: "Features", subcategory: "Meals", unit: "min"),
        // Health & Calendar
        .init(key: "useAppleHealth", name: "Use Apple Health", category: "Services", subcategory: "Apple Health", unit: nil),
        .init(key: "useCalendar", name: "Use Calendar", category: "Features", subcategory: "Calendar", unit: nil),
        .init(key: "displayCalendarIOBandCOB", name: "Calendar IOB and COB", category: "Features", subcategory: "Calendar", unit: nil),
        .init(key: "displayCalendarEmojis", name: "Calendar Emojis", category: "Features", subcategory: "Calendar", unit: nil),
        // Live Activity / Watch
        .init(key: "useLiveActivity", name: "Use Live Activity", category: "Features", subcategory: "Live Activity", unit: nil),
        .init(key: "lockScreenView", name: "Lock Screen View", category: "Features", subcategory: "Live Activity", unit: nil),
        .init(key: "smartStackView", name: "Smart Stack View", category: "Features", subcategory: "Live Activity", unit: nil),
        .init(key: "bolusShortcut", name: "Bolus Shortcut", category: "Features", subcategory: "Watch", unit: nil),
        // UI
        .init(key: "eA1cDisplayUnit", name: "eA1c Display Unit", category: "Features", subcategory: "Display", unit: nil),
        .init(key: "glucoseBadge", name: "Glucose Badge", category: "Features", subcategory: "Display", unit: nil),
        .init(key: "displayPresets", name: "Display Presets", category: "Features", subcategory: "Display", unit: nil),
        .init(key: "overrideFactor", name: "Override Factor", category: "Algorithm", subcategory: "Overrides", unit: nil),
        .init(key: "timeInRangeType", name: "Time in Range Type", category: "Features", subcategory: "Display", unit: nil),
        // Garmin
        .init(key: "garminWatchface", name: "Garmin Watchface", category: "Devices", subcategory: "Garmin", unit: nil),
        .init(key: "garminDatafield", name: "Garmin Datafield", category: "Devices", subcategory: "Garmin", unit: nil),
        .init(key: "primaryAttributeChoice", name: "Garmin Primary Attribute", category: "Devices", subcategory: "Garmin", unit: nil),
        .init(key: "secondaryAttributeChoice", name: "Garmin Secondary Attribute", category: "Devices", subcategory: "Garmin", unit: nil),
        .init(key: "isWatchfaceDataEnabled", name: "Garmin Data Enabled", category: "Devices", subcategory: "Garmin", unit: nil),
        // Glucose Source
        .init(key: "useLocalGlucoseSource", name: "Use Local Glucose Source", category: "Devices", subcategory: "CGM", unit: nil),
        .init(key: "localGlucosePort", name: "Local Glucose Port", category: "Devices", subcategory: "CGM", unit: nil),
    ]

    private static let preferencesMetadata: [SettingMetadata] = [
        // IOB / Safety
        .init(key: "maxIOB", name: "Max IOB", category: "Algorithm", subcategory: "Safety", unit: "U"),
        .init(key: "maxDailySafetyMultiplier", name: "Max Daily Safety Multiplier", category: "Algorithm", subcategory: "Safety", unit: nil),
        .init(key: "currentBasalSafetyMultiplier", name: "Current Basal Safety Multiplier", category: "Algorithm", subcategory: "Safety", unit: nil),
        // Autosens
        .init(key: "autosensMax", name: "Autosens Max", category: "Algorithm", subcategory: "Autosens", unit: nil),
        .init(key: "autosensMin", name: "Autosens Min", category: "Algorithm", subcategory: "Autosens", unit: nil),
        // SMB
        .init(key: "smbDeliveryRatio", name: "SMB Delivery Ratio", category: "Algorithm", subcategory: "SMB", unit: nil),
        .init(key: "enableSMBWithCOB", name: "Enable SMB with COB", category: "Algorithm", subcategory: "SMB", unit: nil),
        .init(key: "enableSMBWithTemptarget", name: "Enable SMB with Temp Target", category: "Algorithm", subcategory: "SMB", unit: nil),
        .init(key: "enableSMBAlways", name: "Enable SMB Always", category: "Algorithm", subcategory: "SMB", unit: nil),
        .init(key: "enableSMBAfterCarbs", name: "Enable SMB After Carbs", category: "Algorithm", subcategory: "SMB", unit: nil),
        .init(key: "allowSMBWithHighTemptarget", name: "Allow SMB with High Temp Target", category: "Algorithm", subcategory: "SMB", unit: nil),
        .init(key: "maxSMBBasalMinutes", name: "Max SMB Basal Minutes", category: "Algorithm", subcategory: "SMB", unit: "min"),
        .init(key: "maxUAMSMBBasalMinutes", name: "Max UAM SMB Basal Minutes", category: "Algorithm", subcategory: "SMB", unit: "min"),
        .init(key: "smbInterval", name: "SMB Interval", category: "Algorithm", subcategory: "SMB", unit: "min"),
        .init(key: "enableSMB_high_bg", name: "Enable SMB at High BG", category: "Algorithm", subcategory: "SMB", unit: nil),
        .init(key: "enableSMB_high_bg_target", name: "SMB High BG Target", category: "Algorithm", subcategory: "SMB", unit: "mg/dL"),
        // Targets
        .init(key: "highTemptargetRaisesSensitivity", name: "High Temp Target Raises Sensitivity", category: "Algorithm", subcategory: "Target Behavior", unit: nil),
        .init(key: "lowTemptargetLowersSensitivity", name: "Low Temp Target Lowers Sensitivity", category: "Algorithm", subcategory: "Target Behavior", unit: nil),
        .init(key: "sensitivityRaisesTarget", name: "Sensitivity Raises Target", category: "Algorithm", subcategory: "Target Behavior", unit: nil),
        .init(key: "resistanceLowersTarget", name: "Resistance Lowers Target", category: "Algorithm", subcategory: "Target Behavior", unit: nil),
        .init(key: "advTargetAdjustments", name: "Advanced Target Adjustments", category: "Algorithm", subcategory: "Target Behavior", unit: nil),
        .init(key: "halfBasalExerciseTarget", name: "Half Basal Exercise Target", category: "Algorithm", subcategory: "Target Behavior", unit: "mg/dL"),
        .init(key: "exerciseMode", name: "Exercise Mode", category: "Algorithm", subcategory: "Target Behavior", unit: nil),
        .init(key: "wideBGTargetRange", name: "Wide BG Target Range", category: "Algorithm", subcategory: "Target Behavior", unit: nil),
        // Carbs
        .init(key: "maxCOB", name: "Max COB", category: "Algorithm", subcategory: "Carbs", unit: "g"),
        .init(key: "maxMealAbsorptionTime", name: "Max Meal Absorption Time", category: "Algorithm", subcategory: "Carbs", unit: "h"),
        .init(key: "min5mCarbimpact", name: "Min 5m Carb Impact", category: "Algorithm", subcategory: "Carbs", unit: nil),
        .init(key: "remainingCarbsFraction", name: "Remaining Carbs Fraction", category: "Algorithm", subcategory: "Carbs", unit: nil),
        .init(key: "remainingCarbsCap", name: "Remaining Carbs Cap", category: "Algorithm", subcategory: "Carbs", unit: "g"),
        .init(key: "carbsReqThreshold", name: "Carbs Required Threshold", category: "Algorithm", subcategory: "Carbs", unit: "g"),
        // Insulin
        .init(key: "curve", name: "Insulin Curve", category: "Algorithm", subcategory: "Insulin", unit: nil),
        .init(key: "useCustomPeakTime", name: "Use Custom Peak Time", category: "Algorithm", subcategory: "Insulin", unit: nil),
        .init(key: "insulinPeakTime", name: "Insulin Peak Time", category: "Algorithm", subcategory: "Insulin", unit: "min"),
        .init(key: "bolusIncrement", name: "Bolus Increment", category: "Algorithm", subcategory: "Insulin", unit: "U"),
        // Dynamic ISF
        .init(key: "sigmoid", name: "Sigmoid", category: "Algorithm", subcategory: "Dynamic ISF", unit: nil),
        .init(key: "useNewFormula", name: "Use New Formula", category: "Algorithm", subcategory: "Dynamic ISF", unit: nil),
        .init(key: "useWeightedAverage", name: "Use Weighted Average", category: "Algorithm", subcategory: "Dynamic ISF", unit: nil),
        .init(key: "weightPercentage", name: "Weight Percentage", category: "Algorithm", subcategory: "Dynamic ISF", unit: nil),
        .init(key: "tddAdjBasal", name: "TDD Adjust Basal", category: "Algorithm", subcategory: "Dynamic ISF", unit: nil),
        .init(key: "adjustmentFactor", name: "Adjustment Factor", category: "Algorithm", subcategory: "Dynamic ISF", unit: nil),
        .init(key: "adjustmentFactorSigmoid", name: "Adjustment Factor Sigmoid", category: "Algorithm", subcategory: "Dynamic ISF", unit: nil),
        // Other
        .init(key: "rewindResetsAutosens", name: "Rewind Resets Autosens", category: "Algorithm", subcategory: "Autosens", unit: nil),
        .init(key: "enableUAM", name: "Enable UAM", category: "Algorithm", subcategory: "SMB", unit: nil),
        .init(key: "a52RiskEnable", name: "A52 Risk Enable", category: "Algorithm", subcategory: "Safety", unit: nil),
        .init(key: "noisyCGMTargetMultiplier", name: "Noisy CGM Target Multiplier", category: "Algorithm", subcategory: "Safety", unit: nil),
        .init(key: "suspendZerosIOB", name: "Suspend Zeros IOB", category: "Algorithm", subcategory: "Safety", unit: nil),
        .init(key: "skipNeutralTemps", name: "Skip Neutral Temps", category: "Algorithm", subcategory: "Basal", unit: nil),
        .init(key: "unsuspendIfNoTemp", name: "Unsuspend If No Temp", category: "Algorithm", subcategory: "Basal", unit: nil),
        .init(key: "maxDeltaBGthreshold", name: "Max Delta BG Threshold", category: "Algorithm", subcategory: "Safety", unit: nil),
        .init(key: "threshold_setting", name: "Threshold Setting", category: "Algorithm", subcategory: "Safety", unit: "mg/dL"),
        .init(key: "updateInterval", name: "Update Interval", category: "Algorithm", subcategory: "General", unit: "min"),
    ]
}
