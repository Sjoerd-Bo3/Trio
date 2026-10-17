import CoreData
import Foundation
import LoopKit
import Testing
@testable import Trio

/// A settings manager that counts writes, so tests can prove a refused restore touched nothing.
private final class RecordingSettingsManager: SettingsManager {
    var settings: TrioSettings { didSet { settingsWrites += 1 } }
    var preferences: Preferences { didSet { preferencesWrites += 1 } }
    var pumpSettings = PumpSettings(insulinActionCurve: 10, maxBolus: 10, maxBasal: 2)
    var settingsWrites = 0
    var preferencesWrites = 0

    init(settings: TrioSettings = TrioSettings(), preferences: Preferences = Preferences()) {
        self.settings = settings
        self.preferences = preferences
    }

    func updateInsulinCurve(_: InsulinType?) {}
}

private enum Interrupted: Error { case terminated }

extension BackupSnapshotTests {
    // MARK: - File protection

    @Test("Therapy files and the journal are written without complete file protection") func atomicOnlyWrites() throws {
        let url = try directory().appendingPathComponent("nested/preferences.json")
        try TherapyFileWriter.write(Data("{}".utf8), to: url)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect(attributes[.protectionKey] as? FileProtectionType != FileProtectionType.complete)
        #expect(TherapyFileWriter.options == [.atomic])
    }

    @Test("A restore leaves the journal and therapy files readable under the default protection class") func restoreFileProtection(
    ) async throws {
        let directory = try directory()
        let context = try await context()
        let candidate = validConfiguration()
        var journalProtection: Any?
        try await SettingsBackupRestore.performTransaction(
            newFiles: SettingsBackupRestore.configurationFiles(candidate),
            presets: candidate.presets,
            directory: directory,
            context: context,
            defaults: isolatedDefaults(),
            phase: { step in
                guard step == .journalWritten else { return }
                let journal = directory.appendingPathComponent(SettingsBackupRestore.journalFileName)
                journalProtection = try FileManager.default.attributesOfItem(atPath: journal.path)[.protectionKey]
            }
        )
        #expect(journalProtection as? FileProtectionType != FileProtectionType.complete)
        for name in SettingsBackupRestore.names {
            let path = directory.appendingPathComponent(name).path
            let protection = try FileManager.default.attributesOfItem(atPath: path)[.protectionKey]
            #expect(protection as? FileProtectionType != FileProtectionType.complete)
        }
    }

    @Test("No backup source file asks for complete file protection") func protectionGuard() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Trio/Sources")
        // The sources are only present when the tests run from a checkout.
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        let folders = ["Services/SettingsManager", "Modules/Settings", "Modules/Onboarding"]
        for folder in folders {
            let enumerator = FileManager.default.enumerator(at: root.appendingPathComponent(folder), includingPropertiesForKeys: nil)
            while let url = enumerator?.nextObject() as? URL {
                guard url.pathExtension == "swift" else { continue }
                let text = try String(contentsOf: url, encoding: .utf8)
                #expect(!text.contains("completeFileProtection"), "\(url.lastPathComponent) must write with TherapyFileWriter")
            }
        }
    }

    // MARK: - Number fidelity

    @Test("Schedule entries round-trip typical pump values exactly", arguments: ["0.05", "0.35", "1.15"])
    func scheduleDecimalRoundTrip(_ text: String) throws {
        let value = try #require(Decimal(string: text))

        let basal = BasalProfileEntry(start: "00:00:00", minutes: 0, rate: value)
        let basalData = try JSONCoding.encoder.encode(basal)
        let decodedBasal = try JSONCoding.decoder.decode(BasalProfileEntry.self, from: basalData)
        #expect(decodedBasal.rate == value)
        #expect(try JSONCoding.encoder.encode(decodedBasal) == basalData)
        #expect(String(decoding: basalData, as: UTF8.self).contains(text))

        let ratio = CarbRatioEntry(start: "00:00:00", offset: 0, ratio: value)
        let ratioData = try JSONCoding.encoder.encode(ratio)
        let decodedRatio = try JSONCoding.decoder.decode(CarbRatioEntry.self, from: ratioData)
        #expect(decodedRatio.ratio == value)
        #expect(try JSONCoding.encoder.encode(decodedRatio) == ratioData)

        let sensitivity = InsulinSensitivityEntry(sensitivity: value, offset: 0, start: "00:00:00")
        let sensitivityData = try JSONCoding.encoder.encode(sensitivity)
        let decodedSensitivity = try JSONCoding.decoder.decode(InsulinSensitivityEntry.self, from: sensitivityData)
        #expect(decodedSensitivity.sensitivity == value)
        #expect(try JSONCoding.encoder.encode(decodedSensitivity) == sensitivityData)
    }

    @Test("A snapshot with typical pump rates keeps its fingerprint through encode and decode", arguments: ["0.05", "0.35", "1.15"])
    func snapshotRateFingerprint(_ text: String) throws {
        let value = try #require(Decimal(string: text))
        var configuration = validConfiguration()
        configuration.basalProfile = [BasalProfileEntry(start: "00:00:00", minutes: 0, rate: value)]
        let backup = try makeBackup(configuration)
        let decoded = try BackupFileService.open(JSONEncoder().encode(backup)).snapshot
        #expect(decoded.fingerprint == backup.fingerprint)
        #expect(decoded.configuration.basalProfile.first?.rate == value)
    }

    // MARK: - Startup recovery

    @Test("Startup recovery without a journal reports nothing to do") func startupRecoveryIdle() async throws {
        let outcome = await SettingsBackupRestore.recoverAtStartup(
            directory: try directory(),
            context: try await context(),
            defaults: isolatedDefaults()
        )
        #expect(outcome == .none)
    }

    @Test("Startup recovery never throws: an unreadable journal forces Open Loop and leaves a notice")
    func startupRecoveryUnreadableJournal() async throws {
        let directory = try directory()
        var settings = TrioSettings()
        settings.dosingMode = .closed
        try TherapyFileWriter.write(
            JSONCoding.encoder.encode(settings),
            to: directory.appendingPathComponent(OpenAPS.Trio.settings)
        )
        let journal = directory.appendingPathComponent(SettingsBackupRestore.journalFileName)
        try Data("not a journal".utf8).write(to: journal)
        let defaults = isolatedDefaults()
        let outcome = await SettingsBackupRestore.recoverAtStartup(
            directory: directory,
            context: try await context(),
            defaults: defaults
        )
        guard case .needsAttention = outcome else {
            Issue.record("Expected a needs-attention outcome, got \(outcome)")
            return
        }
        let saved = try JSONCoding.decoder.decode(
            TrioSettings.self,
            from: Data(contentsOf: directory.appendingPathComponent(OpenAPS.Trio.settings))
        )
        #expect(saved.dosingMode == .open)
        #expect(defaults.string(forKey: SettingsBackupRestore.needsAttentionKey) != nil)
        #expect(FileManager.default.fileExists(atPath: journal.path))
    }

    @MainActor
    @Test("Startup recovery rolls an interrupted restore back and asks for a review") func startupRecoveryRollsBack() async throws {
        let directory = try directory()
        let context = try await context()
        let defaults = isolatedDefaults()
        await #expect(throws: Interrupted.self) {
            try await SettingsBackupRestore.performTransaction(
                newFiles: SettingsBackupRestore.names.map { ($0, Data("{}".utf8)) },
                presets: validConfiguration().presets,
                directory: directory,
                context: context,
                defaults: defaults,
                phase: { if case .fileWritten = $0 { throw Interrupted.terminated } }
            )
        }
        #expect(journalExists(in: directory))
        let outcome = await SettingsBackupRestore.recoverAtStartup(directory: directory, context: context, defaults: defaults)
        #expect(outcome == .rolledBack)
        #expect(!journalExists(in: directory))
        #expect(defaults.bool(forKey: SettingsBackupRestore.reviewPendingKey))
    }

    // MARK: - Refused restores

    @MainActor
    @Test("A restore refused for an active temp target changes nothing") func refusedForActiveAdjustment() async throws {
        let directory = try directory()
        let context = try await context()
        try await context.perform {
            let target = TempTargetStored(context: context)
            target.enabled = true
            target.isPreset = false
            try context.save()
        }
        var closed = TrioSettings()
        closed.dosingMode = .closed
        let manager = RecordingSettingsManager(settings: closed)
        let backup = try makeBackup(validConfiguration())
        await #expect(throws: BackupError.activeAdjustments) {
            try await SettingsBackupRestore.apply(
                backup,
                settingsManager: manager,
                hasPairedPump: { false },
                supportedBasalRates: nil,
                onboarding: false,
                isOnboarding: { false },
                directory: directory,
                context: context,
                defaults: isolatedDefaults()
            )
        }
        #expect(manager.settings.dosingMode == .closed)
        #expect(manager.settingsWrites == 0 && manager.preferencesWrites == 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @MainActor
    @Test("A restore refused while a pump is paired changes nothing") func refusedWithPairedPump() async throws {
        let directory = try directory()
        let manager = RecordingSettingsManager()
        await #expect(throws: BackupError.pumpNotReady) {
            try await SettingsBackupRestore.apply(
                try makeBackup(validConfiguration()),
                settingsManager: manager,
                hasPairedPump: { true },
                supportedBasalRates: nil,
                onboarding: false,
                isOnboarding: { false },
                directory: directory,
                context: try await context(),
                defaults: isolatedDefaults()
            )
        }
        #expect(manager.settingsWrites == 0 && manager.preferencesWrites == 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @MainActor
    @Test("An onboarding restore outside onboarding changes nothing") func refusedOutsideOnboarding() async throws {
        let directory = try directory()
        let manager = RecordingSettingsManager()
        await #expect(throws: BackupError.notOnboarding) {
            try await SettingsBackupRestore.apply(
                try makeBackup(validConfiguration()),
                settingsManager: manager,
                hasPairedPump: { false },
                supportedBasalRates: nil,
                onboarding: true,
                isOnboarding: { false },
                directory: directory,
                context: try await context(),
                defaults: isolatedDefaults()
            )
        }
        #expect(manager.settingsWrites == 0 && manager.preferencesWrites == 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @MainActor
    @Test("An unresolved journal blocks a new restore and stays untouched") func refusedWithUnresolvedJournal() async throws {
        let directory = try directory()
        let journal = directory.appendingPathComponent(SettingsBackupRestore.journalFileName)
        try Data("pending".utf8).write(to: journal)
        let manager = RecordingSettingsManager()
        await #expect(throws: BackupError.unresolvedRestore) {
            try await SettingsBackupRestore.apply(
                try makeBackup(validConfiguration()),
                settingsManager: manager,
                hasPairedPump: { false },
                supportedBasalRates: nil,
                onboarding: false,
                isOnboarding: { false },
                directory: directory,
                context: try await context(),
                defaults: isolatedDefaults()
            )
        }
        #expect(manager.settingsWrites == 0 && manager.preferencesWrites == 0)
        #expect(try Data(contentsOf: journal) == Data("pending".utf8))
    }

    @MainActor
    @Test("A failure after the journal exists rolls back and ends in Open Loop") func rollbackAfterJournal() async throws {
        let directory = try directory()
        let context = try await context()
        var closed = TrioSettings()
        closed.dosingMode = .closed
        var previous = Preferences()
        previous.maxIOB = 3
        let manager = RecordingSettingsManager(settings: closed, preferences: previous)
        var changed = Preferences()
        changed.maxIOB = 7
        await #expect(throws: Interrupted.self) {
            try await SettingsBackupRestore.apply(
                try makeBackup(validConfiguration(preferences: changed)),
                settingsManager: manager,
                hasPairedPump: { false },
                supportedBasalRates: nil,
                onboarding: false,
                isOnboarding: { false },
                directory: directory,
                context: context,
                defaults: isolatedDefaults(),
                phase: { if case .fileWritten = $0 { throw Interrupted.terminated } }
            )
        }
        #expect(manager.settings.dosingMode == .open)
        #expect(manager.preferences.maxIOB == 3)
        #expect(!journalExists(in: directory))
    }

    @MainActor
    @Test("A completed restore writes the guarded configuration, ends in Open Loop and asks for a review")
    func completedRestore() async throws {
        let directory = try directory()
        let context = try await context()
        let defaults = isolatedDefaults()
        var closed = TrioSettings()
        closed.dosingMode = .closed
        let manager = RecordingSettingsManager(settings: closed)
        var changed = Preferences()
        changed.maxIOB = 7
        _ = try await SettingsBackupRestore.apply(
            try makeBackup(validConfiguration(preferences: changed)),
            settingsManager: manager,
            hasPairedPump: { false },
            supportedBasalRates: nil,
            onboarding: false,
            isOnboarding: { false },
            directory: directory,
            context: context,
            defaults: defaults
        )
        #expect(manager.settings.dosingMode == .open)
        #expect(manager.preferences.maxIOB == 7)
        #expect(!journalExists(in: directory))
        #expect(defaults.bool(forKey: SettingsBackupRestore.reviewPendingKey))
        let saved = try JSONCoding.decoder.decode(
            TrioSettings.self,
            from: Data(contentsOf: directory.appendingPathComponent(OpenAPS.Trio.settings))
        )
        #expect(saved.dosingMode == .open)
    }

    // MARK: - CGM selection

    @Test("The CGM type and plugin travel with the snapshot and survive an onboarding restore") func cgmSelectionIsPortable() throws {
        var configuration = validConfiguration()
        configuration.settings.cgm = .plugin
        configuration.settings.cgmPluginIdentifier = "DexG7"
        let decoded = try TrioSettingsBackup.decode(JSONEncoder().encode(makeBackup(configuration)))
        #expect(decoded.configuration.settings.cgm == .plugin)
        #expect(decoded.configuration.settings.cgmPluginIdentifier == "DexG7")
        let onboarding = try SettingsBackupRestore.onboardingConfiguration(decoded.configuration)
        #expect(onboarding.settings.cgm == .plugin && onboarding.settings.cgmPluginIdentifier == "DexG7")
        var device = TrioSettings()
        device.cgm = .nightscout
        let configured = SettingsBackupRestore.configuredConfiguration(
            decoded.configuration,
            currentSettings: device,
            currentPreferences: Preferences()
        )
        #expect(configured.settings.cgm == .nightscout)
    }

    // MARK: - Guardrails and overview

    @Test("Guardrails clamp out-of-range values with warnings and never touch the dosing mode") func guardrailsClamp() {
        var configuration = validConfiguration()
        configuration.preferences.autosensMax = 100
        configuration.settings.dosingMode = .closed
        let guarded = SettingsImportApplier.applyGuardrails(to: configuration)
        #expect(guarded.configuration.preferences.autosensMax == PickerSettingsProvider.shared.settings.autosensMax.max)
        #expect(guarded.warnings.count == 1)
        #expect(guarded.configuration.settings.dosingMode == .closed)
        #expect(guarded.configuration.basalProfile == configuration.basalProfile)
    }

    @Test("Basal rates snap to the pump's supported rates, keeping zero segments") func guardrailsSnapBasal() {
        var configuration = validConfiguration()
        configuration.basalProfile = [
            BasalProfileEntry(start: "00:00:00", minutes: 0, rate: 0.62),
            BasalProfileEntry(start: "06:00:00", minutes: 360, rate: 0)
        ]
        let guarded = SettingsImportApplier.applyGuardrails(to: configuration, supportedBasalRates: [0.5, 0.6, 0.7])
        #expect(guarded.configuration.basalProfile.map(\.rate) == [0.6, 0])
        #expect(guarded.warnings.count == 1)
    }

    @Test("The change overview lists changed settings, schedules and replaced presets") func changeOverview() {
        let current = BackupCurrentState(
            settings: TrioSettings(),
            preferences: Preferences(),
            pumpSettings: PumpSettings(insulinActionCurve: 10, maxBolus: 10, maxBasal: 2),
            basalProfile: [BasalProfileEntry(start: "00:00:00", minutes: 0, rate: 0.8)],
            carbRatios: nil,
            insulinSensitivities: nil,
            glucoseTargets: nil,
            presets: .init(overrides: [], tempTargets: [], meals: [.init(dish: "Old meal", carbs: 10, fat: 0, protein: 0)])
        )
        var preferences = Preferences()
        preferences.maxIOB = 7
        let changes = SettingsImportApplier.changeSet(restoring: validConfiguration(preferences: preferences), current: current)
        #expect(changes.settingChanges[.therapy]?.contains { $0.newDisplay.contains("7") } == true)
        #expect(changes.therapyChanges.contains { $0.label == String(localized: "Basal Rates") })
        let meals = changes.presetChanges[.mealPresets] ?? []
        #expect(meals.contains(PresetChange(name: "Lunch", kind: .added)))
        #expect(meals.contains(PresetChange(name: "Old meal", kind: .removed)))
        #expect(changes.totalChangeCount > 0)
        let unchanged = SettingsImportApplier.changeSet(
            restoring: validConfiguration(),
            current: BackupCurrentState(
                settings: TrioSettings(),
                preferences: Preferences(),
                pumpSettings: PumpSettings(insulinActionCurve: 10, maxBolus: 10, maxBasal: 2),
                basalProfile: validConfiguration().basalProfile,
                carbRatios: validConfiguration().carbRatios,
                insulinSensitivities: validConfiguration().insulinSensitivities,
                glucoseTargets: validConfiguration().glucoseTargets,
                presets: validConfiguration().presets
            )
        )
        #expect(unchanged.therapyChanges.isEmpty)
        #expect(unchanged.presetChanges[.mealPresets]?.allSatisfy { $0.kind == .keptExisting } == true)
        #expect(unchanged.changeCount(for: .mealPresets) == 0)
    }

    // MARK: - Reading files

    @Test("A schema-1 file converts into a validated snapshot that restores the same therapy") func legacyFileEndToEnd() async throws {
        let legacy = SettingsBackupTestFixtures.fullBackup()
        let opened = try BackupFileService.open(JSONCoding.encoder.encode(legacy))
        #expect(opened.snapshot.schemaVersion == TrioSettingsBackup.currentSchema)
        #expect(!opened.warnings.isEmpty)
        #expect(opened.snapshot.deviceInfo?.pumpType == "Omnipod DASH")

        let prepared = try SettingsBackupRestore.prepare(
            opened.snapshot,
            currentSettings: TrioSettings(),
            currentPreferences: Preferences(),
            onboarding: true,
            supportedBasalRates: nil
        )
        #expect(prepared.configuration.settings.cgm == legacy.trioSettings?.cgm)
        #expect(prepared.configuration.settings.cgmPluginIdentifier == legacy.trioSettings?.cgmPluginIdentifier)
        #expect(prepared.configuration.settings.dosingMode == .open)
        #expect(prepared.configuration.basalProfile.map(\.rate) == [0.8, 1.2])

        let directory = try directory()
        let context = try await context()
        try await SettingsBackupRestore.performTransaction(
            newFiles: SettingsBackupRestore.configurationFiles(prepared.configuration),
            presets: prepared.configuration.presets,
            directory: directory,
            context: context,
            defaults: isolatedDefaults()
        )
        let basal = try JSONCoding.decoder.decode(
            [BasalProfileEntry].self,
            from: Data(contentsOf: directory.appendingPathComponent(OpenAPS.Settings.basalProfile))
        )
        #expect(basal == prepared.configuration.basalProfile)
        let presets = try await TrioSettingsBackup.readPresets(context: context)
        #expect(presets.tempTargets.map(\.name) == ["Sport"])
        #expect(presets.overrides.map(\.name) == ["Lazy Sunday"])
        #expect(presets.meals.map(\.dish) == ["Pizza"])
    }

    @Test("Files that are not backups, are incomplete or come from a newer version are refused") func openRefusals() throws {
        #expect(throws: BackupError.unrecognizedFile) { _ = try BackupFileService.open(Data("{\"hello\": 1}".utf8)) }
        #expect(throws: BackupError.unrecognizedFile) { _ = try BackupFileService.open(Data("not json".utf8)) }
        var partial = SettingsBackup()
        partial.trioSettings = TrioSettings()
        #expect(throws: BackupError.incompleteBackup) { _ = try BackupFileService.open(JSONCoding.encoder.encode(partial)) }
        var object = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(makeBackup(validConfiguration()))) as? [String: Any]
        )
        object["schemaVersion"] = TrioSettingsBackup.currentSchema + 1
        #expect(throws: BackupError.unsupportedSchema) {
            _ = try BackupFileService.open(JSONSerialization.data(withJSONObject: object))
        }
    }

    @Test("A current snapshot file opens unchanged and unknown top-level keys are ignored") func openCurrentSnapshot() throws {
        let backup = try makeBackup(validConfiguration())
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(backup)) as? [String: Any])
        object["futureTier"] = ["anything": true]
        let opened = try BackupFileService.open(JSONSerialization.data(withJSONObject: object))
        #expect(opened.snapshot.id == backup.id)
        #expect(opened.snapshot.fingerprint == backup.fingerprint)
        #expect(opened.warnings.isEmpty)
    }
}
