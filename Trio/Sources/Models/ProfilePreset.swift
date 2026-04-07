import Foundation

struct ProfilePreset: JSON, Identifiable, Equatable, Hashable {
    let id: String
    var name: String
    var icon: String
    var basalProfile: [BasalProfileEntry]
    var insulinSensitivities: InsulinSensitivities
    var carbRatios: CarbRatios
    var bgTargets: BGTargets
    var smbSettings: SMBPresetSettings?
    var dynamicSettings: DynamicPresetSettings?

    /// The default SF Symbol used for new presets.
    static let defaultIcon = "person.crop.circle"

    /// SF Symbol names suitable for profile preset icons
    static let availableIcons: [String] = [
        "person.crop.circle",
        "figure.run",
        "figure.walk",
        "bed.double.fill",
        "briefcase.fill",
        "heart.fill",
        "cross.case.fill",
        "fork.knife",
        "cup.and.saucer.fill",
        "moon.fill",
        "sun.max.fill",
        "cloud.rain.fill",
        "snowflake",
        "flame.fill",
        "bolt.fill",
        "leaf.fill",
        "bicycle",
        "sportscourt.fill",
        "graduationcap.fill",
        "airplane",
        "car.fill",
        "house.fill",
        "building.2.fill",
        "star.fill",
        "flag.fill"
    ]

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case icon
        case basalProfile = "basal_profile"
        case insulinSensitivities = "insulin_sensitivities"
        case carbRatios = "carb_ratios"
        case bgTargets = "bg_targets"
        case smbSettings = "smb_settings"
        case dynamicSettings = "dynamic_settings"
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        icon: String = ProfilePreset.defaultIcon,
        basalProfile: [BasalProfileEntry],
        insulinSensitivities: InsulinSensitivities,
        carbRatios: CarbRatios,
        bgTargets: BGTargets,
        smbSettings: SMBPresetSettings? = nil,
        dynamicSettings: DynamicPresetSettings? = nil
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.basalProfile = basalProfile
        self.insulinSensitivities = insulinSensitivities
        self.carbRatios = carbRatios
        self.bgTargets = bgTargets
        self.smbSettings = smbSettings
        self.dynamicSettings = dynamicSettings
    }

    static func == (lhs: ProfilePreset, rhs: ProfilePreset) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        icon = try container.decodeIfPresent(String.self, forKey: .icon) ?? ProfilePreset.defaultIcon
        basalProfile = try container.decode([BasalProfileEntry].self, forKey: .basalProfile)
        insulinSensitivities = try container.decode(InsulinSensitivities.self, forKey: .insulinSensitivities)
        carbRatios = try container.decode(CarbRatios.self, forKey: .carbRatios)
        bgTargets = try container.decode(BGTargets.self, forKey: .bgTargets)
        smbSettings = try container.decodeIfPresent(SMBPresetSettings.self, forKey: .smbSettings)
        dynamicSettings = try container.decodeIfPresent(DynamicPresetSettings.self, forKey: .dynamicSettings)
    }
}

// MARK: - SMB Preset Settings

struct SMBPresetSettings: JSON, Equatable {
    var enableSMBAlways: Bool
    var enableSMBWithCOB: Bool
    var enableSMBWithTemptarget: Bool
    var enableSMBAfterCarbs: Bool
    var allowSMBWithHighTemptarget: Bool
    var enableSMBHighBG: Bool
    var enableSMBHighBGTarget: Decimal
    var maxSMBBasalMinutes: Decimal
    var maxUAMSMBBasalMinutes: Decimal
    var enableUAM: Bool
    var maxDeltaBGthreshold: Decimal

    private enum CodingKeys: String, CodingKey {
        case enableSMBAlways = "enable_smb_always"
        case enableSMBWithCOB = "enable_smb_with_cob"
        case enableSMBWithTemptarget = "enable_smb_with_temptarget"
        case enableSMBAfterCarbs = "enable_smb_after_carbs"
        case allowSMBWithHighTemptarget = "allow_smb_with_high_temptarget"
        case enableSMBHighBG = "enable_smb_high_bg"
        case enableSMBHighBGTarget = "enable_smb_high_bg_target"
        case maxSMBBasalMinutes = "max_smb_basal_minutes"
        case maxUAMSMBBasalMinutes = "max_uam_smb_basal_minutes"
        case enableUAM = "enable_uam"
        case maxDeltaBGthreshold = "max_delta_bg_threshold"
    }
}

// MARK: - Dynamic ISF Preset Settings

struct DynamicPresetSettings: JSON, Equatable {
    var useNewFormula: Bool
    var sigmoid: Bool
    var adjustmentFactor: Decimal
    var adjustmentFactorSigmoid: Decimal
    var weightPercentage: Decimal
    var tddAdjBasal: Bool

    private enum CodingKeys: String, CodingKey {
        case useNewFormula = "use_new_formula"
        case sigmoid
        case adjustmentFactor = "adjustment_factor"
        case adjustmentFactorSigmoid = "adjustment_factor_sigmoid"
        case weightPercentage = "weight_percentage"
        case tddAdjBasal = "tdd_adj_basal"
    }
}

// MARK: - Computed Properties

extension ProfilePreset {
    var totalDailyBasal: Decimal {
        basalProfile.enumerated().reduce(Decimal.zero) { result, entry in
            let current = entry.element
            let nextMinutes: Int
            if entry.offset + 1 < basalProfile.count {
                nextMinutes = basalProfile[entry.offset + 1].minutes
            } else {
                nextMinutes = 24 * 60
            }
            let durationHours = Decimal(nextMinutes - current.minutes) / 60
            return result + current.rate * durationHours
        }
    }
}

// MARK: - Percentage Scaling

extension ProfilePreset {
    /// Creates a new profile preset with therapy values scaled by the given percentage.
    ///
    /// A percentage of 110 means 10% stronger (more insulin):
    /// - Basal rates are multiplied by (percentage / 100)
    /// - ISF values are divided by (percentage / 100) — lower ISF = more aggressive
    /// - CR values are divided by (percentage / 100) — lower CR = more aggressive
    /// - BG targets, SMB settings, and dynamic settings remain unchanged
    func scaled(by percentage: Int, name: String) -> ProfilePreset? {
        guard percentage > 0 else { return nil }
        let factor = Decimal(percentage) / 100

        let scaledBasal = basalProfile.map { entry in
            BasalProfileEntry(
                start: entry.start,
                minutes: entry.minutes,
                rate: roundToTwoDecimals(entry.rate * factor)
            )
        }

        let scaledSensitivities = insulinSensitivities.sensitivities.map { entry in
            InsulinSensitivityEntry(
                sensitivity: roundToOneDecimal(entry.sensitivity / factor),
                offset: entry.offset,
                start: entry.start
            )
        }
        let scaledISF = InsulinSensitivities(
            units: insulinSensitivities.units,
            userPreferredUnits: insulinSensitivities.userPreferredUnits,
            sensitivities: scaledSensitivities
        )

        let scaledSchedule = carbRatios.schedule.map { entry in
            CarbRatioEntry(
                start: entry.start,
                offset: entry.offset,
                ratio: roundToOneDecimal(entry.ratio / factor)
            )
        }
        let scaledCR = CarbRatios(units: carbRatios.units, schedule: scaledSchedule)

        return ProfilePreset(
            name: name,
            icon: icon,
            basalProfile: scaledBasal,
            insulinSensitivities: scaledISF,
            carbRatios: scaledCR,
            bgTargets: bgTargets,
            smbSettings: smbSettings,
            dynamicSettings: dynamicSettings
        )
    }

    private func roundToTwoDecimals(_ value: Decimal) -> Decimal {
        var result = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &result, 2, .plain)
        return rounded
    }

    private func roundToOneDecimal(_ value: Decimal) -> Decimal {
        var result = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &result, 1, .plain)
        return rounded
    }
}
