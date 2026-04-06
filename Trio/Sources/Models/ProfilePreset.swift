import Foundation

struct ProfilePreset: JSON, Identifiable, Equatable {
    let id: String
    var name: String
    var basalProfile: [BasalProfileEntry]
    var insulinSensitivities: InsulinSensitivities
    var carbRatios: CarbRatios
    var bgTargets: BGTargets

    init(
        id: String = UUID().uuidString,
        name: String,
        basalProfile: [BasalProfileEntry],
        insulinSensitivities: InsulinSensitivities,
        carbRatios: CarbRatios,
        bgTargets: BGTargets
    ) {
        self.id = id
        self.name = name
        self.basalProfile = basalProfile
        self.insulinSensitivities = insulinSensitivities
        self.carbRatios = carbRatios
        self.bgTargets = bgTargets
    }

    static func == (lhs: ProfilePreset, rhs: ProfilePreset) -> Bool {
        lhs.id == rhs.id
    }
}

extension ProfilePreset {
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case basalProfile = "basal_profile"
        case insulinSensitivities = "insulin_sensitivities"
        case carbRatios = "carb_ratios"
        case bgTargets = "bg_targets"
    }

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
