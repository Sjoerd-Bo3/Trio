import CoreData
import CryptoKit
import Foundation
import Testing
@testable import Trio

@Suite("Settings Backup Snapshot", .serialized) struct BackupSnapshotTests {
    let resources = BackupTestResources()

    func validConfiguration(preferences: Preferences = Preferences()) -> TrioSettingsBackup.Configuration {
        TrioSettingsBackup.Configuration(
            settings: TrioSettings(),
            preferences: preferences,
            pumpSettings: PumpSettings(insulinActionCurve: 10, maxBolus: 10, maxBasal: 2),
            basalProfile: [BasalProfileEntry(start: "00:00:00", minutes: 0, rate: 1)],
            carbRatios: CarbRatios(
                units: .grams,
                schedule: [CarbRatioEntry(start: "00:00:00", offset: 0, ratio: 10)]
            ),
            insulinSensitivities: InsulinSensitivities(
                units: .mgdL, userPreferredUnits: .mgdL,
                sensitivities: [InsulinSensitivityEntry(sensitivity: 40, offset: 0, start: "00:00:00")]
            ),
            glucoseTargets: BGTargets(
                units: .mgdL, userPreferredUnits: .mgdL,
                targets: [BGTargetEntry(low: 100, high: 100, start: "00:00:00", offset: 0)]
            ),
            presets: .init(
                overrides: [],
                tempTargets: [],
                meals: [.init(dish: "Lunch", carbs: 55, fat: 8, protein: 20)]
            )
        )
    }

    func makeBackup(
        _ configuration: TrioSettingsBackup.Configuration,
        origin: TrioSettingsBackup.Origin = .manual,
        name: String? = "Baseline",
        createdAt: Date = Date(),
        schemaVersion: Int = TrioSettingsBackup.currentSchema,
        fingerprint: String? = nil
    ) throws -> TrioSettingsBackup {
        TrioSettingsBackup(
            schemaVersion: schemaVersion,
            id: UUID(),
            createdAt: createdAt,
            appVersion: "test",
            origin: origin,
            name: name,
            configuration: configuration,
            fingerprint: try fingerprint ?? TrioSettingsBackup.fingerprint(for: configuration)
        )
    }

    @Test("Configuration round trips through JSON with intact presets") func jsonRoundTrip() throws {
        let backup = try makeBackup(validConfiguration())
        let bytes = try JSONEncoder().encode(backup)
        let decoded = try JSONDecoder().decode(TrioSettingsBackup.self, from: bytes).validated()
        #expect(decoded.fingerprint == backup.fingerprint)
        #expect(decoded.configuration.presets.meals.first?.dish == "Lunch")
        #expect(decoded.name == "Baseline")
    }

    @Test("New backups omit dosing mode and preserve strict validation of the remaining settings")
    func portableDosingMode() throws {
        var closed = validConfiguration()
        closed.settings.dosingMode = .closed
        var open = closed
        open.settings.dosingMode = .open
        #expect(try TrioSettingsBackup.fingerprint(for: closed) == TrioSettingsBackup.fingerprint(for: open))
        let bytes = try JSONEncoder().encode(makeBackup(closed))
        let text = String(decoding: bytes, as: UTF8.self)
        #expect(!text.contains("dosingMode"))
        let decoded = try TrioSettingsBackup.decode(bytes)
        #expect(decoded.configuration.settings.dosingMode == .open)
        #expect(decoded.configuration.settings.units == closed.settings.units)
        var object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        var configuration = try #require(object["configuration"] as? [String: Any])
        var settings = try #require(configuration["settings"] as? [String: Any])
        settings.removeValue(forKey: "units")
        configuration["settings"] = settings
        object["configuration"] = configuration
        #expect(throws: BackupError.self) { _ = try TrioSettingsBackup.decode(JSONSerialization.data(withJSONObject: object)) }
        settings["units"] = "mg/dL"
        settings["dosingMode"] = "closed"
        configuration["settings"] = settings
        object["configuration"] = configuration
        #expect(throws: BackupError.self) { _ = try TrioSettingsBackup.decode(JSONSerialization.data(withJSONObject: object)) }
    }

    @Test("Schema 3 and 4 backups migrate to Open Loop while retaining identity and history", arguments: [3, 4])
    func migrateLegacyDosingMode(_ schema: Int) throws {
        var configuration = validConfiguration()
        configuration.settings.dosingMode = .closed
        let oldConfiguration = try TrioSettingsBackup.normalized(configuration, preserveDosingMode: true)
        let oldChecksum = try TrioSettingsBackup.normalizedFingerprint(oldConfiguration, legacySettings: true)
        var original = try makeBackup(oldConfiguration, schemaVersion: schema, fingerprint: oldChecksum)
        if schema == 4 {
            original.dynamicISFHistory = [tdd(original.createdAt.addingTimeInterval(-300))]
            original.historyChecksum = try TrioSettingsBackup.historyDigest(original.dynamicISFHistory ?? [])
        }
        let bytes = try JSONEncoder().encode(original)
        #expect(String(decoding: bytes, as: UTF8.self).contains("dosingMode"))
        let restored = try TrioSettingsBackup.decode(bytes, expectedFingerprint: oldChecksum)
        #expect(restored.schemaVersion == TrioSettingsBackup.currentSchema)
        #expect(restored.id == original.id)
        #expect(restored.createdAt == original.createdAt)
        #expect(restored.name == original.name)
        #expect(restored.configuration.settings.dosingMode == .open)
        #expect(restored.dynamicISFHistory == original.dynamicISFHistory)
        #expect(restored.historyChecksum == original.historyChecksum)
        #expect(!String(decoding: try JSONEncoder().encode(restored), as: UTF8.self).contains("dosingMode"))
        #expect(try original.matchesUploadedSnapshot(restored))
        #expect(try TrioSettingsBackup.matchesLegacyFingerprint(oldChecksum, configuration: restored.configuration))
        var changed = restored.configuration
        changed.preferences.maxIOB += 1
        #expect(try !TrioSettingsBackup.matchesLegacyFingerprint(oldChecksum, configuration: changed))
    }

    @Test("Any meaningful preference change alters fingerprint") func fingerprintsChange() throws {
        let baseline = try TrioSettingsBackup.fingerprint(for: validConfiguration())
        var preferences = Preferences()
        preferences.maxIOB = 5
        let changed = try TrioSettingsBackup.fingerprint(for: validConfiguration(preferences: preferences))
        #expect(baseline != changed)
    }

    @Test("A tampered snapshot fails integrity checking") func detectsTampering() throws {
        let altered = try makeBackup(validConfiguration(), fingerprint: "000000")
        #expect(throws: BackupError.self) {
            _ = try altered.validated()
        }
    }

    @Test("Upload retry identity ignores a manual rename but validates history") func uploadRetryIdentity() throws {
        let now = Date()
        let backup = try historyBackup([tdd(now.addingTimeInterval(-300))], createdAt: now)
        var renamed = backup
        renamed.name = "Renamed"
        #expect(try backup.matchesUploadedSnapshot(renamed))
        var altered = backup
        altered.dynamicISFHistory = []
        altered.historyChecksum = try TrioSettingsBackup.historyDigest([])
        #expect(try !backup.matchesUploadedSnapshot(altered))
    }

    func directory() throws -> URL { try resources.directory() }

    func journalExists(in directory: URL) -> Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent(SettingsBackupRestore.journalFileName).path)
    }

    func isolatedDefaults() -> UserDefaults { resources.defaults() }

    @Test("Fingerprint ignores transient timestamp and device-derived bolus increment") func transientPreferences() throws {
        var preferences = Preferences()
        preferences.timestamp = Date()
        preferences.bolusIncrement = 0.05
        #expect(
            try TrioSettingsBackup.fingerprint(for: validConfiguration()) ==
                TrioSettingsBackup.fingerprint(for: validConfiguration(preferences: preferences))
        )
    }

    @Test("Preset fetch ordering is canonical; contents and deletion change hashes") func stablePresetOrdering() throws {
        let original = validConfiguration()
        let meals: [TrioSettingsBackup.MealPreset] = [
            .init(dish: "Lunch", carbs: 55, fat: 8, protein: 20),
            .init(dish: "Lunch", carbs: 25, fat: 0, protein: 0)
        ]
        func configuration(_ meals: [TrioSettingsBackup.MealPreset]) -> TrioSettingsBackup.Configuration {
            var configuration = original
            configuration.presets = .init(overrides: [], tempTargets: [], meals: meals)
            return configuration
        }
        let hash = try TrioSettingsBackup.fingerprint(for: configuration(meals))
        #expect(try hash == TrioSettingsBackup.fingerprint(for: configuration(meals.reversed())))
        #expect(try hash != TrioSettingsBackup.fingerprint(for: configuration([meals[0]])))
        #expect(try hash != TrioSettingsBackup.fingerprint(for: configuration([
            .init(dish: "Lunch", carbs: 56, fat: 8, protein: 20), meals[1]
        ])))
    }

    @Test("Both supported schedule time formats validate and share an effective fingerprint") func supportedTimeFormats() throws {
        let original = validConfiguration()
        var short = original
        short.basalProfile = [.init(start: "00:00", minutes: 0, rate: 1)]
        short.carbRatios = .init(units: .grams, schedule: [.init(start: "00:00", offset: 0, ratio: 10)])
        short.insulinSensitivities = .init(
            units: .mgdL, userPreferredUnits: .mgdL,
            sensitivities: [.init(sensitivity: 40, offset: 0, start: "00:00")]
        )
        short.glucoseTargets = .init(
            units: .mgdL, userPreferredUnits: .mgdL,
            targets: [.init(low: 100, high: 100, start: "00:00", offset: 0)]
        )
        _ = try makeBackup(short).validated()
        #expect(try TrioSettingsBackup.fingerprint(for: short) == TrioSettingsBackup.fingerprint(for: original))
        #expect(try SettingsBackupRestore.onboardingConfiguration(short).basalProfile.first?.start == "00:00:00")
    }

    @Test("Zero override target preserves Trio's no-target sentinel semantics") func noTargetOverride() throws {
        let source = validConfiguration()
        var preset = TrioSettingsBackup.OverridePreset(
            name: "Basal only",
            order: 1,
            percentage: 90,
            duration: 60,
            indefinite: false,
            target: 0,
            isf: false,
            cr: false,
            isfAndCr: false,
            advancedSettings: false,
            smbIsScheduledOff: false,
            smbIsOff: false,
            smbMinutes: 30,
            uamMinutes: 30,
            start: 0,
            end: 0
        )
        func configuration(_ preset: TrioSettingsBackup.OverridePreset) -> TrioSettingsBackup.Configuration {
            var configuration = source
            configuration.presets = .init(overrides: [preset], tempTargets: [], meals: [])
            return configuration
        }
        let zero = configuration(preset)
        _ = try makeBackup(zero).validated()
        preset.target = nil
        #expect(try TrioSettingsBackup.fingerprint(for: zero) == TrioSettingsBackup.fingerprint(for: configuration(preset)))
        #expect(try SettingsBackupRestore.onboardingConfiguration(zero).presets.overrides.first?.target == nil)
    }

    @Test(
        "Missing, unknown and mistyped saved settings fail instead of defaulting",
        arguments: ["missing", "unknown", "mistyped"]
    ) func strictDecoding(_ mutation: String) throws {
        let backup = try makeBackup(validConfiguration())
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(backup)) as? [String: Any])
        var configuration = try #require(object["configuration"] as? [String: Any])
        var preferences = try #require(configuration["preferences"] as? [String: Any])
        if mutation == "missing" { preferences.removeValue(forKey: "max_iob") }
        if mutation == "unknown" { preferences["future_dosing_feature"] = true }
        if mutation == "mistyped" { preferences["max_iob"] = "invalid" }
        configuration["preferences"] = preferences
        object["configuration"] = configuration
        let bytes = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: BackupError.self) { _ = try TrioSettingsBackup.decode(bytes) }
    }

    @Test("Corrupt JSON and future schemas are rejected") func invalidImports() throws {
        #expect(throws: Error.self) { _ = try TrioSettingsBackup.decode(Data("{bad".utf8)) }
        let original = try makeBackup(validConfiguration())
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        object["schemaVersion"] = 999
        let bytes = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: BackupError.self) { _ = try TrioSettingsBackup.decode(bytes) }
    }

    @Test("Schema 2 verifies its checksum before normalization/migration") func migration() throws {
        let configuration = validConfiguration()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let fingerprint = SHA256.hash(data: try encoder.encode(LegacyBackupConfiguration(value: configuration))).map { String(format: "%02x", $0) }.joined()
        let legacy = try makeBackup(configuration, name: "Old settings", schemaVersion: 2, fingerprint: fingerprint)
        let bytes = try JSONEncoder().encode(legacy)
        let migrated = try TrioSettingsBackup.decode(bytes, expectedFingerprint: fingerprint)
        #expect(migrated.schemaVersion == TrioSettingsBackup.currentSchema)
        #expect(migrated.configuration.preferences.maxIOB == configuration.preferences.maxIOB)
        #expect(migrated.configuration.appConfiguration == nil)
        #expect(throws: BackupError.integrityCheckFailed) {
            _ = try TrioSettingsBackup.decode(bytes, expectedFingerprint: "wrong checksum")
        }
    }

    @Test(
        "Critical therapy validation rejects incomplete or inconsistent settings",
        arguments: [
            "negativeIOB",
            "autosens",
            "SMB",
            "peak",
            "nonmidnight",
            "duplicate",
            "basalLimit",
            "timeMismatch",
            "excessIOB",
            "excessSMB",
            "invalidCarbImpact"
        ]
    ) func therapyValidation(_ mutation: String) throws {
        let original = validConfiguration()
        var preferences = original.preferences
        var basal = original.basalProfile
        switch mutation {
        case "excessIOB": preferences.maxIOB = 31
        case "excessSMB": preferences.maxSMBBasalMinutes = 181
        case "invalidCarbImpact": preferences.min5mCarbimpact = 0
        case "negativeIOB": preferences.maxIOB = -1
        case "autosens": preferences.autosensMin = 2
            preferences.autosensMax = 1
        case "SMB": preferences.smbDeliveryRatio = 1.1
        case "peak": preferences.insulinPeakTime = 601
        case "nonmidnight": basal = [.init(start: "01:00:00", minutes: 60, rate: 1)]
        case "duplicate": basal.append(basal[0])
        case "basalLimit": basal = [.init(start: "00:00:00", minutes: 0, rate: 3)]
        default: basal = [.init(start: "01:00:00", minutes: 0, rate: 1)]
        }
        var invalid = original
        invalid.preferences = preferences
        invalid.basalProfile = basal
        #expect(throws: BackupError.self) { _ = try makeBackup(invalid).validated() }
    }

    @Test("App configuration round trips while snoozes and associations are removed") func completeAppConfiguration() throws {
        var configuration = validConfiguration()
        var alert = GlucoseAlert(type: .low)
        alert.snoozedUntil = Date().addingTimeInterval(600)
        configuration.appConfiguration = .init(
            appearance: .dark,
            liveActivityOrder: ["iob", "cob", "", ""],
            glucoseAlerts: [alert],
            glucoseAlertConfiguration: .init(),
            deviceAlertConfigurations: [.init(severity: .critical)]
        )
        let safe = try TrioSettingsBackup.normalized(configuration)
        let decoded = try TrioSettingsBackup.decode(JSONEncoder().encode(makeBackup(safe)))
        #expect(decoded.configuration.appConfiguration?.appearance == .dark)
        #expect(decoded.configuration.appConfiguration?.liveActivityOrder?.first == "iob")
        #expect(decoded.configuration.appConfiguration?.glucoseAlerts.first?.snoozedUntil == nil)
        let text = String(decoding: try JSONEncoder().encode(decoded), as: UTF8.self)
        #expect(!text.contains("pumpManagerRawValue"))
        #expect(!text.contains("snoozedUntil"))
        #expect(!text.contains("sharedSecret"))
    }

    @Test("Rollback reload retains the alert stores' existing migration and baseline rules") func alertStoreRollbackReload() throws {
        let defaults = isolatedDefaults()
        let glucose = GlucoseAlertsStore(defaults: defaults)
        let low = GlucoseAlert(type: .low)
        try defaults.set(JSONEncoder().encode([low]), forKey: "trio.glucoseAlerts.v1")
        glucose.reloadSavedConfiguration()
        #expect(Set(glucose.alerts.map(\.type)) == Set(GlucoseAlertType.allCases))
        #expect(glucose.alerts.contains(where: { $0.id == low.id }))
        let device = DeviceAlertsStore(defaults: defaults)
        try defaults.set(JSONEncoder().encode([DeviceAlertSeverityConfig]()), forKey: "trio.deviceAlertSeverityConfigs.v1")
        device.reloadSavedConfiguration()
        #expect(DeviceAlertSeverity.allCases.allSatisfy { severity in
            device.configs.contains(where: { $0.severity == severity && $0.activeOption == .always })
        })
    }

    @Test("Default alert row identities do not create redundant backups across launches") func alertIdentityNormalization() throws {
        var first = validConfiguration()
        first.appConfiguration = .init(
            appearance: .systemDefault,
            liveActivityOrder: nil,
            glucoseAlerts: [GlucoseAlert(type: .low)],
            glucoseAlertConfiguration: .init(),
            deviceAlertConfigurations: [.init(severity: .critical)]
        )
        var second = validConfiguration()
        second.appConfiguration = .init(
            appearance: .systemDefault,
            liveActivityOrder: nil,
            glucoseAlerts: [GlucoseAlert(type: .low)],
            glucoseAlertConfiguration: .init(),
            deviceAlertConfigurations: [.init(severity: .critical)]
        )
        #expect(try TrioSettingsBackup.fingerprint(for: first) == TrioSettingsBackup.fingerprint(for: second))
    }

    @Test("Oversized imports are rejected before JSON decoding") func oversizedImport() {
        #expect(throws: BackupError.backupTooLarge) {
            _ = try TrioSettingsBackup.decode(Data(repeating: 0, count: TrioSettingsBackup.maximumSize + 1))
        }
    }

    @Test("File imports reject oversized files before parsing") func boundedFileRead() throws {
        let directory = try directory()
        let url = directory.appendingPathComponent("large.json")
        try Data().write(to: url)
        let file = try FileHandle(forWritingTo: url)
        defer { try? file.close() }
        try file.truncate(atOffset: UInt64(TrioSettingsBackup.maximumSize + 1024))
        #expect(throws: BackupError.backupTooLarge) { _ = try TrioSettingsBackup.readBackupData(from: url) }
    }

    @Test("Backup navigation follows Trio's configuration menus and keeps section headings on their screens")
    func previewSettingsHierarchy() throws {
        let nodes = BackupSettingsNode.make(from: try makeBackup(validConfiguration()))
        #expect(nodes.filter { $0.id != "presets" }.map { $0.title.localized } == SettingItems.trioConfig.map(\.title))
        let therapy = try #require(nodes.first { $0.id == "therapy" })
        #expect(therapy.navigationTitle == "Therapy Settings")
        #expect(therapy.sections.map(\.title) == ["Basic Settings", "Basic Insulin Rates & Targets"])
        #expect(therapy.sections.last?.rows.map(\.title) == ["Glucose Targets", "Basal Rates", "Carb Ratios", "Insulin Sensitivities"])
        #expect(!therapy.children.flatMap(\.children).contains { $0.id == "trioSettings.dosingMode" })
        let devices = try #require(nodes.first { $0.id == "devices" })
        let watch = try #require(devices.children.first { $0.title == "Smart Watch" })
        #expect(watch.sections.first?.rows.map(\.title) == ["Apple Watch", "Garmin"])
        let presets = try #require(nodes.first { $0.id == "presets" })
        #expect(presets.sections.first?.rows.map(\.title) == ["Overrides", "Temporary Targets", "Meals"])
    }

    @Test("Backup preview shows saved schedule values in the backup's glucose units") func previewSavedValues() throws {
        var configuration = validConfiguration()
        configuration.settings.units = .mmolL
        configuration.preferences.maxIOB = 7
        configuration.insulinSensitivities = .init(
            units: .mgdL, userPreferredUnits: .mmolL,
            sensitivities: [.init(sensitivity: 72, offset: 0, start: "00:00:00")]
        )
        let backup = try makeBackup(configuration)
        let before = try TrioSettingsBackup.encoded(backup)
        let nodes = BackupSettingsNode.make(from: backup)
        func find(_ id: String, in nodes: [BackupSettingsNode]) -> BackupSettingsNode? {
            for node in nodes {
                if node.id == id { return node }
                if let found = find(id, in: node.children) { return found }
            }
            return nil
        }
        #expect(find("preferences.maxIOB", in: nodes)?.value?.contains("7 U") == true)
        #expect(find("preferences.adjustmentFactor", in: nodes)?.value?.contains("80 %") == true)
        #expect(find("basal-0", in: nodes)?.value?.contains("1 U/hr") == true)
        #expect(find("carbs-0", in: nodes)?.value?.contains("10 g/U") == true)
        #expect(find("isf-0", in: nodes)?.value?.contains("4 mmol/L/U") == true)
        #expect(find("trioSettings.cgm", in: nodes) != nil)
        #expect(find("trioSettings.dosingMode", in: nodes) == nil)
        #expect(try TrioSettingsBackup.encoded(backup) == before)
    }

    @Test("Backup preview distinguishes glucose targets from carbohydrate alarm thresholds")
    func previewAlarmAndPresetUnits() throws {
        var configuration = validConfiguration()
        configuration.settings.units = .mmolL
        var low = GlucoseAlert(type: .low)
        low.thresholdMgDL = 72
        var carbs = GlucoseAlert(type: .carbsRequired)
        carbs.thresholdMgDL = 15
        configuration.appConfiguration = .init(
            appearance: .systemDefault, liveActivityOrder: nil,
            glucoseAlerts: [low, carbs], glucoseAlertConfiguration: .init(), deviceAlertConfigurations: []
        )
        configuration.presets = .init(
            overrides: [],
            tempTargets: [.init(name: "Activity", order: 0, duration: 60, target: 108, halfBasalTarget: 144)],
            meals: []
        )
        let nodes = BackupSettingsNode.make(from: try makeBackup(configuration))
        let notifications = try #require(nodes.first { $0.id == "notifications" })
        #expect(notifications.children.filter { $0.title == "Glucose Alarms" }.count == 1)
        #expect(Set(notifications.children.map(\.id)).count == notifications.children.count)
        func find(_ id: String, in nodes: [BackupSettingsNode]) -> BackupSettingsNode? {
            for node in nodes {
                if node.id == id { return node }
                if let found = find(id, in: node.children) { return found }
            }
            return nil
        }
        #expect(find("Notifications/Glucose Alarms/0/thresholdMgDL", in: nodes)?.value == "4 mmol/L")
        #expect(find("Notifications/Glucose Alarms/1/thresholdMgDL", in: nodes)?.value == "15 g")
        #expect(find("Presets/Temporary Targets/0/target", in: nodes)?.value == "6 mmol/L")
        #expect(find("Presets/Temporary Targets/0/duration", in: nodes)?.value == "60 minutes")
        #expect(find("Notifications/Day & Night Windows/dayStart", in: nodes)?.value == "06:00")
    }

    @Test("Backup preview keeps saved Dynamic ISF history visible after restore eligibility expires")
    func previewOlderHistory() throws {
        let createdAt = Date().addingTimeInterval(-11 * 86400)
        let backup = try historyBackup([tdd(createdAt.addingTimeInterval(-300), total: 42)], createdAt: createdAt)
        #expect(backup.eligibleTDDHistory().isEmpty)
        let algorithm = try #require(BackupSettingsNode.make(from: backup).first { $0.id == "algorithm" })
        let dynamic = try #require(algorithm.children.first { $0.title == "Dynamic Settings" })
        let history = try #require(dynamic.children.first { $0.id == "tdd-history" })
        #expect(history.children.first { $0.id == "history-count" }?.value == "1")
        #expect(history.children.first { $0.id == "history-total" }?.value == "42 U")
        #expect(history.children.first { $0.id == "history-last" }?.value != nil)
    }

    @Test("Exporting a downloaded backup preserves its identity and Dynamic ISF history")
    func exportDownloadedSnapshot() throws {
        let createdAt = Date().addingTimeInterval(-2 * 86400)
        var snapshot = try historyBackup([tdd(createdAt.addingTimeInterval(-300))], createdAt: createdAt)
        snapshot.name = "Downloaded Cloud Backup"
        let url = try BackupFileService.export(snapshot)
        defer { try? FileManager.default.removeItem(at: url) }
        let exported = try TrioSettingsBackup.decode(TrioSettingsBackup.readBackupData(from: url))
        #expect(exported.id == snapshot.id)
        #expect(exported.createdAt == snapshot.createdAt)
        #expect(exported.origin == snapshot.origin)
        #expect(exported.name == snapshot.name)
        #expect(exported.fingerprint == snapshot.fingerprint)
        #expect(exported.dynamicISFHistory == snapshot.dynamicISFHistory)
        #expect(exported.historyChecksum == snapshot.historyChecksum)
    }

}


/// Owns only resources created by this suite instance, including parameterized test cases.
final class BackupTestResources {
    private var directories: [URL] = []
    private var defaultsSuites: [String] = []

    func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        directories.append(url)
        return url
    }

    func defaults() -> UserDefaults {
        let name = "BackupTests.\(UUID().uuidString)"
        defaultsSuites.append(name)
        return UserDefaults(suiteName: name)!
    }

    deinit {
        for url in directories { try? FileManager.default.removeItem(at: url) }
        for name in defaultsSuites { UserDefaults(suiteName: name)?.removePersistentDomain(forName: name) }
    }
}

final class BackupFailingSaveContext: NSManagedObjectContext {
    enum Failure: Error { case unavailable }
    var shouldFail = true
    override func save() throws {
        if shouldFail { throw Failure.unavailable }
        try super.save()
    }
}

