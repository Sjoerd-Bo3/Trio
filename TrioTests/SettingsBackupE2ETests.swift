import CoreData
import Foundation
import Swinject
import Testing

@testable import Trio

/// End-to-end round trip through the real persistence layer: build a backup → encode to JSON →
/// decode → run the applier merges → persist via the real `SettingsManager`/`FileStorage` and
/// Core Data → read everything back and compare. Only pump/CGM hardware interaction is out of
/// scope. The host app's files are snapshotted and restored around each test.
@Suite("Settings Backup E2E Tests", .serialized) struct SettingsBackupE2ETests: Injectable {
    @Injected() var settingsManager: SettingsManager!
    @Injected() var fileStorage: FileStorage!
    @Injected() var tempTargetsStorage: TempTargetsStorage!
    @Injected() var overrideStorage: OverrideStorage!
    let resolver: Resolver
    var coreDataStack: CoreDataStack!
    var testContext: NSManagedObjectContext!

    init() async throws {
        coreDataStack = try await CoreDataStack.createForTests()
        testContext = coreDataStack.newTaskContext()

        let assembler = Assembler([
            StorageAssembly(),
            ServiceAssembly(),
            APSAssembly(),
            NetworkAssembly(),
            UIAssembly(),
            SecurityAssembly(),
            TestAssembly(testContext: testContext)
        ])

        resolver = assembler.resolver
        injectServices(resolver)
    }

    private struct PersistedSnapshot {
        let settings: TrioSettings
        let preferences: Preferences
        let basalProfile: [BasalProfileEntry]?
        let sensitivities: InsulinSensitivities?
        let carbRatios: CarbRatios?
        let bgTargets: BGTargets?
    }

    private func takeSnapshot() -> PersistedSnapshot {
        PersistedSnapshot(
            settings: settingsManager.settings,
            preferences: settingsManager.preferences,
            basalProfile: fileStorage.retrieve(OpenAPS.Settings.basalProfile, as: [BasalProfileEntry].self),
            sensitivities: fileStorage.retrieve(OpenAPS.Settings.insulinSensitivities, as: InsulinSensitivities.self),
            carbRatios: fileStorage.retrieve(OpenAPS.Settings.carbRatios, as: CarbRatios.self),
            bgTargets: fileStorage.retrieve(OpenAPS.Settings.bgTargets, as: BGTargets.self)
        )
    }

    private func restore(_ snapshot: PersistedSnapshot) {
        settingsManager.settings = snapshot.settings
        settingsManager.preferences = snapshot.preferences
        if let basalProfile = snapshot.basalProfile {
            fileStorage.save(basalProfile, as: OpenAPS.Settings.basalProfile)
        } else {
            fileStorage.remove(OpenAPS.Settings.basalProfile)
        }
        if let sensitivities = snapshot.sensitivities {
            fileStorage.save(sensitivities, as: OpenAPS.Settings.insulinSensitivities)
        } else {
            fileStorage.remove(OpenAPS.Settings.insulinSensitivities)
        }
        if let carbRatios = snapshot.carbRatios {
            fileStorage.save(carbRatios, as: OpenAPS.Settings.carbRatios)
        } else {
            fileStorage.remove(OpenAPS.Settings.carbRatios)
        }
        if let bgTargets = snapshot.bgTargets {
            fileStorage.save(bgTargets, as: OpenAPS.Settings.bgTargets)
        } else {
            fileStorage.remove(OpenAPS.Settings.bgTargets)
        }
    }

    @Test("Full backup round-trips through JSON and real persistence") func testFullRoundTrip() async throws {
        let snapshot = takeSnapshot()
        defer { restore(snapshot) }

        // Export side: build and encode the backup exactly like the export does.
        let backup = SettingsBackupTestFixtures.fullBackup()
        let data = try JSONCoding.encoder.encode(backup)

        // Import side: decode, merge, persist.
        let decoded = try JSONCoding.decoder.decode(SettingsBackup.self, from: data)
        let importedSettings = try #require(decoded.trioSettings)
        let importedPreferences = try #require(decoded.preferences)
        let allCategories = Set(SettingsBackupCategory.allCases)

        let mergedSettings = SettingsImportApplier.merge(
            SettingsImportApplier.trioSettingsFields,
            current: settingsManager.settings,
            imported: importedSettings,
            categories: allCategories,
            units: importedSettings.units
        ).result
        settingsManager.settings = mergedSettings

        let mergedPreferences = SettingsImportApplier.merge(
            SettingsImportApplier.preferencesFields,
            current: settingsManager.preferences,
            imported: importedPreferences,
            categories: allCategories,
            units: importedSettings.units
        ).result
        settingsManager.preferences = mergedPreferences

        let therapy = try #require(decoded.therapy)
        let normalized = try SettingsImportApplier.validateTherapy(therapy)
        if let targets = normalized.bgTargets { fileStorage.save(targets, as: OpenAPS.Settings.bgTargets) }
        if let sensitivities = normalized.insulinSensitivities {
            fileStorage.save(sensitivities, as: OpenAPS.Settings.insulinSensitivities)
        }
        if let carbRatios = normalized.carbRatios { fileStorage.save(carbRatios, as: OpenAPS.Settings.carbRatios) }
        if let basalProfile = normalized.basalProfile { fileStorage.save(basalProfile, as: OpenAPS.Settings.basalProfile) }

        // Verify: what is on disk equals what the backup carried (modulo exclusions).
        let persistedSettings = try #require(fileStorage.retrieve(OpenAPS.Trio.settings, as: TrioSettings.self))
        var expectedSettings = importedSettings
        expectedSettings.closedLoop = snapshot.settings.closedLoop
        #expect(persistedSettings == expectedSettings)

        let persistedPreferences = try #require(fileStorage.retrieve(OpenAPS.Settings.preferences, as: Preferences.self))
        var expectedPreferences = importedPreferences
        expectedPreferences.bolusIncrement = snapshot.preferences.bolusIncrement
        expectedPreferences.timestamp = persistedPreferences.timestamp
        #expect(persistedPreferences == expectedPreferences)

        let persistedBasal = try #require(fileStorage.retrieve(OpenAPS.Settings.basalProfile, as: [BasalProfileEntry].self))
        #expect(persistedBasal == normalized.basalProfile)

        let persistedTargets = try #require(fileStorage.retrieve(OpenAPS.Settings.bgTargets, as: BGTargets.self))
        #expect(persistedTargets.units == .mgdL)
        #expect(persistedTargets.targets == normalized.bgTargets?.targets)

        // Presets go through Core Data and come back identical.
        let presets = try #require(decoded.presets)
        await SettingsBackupPresetApplier.apply(
            presets,
            strategy: .replaceSameNamed,
            tempTargetsStorage: tempTargetsStorage,
            overrideStorage: overrideStorage,
            context: testContext
        )
        let loaded = try await SettingsBackupPresetLoader.load(
            tempTargetsStorage: tempTargetsStorage,
            overrideStorage: overrideStorage,
            context: testContext
        )
        #expect(loaded.presets.tempTargets?.map(\.name) == presets.tempTargets?.map(\.name))
        #expect(loaded.presets.overrides?.map(\.name) == presets.overrides?.map(\.name))
        #expect(loaded.presets.meals?.map(\.dish) == presets.meals?.map(\.dish))
    }

    @Test("Partial category import leaves the other categories untouched") func testPartialCategoryImport() throws {
        let snapshot = takeSnapshot()
        defer { restore(snapshot) }

        let backup = SettingsBackupTestFixtures.fullBackup()
        let importedSettings = try #require(backup.trioSettings)

        let merged = SettingsImportApplier.merge(
            SettingsImportApplier.trioSettingsFields,
            current: settingsManager.settings,
            imported: importedSettings,
            categories: [.notifications],
            units: settingsManager.settings.units
        ).result
        settingsManager.settings = merged

        let persisted = try #require(fileStorage.retrieve(OpenAPS.Trio.settings, as: TrioSettings.self))
        #expect(persisted.useLiveActivity == importedSettings.useLiveActivity)
        #expect(persisted.glucoseBadge == importedSettings.glucoseBadge)
        #expect(persisted.units == snapshot.settings.units)
        #expect(persisted.maxCarbs == snapshot.settings.maxCarbs)
        #expect(persisted.cgm == snapshot.settings.cgm)
    }
}
