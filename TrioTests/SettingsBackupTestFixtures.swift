import Foundation
@testable import Trio

/// Shared builders for settings-backup tests. The "maximally different" structs flip or change
/// EVERY stored property relative to the defaults, with all numeric values inside the guardrail
/// bounds — the totality tests rely on that.
enum SettingsBackupTestFixtures {
    static func maximallyDifferentTrioSettings() -> TrioSettings {
        var settings = TrioSettings()
        settings.units = .mmolL
        settings.closedLoop = true
        settings.isUploadEnabled = true
        settings.isDownloadEnabled = true
        settings.useLocalGlucoseSource = true
        settings.localGlucosePort = 9090
        settings.debugOptions = true
        settings.cgm = .nightscout
        settings.cgmPluginIdentifier = "some-plugin"
        settings.uploadGlucose = false
        settings.useCalendar = true
        settings.displayCalendarIOBandCOB = true
        settings.displayCalendarEmojis = true
        settings.glucoseBadge = true
        settings.carbsRequiredThreshold = 20
        settings.showCarbsRequiredBadge = false
        settings.useFPUconversion = true
        settings.individualAdjustmentFactor = 0.6
        settings.minuteInterval = 45
        settings.delay = 90
        settings.useAppleHealth = true
        settings.smoothGlucose = true
        settings.eA1cDisplayUnit = .mmolMol
        settings.high = 200
        settings.low = 80
        settings.glucoseColorScheme = .staticColor
        settings.xGridLines = false
        settings.yGridLines = false
        settings.hideInsulinBadge = true
        settings.allowDilution = true
        settings.insulinConcentration = 2
        settings.showCobIobChart = false
        settings.rulerMarks = false
        settings.bolusDisplayThreshold = .oneUnit
        settings.forecastDisplayType = .lines
        settings.maxCarbs = 200
        settings.maxFat = 150
        settings.maxProtein = 100
        settings.confirmBolusFaster = true
        settings.overrideFactor = 0.7
        settings.fattyMeals = true
        settings.fattyMealFactor = 0.5
        settings.sweetMeals = true
        settings.sweetMealFactor = 1.5
        settings.displayPresets = false
        settings.confirmBolus = true
        settings.enableQuickBolus = true
        settings.useLiveActivity = true
        settings.lockScreenView = .detailed
        settings.smartStackView = .detailed
        settings.displayGlucoseForecasts = true
        settings.bolusShortcut = .limitWithSafetyChecks
        settings.timeInRangeType = .timeInNormoglycemia
        settings.requireAdjustmentsConfirmation = true
        settings.garminWatchface = .swissalpine
        settings.garminDatafield = .trio
        settings.primaryAttributeChoice = .isf
        settings.secondaryAttributeChoice = .eventualBG
        settings.isWatchfaceDataEnabled = true
        settings.showForecastWatch = true
        settings.homeStatsPanelFace = .distributionBar
        return settings
    }

    static func maximallyDifferentPreferences() -> Preferences {
        var preferences = Preferences()
        preferences.maxIOB = 5
        preferences.maxDailySafetyMultiplier = 2
        preferences.currentBasalSafetyMultiplier = 3
        preferences.autosensMax = 1.5
        preferences.autosensMin = 0.8
        preferences.smbDeliveryRatio = 0.6
        preferences.rewindResetsAutosens = false
        preferences.highTemptargetRaisesSensitivity = true
        preferences.lowTemptargetLowersSensitivity = true
        preferences.sensitivityRaisesTarget = true
        preferences.resistanceLowersTarget = true
        preferences.advTargetAdjustments = true
        preferences.exerciseMode = true
        preferences.halfBasalExerciseTarget = 180
        preferences.maxCOB = 200
        preferences.maxMealAbsorptionTime = 8
        preferences.wideBGTargetRange = true
        preferences.skipNeutralTemps = true
        preferences.unsuspendIfNoTemp = true
        preferences.min5mCarbimpact = 10
        preferences.remainingCarbsFraction = 0.8
        preferences.remainingCarbsCap = 100
        preferences.enableUAM = true
        preferences.a52RiskEnable = true
        preferences.enableSMBWithCOB = true
        preferences.enableSMBWithTemptarget = true
        preferences.enableSMBAlways = true
        preferences.enableSMBAfterCarbs = true
        preferences.allowSMBWithHighTemptarget = true
        preferences.maxSMBBasalMinutes = 60
        preferences.maxUAMSMBBasalMinutes = 90
        preferences.smbInterval = 5
        preferences.bolusIncrement = 0.05
        preferences.curve = .ultraRapid
        preferences.useCustomPeakTime = true
        preferences.insulinPeakTime = 60
        preferences.carbsReqThreshold = 2
        preferences.noisyCGMTargetMultiplier = 1.5
        preferences.suspendZerosIOB = false
        preferences.timestamp = Date(timeIntervalSince1970: 1_000_000)
        preferences.maxDeltaBGthreshold = 0.3
        preferences.adjustmentFactor = 1.0
        preferences.adjustmentFactorSigmoid = 0.7
        preferences.sigmoid = true
        preferences.useNewFormula = true
        preferences.useWeightedAverage = true
        preferences.weightPercentage = 0.5
        preferences.tddAdjBasal = true
        preferences.enableSMB_high_bg = true
        preferences.enableSMB_high_bg_target = 150
        preferences.threshold_setting = 80
        preferences.updateInterval = 30
        return preferences
    }

    static func fullBackup() -> SettingsBackup {
        var backup = SettingsBackup()
        backup.exportDate = Date(timeIntervalSince1970: 1_750_000_000)
        backup.appVersion = "0.8.4"
        backup.buildNumber = "123"
        backup.branch = "dev abc1234"

        backup.devices = SettingsBackup.DeviceInfo(
            pumpType: "Omnipod DASH",
            insulinType: "Novolog",
            cgmDisplayName: "Nightscout as CGM",
            pumpState: nil,
            cgmState: nil
        )
        backup.trioSettings = maximallyDifferentTrioSettings()
        backup.preferences = maximallyDifferentPreferences()
        backup.pumpSettings = PumpSettings(insulinActionCurve: 9, maxBolus: 8, maxBasal: 3.5)
        backup.therapy = SettingsBackup.Therapy(
            basalProfile: [
                BasalProfileEntry(start: "00:00:00", minutes: 0, rate: 0.8),
                BasalProfileEntry(start: "06:00:00", minutes: 360, rate: 1.2)
            ],
            insulinSensitivities: InsulinSensitivities(
                units: .mgdL,
                userPreferredUnits: .mgdL,
                sensitivities: [
                    InsulinSensitivityEntry(sensitivity: 45, offset: 0, start: "00:00:00"),
                    InsulinSensitivityEntry(sensitivity: 55, offset: 720, start: "12:00:00")
                ]
            ),
            carbRatios: CarbRatios(
                units: .grams,
                schedule: [
                    CarbRatioEntry(start: "00:00:00", offset: 0, ratio: 10),
                    CarbRatioEntry(start: "18:00:00", offset: 1080, ratio: 8)
                ]
            ),
            bgTargets: BGTargets(
                units: .mgdL,
                userPreferredUnits: .mgdL,
                targets: [BGTargetEntry(low: 100, high: 100, start: "00:00:00", offset: 0)]
            )
        )
        backup.presets = SettingsBackup.Presets(
            tempTargets: [
                SettingsBackup.TempTargetPreset(name: "Sport", target: 140, duration: 60, halfBasalTarget: 160, orderPosition: 1)
            ],
            overrides: [
                SettingsBackup.OverridePreset(
                    name: "Lazy Sunday",
                    percentage: 80,
                    indefinite: false,
                    duration: 120,
                    target: 120,
                    advancedSettings: true,
                    smbIsOff: false,
                    smbIsScheduledOff: true,
                    start: 8,
                    end: 20,
                    isfAndCr: true,
                    isf: true,
                    cr: true,
                    smbMinutes: 45,
                    uamMinutes: 45,
                    orderPosition: 1
                )
            ],
            meals: [SettingsBackup.MealPreset(dish: "Pizza", carbs: 80, fat: 30, protein: 25)]
        )
        backup.userDefaults = SettingsBackup.UserDefaultsValues(
            colorSchemePreference: "dark",
            isTrioRemoteControlEnabled: true
        )
        backup.profilePresets = [profilePreset(name: "Weekend", basalRate: 0.9)]
        backup.activeProfilePresetName = "Weekend"
        backup.history = history(around: backup.exportDate!)
        backup.credentials = SettingsBackup.Credentials(
            nightscoutURL: "https://example.nightscout.test",
            nightscoutSecret: "supersecret",
            remoteControlSharedSecret: "sharedsecret"
        )
        return backup
    }

    /// Entries per history category, dated relative to `date` — including one glucose reading
    /// days in the past, since the backup carries the full history the device still holds.
    static func history(around date: Date) -> SettingsBackup.History {
        let glucoseDate = date.addingTimeInterval(-10 * 60)
        let oldGlucoseDate = date.addingTimeInterval(-3 * 24 * 60 * 60)
        let bolusDate = date.addingTimeInterval(-30 * 60)
        let tempBasalDate = date.addingTimeInterval(-60 * 60)
        let carbsDate = date.addingTimeInterval(-45 * 60)

        return SettingsBackup.History(
            glucose: [
                BloodGlucose(
                    id: "11111111-1111-1111-1111-111111111111",
                    sgv: 120,
                    direction: .flat,
                    date: Decimal(Int64(glucoseDate.timeIntervalSince1970 * 1000)),
                    dateString: glucoseDate,
                    glucose: nil,
                    type: "sgv"
                ),
                BloodGlucose(
                    id: "33333333-3333-3333-3333-333333333333",
                    sgv: 145,
                    direction: .fortyFiveUp,
                    date: Decimal(Int64(oldGlucoseDate.timeIntervalSince1970 * 1000)),
                    dateString: oldGlucoseDate,
                    glucose: nil,
                    type: "sgv"
                )
            ],
            pumpHistory: [
                PumpHistoryEvent(
                    id: "bolus-1",
                    type: .bolus,
                    timestamp: bolusDate,
                    amount: 1.5,
                    duration: 0,
                    isSMB: true,
                    isExternal: false
                ),
                PumpHistoryEvent(
                    id: "temp-1",
                    type: .tempBasalDuration,
                    timestamp: tempBasalDate,
                    durationMin: 30
                ),
                PumpHistoryEvent(
                    id: "_temp-1",
                    type: .tempBasal,
                    timestamp: tempBasalDate,
                    rate: 0.85,
                    temp: .absolute
                )
            ],
            carbs: [
                CarbsEntry(
                    id: "22222222-2222-2222-2222-222222222222",
                    createdAt: carbsDate,
                    actualDate: carbsDate,
                    carbs: 45,
                    fat: 10,
                    protein: 5,
                    note: "Lunch",
                    enteredBy: CarbsEntry.local,
                    isFPU: false,
                    fpuID: nil
                )
            ],
            tdd: [
                SettingsBackup.TDDEntry(
                    date: date.addingTimeInterval(-2 * 60 * 60),
                    total: 38.5,
                    bolus: 20,
                    tempBasal: 10,
                    scheduledBasal: 8.5,
                    weightedAverage: 37.2
                ),
                SettingsBackup.TDDEntry(
                    date: date.addingTimeInterval(-26 * 60 * 60),
                    total: 41,
                    bolus: 22,
                    tempBasal: 11,
                    scheduledBasal: 8,
                    weightedAverage: nil
                )
            ],
            tddDaily: [
                TDDArchiveStore.dayKey(for: date.addingTimeInterval(-5 * 24 * 60 * 60)): 39.5,
                TDDArchiveStore.dayKey(for: date.addingTimeInterval(-10 * 24 * 60 * 60)): 42.0
            ]
        )
    }

    static func profilePreset(name: String, basalRate: Decimal = 0.8) -> ProfilePreset {
        ProfilePreset(
            name: name,
            basalProfile: [BasalProfileEntry(start: "00:00:00", minutes: 0, rate: basalRate)],
            insulinSensitivities: InsulinSensitivities(
                units: .mgdL,
                userPreferredUnits: .mgdL,
                sensitivities: [InsulinSensitivityEntry(sensitivity: 50, offset: 0, start: "00:00:00")]
            ),
            carbRatios: CarbRatios(units: .grams, schedule: [CarbRatioEntry(start: "00:00:00", offset: 0, ratio: 10)]),
            bgTargets: BGTargets(
                units: .mgdL,
                userPreferredUnits: .mgdL,
                targets: [BGTargetEntry(low: 100, high: 100, start: "00:00:00", offset: 0)]
            )
        )
    }

    /// Counts stored properties whose values differ between two instances of the same type.
    static func differingFieldLabels<T>(_ a: T, _ b: T) -> [String] {
        let childrenA = Array(Mirror(reflecting: a).children)
        let childrenB = Array(Mirror(reflecting: b).children)
        return zip(childrenA, childrenB).compactMap { childA, childB in
            "\(childA.value)" != "\(childB.value)" ? (childA.label ?? "?") : nil
        }
    }

    static func storedPropertyCount<T>(_ value: T) -> Int {
        Mirror(reflecting: value).children.count
    }
}
