import Foundation

/// Categories a settings backup can be applied by. Mirrors the sections of the CSV export,
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
    case profilePresets
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
        case .profilePresets:
            return String(localized: "Profile Presets")
        case .history:
            return String(localized: "History")
        }
    }
}

/// Machine-readable, schema-versioned backup of Trio's restorable configuration.
///
/// All values are stored raw, exactly as persisted on disk: glucose in mg/dL, multipliers as
/// fractions (not percentages). Every section is optional so partial or future backups still
/// decode; only `schemaVersion` is decoded strictly — its absence means the file is not a Trio
/// backup at all.
struct SettingsBackup: JSON, Equatable, Encodable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int = SettingsBackup.currentSchemaVersion
    var exportDate: Date?
    var appVersion: String?
    var buildNumber: String?
    var branch: String?

    var devices: DeviceInfo?
    var trioSettings: TrioSettings?
    var preferences: Preferences?
    var pumpSettings: PumpSettings?
    var therapy: Therapy?
    var presets: Presets?
    var userDefaults: UserDefaultsValues?
    var credentials: Credentials?

    /// Full profile presets (therapy schedules plus optional SMB/dynamic settings each). The
    /// ACTIVE profile is exported by name for display only — an import never switches profiles.
    var profilePresets: [ProfilePreset]?
    var activeProfilePresetName: String?

    /// Optional treatment history (export toggle, off by default): the last 24 hours of glucose,
    /// pump events and carbs, plus 10 days of hourly TDD samples for Dynamic ISF continuity.
    /// Import deduplicates by date, and the 24-hour categories only land when the backup is
    /// fresh enough.
    var history: History?

    struct History: JSON, Equatable {
        var glucose: [BloodGlucose]?
        var pumpHistory: [PumpHistoryEvent]?
        var carbs: [CarbsEntry]?
        var tdd: [TDDEntry]?
    }

    struct TDDEntry: JSON, Equatable {
        var date: Date
        var total: Decimal
        var bolus: Decimal
        var tempBasal: Decimal
        var scheduledBasal: Decimal
        var weightedAverage: Decimal?
    }

    /// Device metadata. `pumpType`/`insulinType`/`cgmDisplayName` are informational only —
    /// the authoritative CGM selection lives in `trioSettings.cgm`/`.cgmPluginIdentifier`.
    /// `pumpState`/`cgmState` are the raw manager state plists (base64-encoded) and are only
    /// present when the user explicitly opted in to exporting device pairing data.
    struct DeviceInfo: JSON, Equatable {
        var pumpType: String?
        var insulinType: String?
        var cgmDisplayName: String?
        var pumpState: String?
        var cgmState: String?
    }

    struct Therapy: JSON, Equatable {
        var basalProfile: [BasalProfileEntry]?
        var insulinSensitivities: InsulinSensitivities?
        var carbRatios: CarbRatios?
        var bgTargets: BGTargets?
    }

    struct Presets: JSON, Equatable {
        var tempTargets: [TempTargetPreset]?
        var overrides: [OverridePreset]?
        var meals: [MealPreset]?
    }

    /// Runtime attributes (`id`, `date`, `enabled`, `isUploadedToNS`) are intentionally not part
    /// of the backup — they are regenerated on import, with `isPreset = true` and `enabled = false`.
    struct TempTargetPreset: JSON, Equatable {
        var name: String
        var target: Decimal
        var duration: Decimal
        var halfBasalTarget: Decimal?
        var orderPosition: Int?
    }

    struct OverridePreset: JSON, Equatable {
        var name: String
        var percentage: Double
        var indefinite: Bool
        var duration: Decimal
        var target: Decimal?
        var advancedSettings: Bool
        var smbIsOff: Bool
        var smbIsScheduledOff: Bool
        var start: Decimal?
        var end: Decimal?
        var isfAndCr: Bool
        var isf: Bool
        var cr: Bool
        var smbMinutes: Decimal?
        var uamMinutes: Decimal?
        var orderPosition: Int?
    }

    struct MealPreset: JSON, Equatable {
        var dish: String
        var carbs: Decimal
        var fat: Decimal
        var protein: Decimal
    }

    struct UserDefaultsValues: JSON, Equatable {
        var colorSchemePreference: String?
        var isTrioRemoteControlEnabled: Bool?
    }

    /// Only present when the user explicitly opted in to exporting credentials.
    struct Credentials: JSON, Equatable {
        var nightscoutURL: String?
        var nightscoutSecret: String?
        var remoteControlSharedSecret: String?
    }
}

extension SettingsBackup {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case exportDate
        case appVersion
        case buildNumber
        case branch
        case devices
        case trioSettings
        case preferences
        case pumpSettings
        case therapy
        case presets
        case userDefaults
        case credentials
        case profilePresets
        case activeProfilePresetName
        case history
    }
}

extension SettingsBackup: Decodable {
    /// `schemaVersion` is decoded strictly — a file without it is not a Trio backup. Every other
    /// field decodes leniently so partial backups and files from newer Trio versions still load.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        var backup = SettingsBackup()
        backup.schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)

        backup.exportDate = try? container.decode(Date.self, forKey: .exportDate)
        backup.appVersion = try? container.decode(String.self, forKey: .appVersion)
        backup.buildNumber = try? container.decode(String.self, forKey: .buildNumber)
        backup.branch = try? container.decode(String.self, forKey: .branch)

        backup.devices = try? container.decode(DeviceInfo.self, forKey: .devices)
        backup.trioSettings = try? container.decode(TrioSettings.self, forKey: .trioSettings)
        backup.preferences = try? container.decode(Preferences.self, forKey: .preferences)
        backup.pumpSettings = try? container.decode(PumpSettings.self, forKey: .pumpSettings)
        backup.therapy = try? container.decode(Therapy.self, forKey: .therapy)
        backup.presets = try? container.decode(Presets.self, forKey: .presets)
        backup.userDefaults = try? container.decode(UserDefaultsValues.self, forKey: .userDefaults)
        backup.credentials = try? container.decode(Credentials.self, forKey: .credentials)
        backup.profilePresets = try? container.decode([ProfilePreset].self, forKey: .profilePresets)
        backup.activeProfilePresetName = try? container.decode(String.self, forKey: .activeProfilePresetName)
        backup.history = try? container.decode(History.self, forKey: .history)

        self = backup
    }
}

extension SettingsBackup {
    /// Raw pump/CGM manager state dictionaries are property-list values; JSON carries them as
    /// base64-encoded binary plists.
    static func encodeManagerState(_ rawValue: [String: Any]) -> String? {
        guard let data = try? PropertyListSerialization.data(fromPropertyList: rawValue, format: .binary, options: 0) else {
            return nil
        }
        return data.base64EncodedString()
    }

    static func decodeManagerState(_ base64: String) -> [String: Any]? {
        guard let data = Data(base64Encoded: base64),
              let rawValue = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else {
            return nil
        }
        return rawValue
    }
}

// Swift cannot synthesize Equatable in extensions outside the declaring file, so == is spelled
// out for the container types the backup embeds. The schedule entry types already conform in
// their declaring files.
extension InsulinSensitivities: Equatable {
    static func == (lhs: InsulinSensitivities, rhs: InsulinSensitivities) -> Bool {
        lhs.units == rhs.units && lhs.userPreferredUnits == rhs.userPreferredUnits &&
            lhs.sensitivities == rhs.sensitivities
    }
}

extension CarbRatios: Equatable {
    static func == (lhs: CarbRatios, rhs: CarbRatios) -> Bool {
        lhs.units == rhs.units && lhs.schedule == rhs.schedule
    }
}

extension BGTargets: Equatable {
    static func == (lhs: BGTargets, rhs: BGTargets) -> Bool {
        lhs.units == rhs.units && lhs.userPreferredUnits == rhs.userPreferredUnits && lhs.targets == rhs.targets
    }
}

extension PumpSettings: Equatable {
    static func == (lhs: PumpSettings, rhs: PumpSettings) -> Bool {
        lhs.insulinActionCurve == rhs.insulinActionCurve && lhs.maxBolus == rhs.maxBolus && lhs.maxBasal == rhs.maxBasal
    }
}
