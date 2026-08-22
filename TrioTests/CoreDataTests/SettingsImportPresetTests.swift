import CoreData
import Foundation
import Swinject
import Testing

@testable import Trio

@Suite("Settings Import Preset Tests", .serialized) struct SettingsImportPresetTests: Injectable {
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

    private func seedTempTargetPreset(name: String, target: Decimal, enabled: Bool = false) async throws {
        try await tempTargetsStorage.storeTempTarget(tempTarget: TempTarget(
            name: name,
            createdAt: Date(),
            targetTop: target,
            targetBottom: target,
            duration: 60,
            enteredBy: TempTarget.local,
            reason: nil,
            isPreset: true,
            enabled: enabled,
            halfBasalTarget: nil
        ))
    }

    private func loadedPresets() async throws -> SettingsBackupPresetLoader.LoadedPresets {
        try await SettingsBackupPresetLoader.load(
            tempTargetsStorage: tempTargetsStorage,
            overrideStorage: overrideStorage,
            context: testContext
        )
    }

    @Test("Replace same-named replaces duplicates and keeps others") func testReplaceSameNamed() async throws {
        try await seedTempTargetPreset(name: "Sport", target: 140)
        try await seedTempTargetPreset(name: "Night", target: 110)

        let imported = SettingsBackup.Presets(
            tempTargets: [
                SettingsBackup.TempTargetPreset(name: "Sport", target: 150, duration: 90, halfBasalTarget: nil, orderPosition: nil),
                SettingsBackup.TempTargetPreset(name: "New", target: 130, duration: 30, halfBasalTarget: nil, orderPosition: nil)
            ],
            overrides: nil,
            meals: nil
        )

        await SettingsBackupPresetApplier.apply(
            imported,
            categories: [.tempTargetPresets],
            strategy: .replaceSameNamed,
            tempTargetsStorage: tempTargetsStorage,
            overrideStorage: overrideStorage,
            context: testContext
        )

        let result = try await loadedPresets()
        let byName = Dictionary(
            (result.presets.tempTargets ?? []).map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        #expect(byName.count == 3)
        #expect(byName["Sport"]?.target == 150)
        #expect(byName["Sport"]?.duration == 90)
        #expect(byName["Night"]?.target == 110)
        #expect(byName["New"]?.target == 130)
    }

    @Test("Keep existing never touches presets with known names") func testKeepExisting() async throws {
        try await seedTempTargetPreset(name: "Sport", target: 140)

        let imported = SettingsBackup.Presets(
            tempTargets: [
                SettingsBackup.TempTargetPreset(name: "Sport", target: 150, duration: 90, halfBasalTarget: nil, orderPosition: nil),
                SettingsBackup.TempTargetPreset(name: "New", target: 130, duration: 30, halfBasalTarget: nil, orderPosition: nil)
            ],
            overrides: nil,
            meals: nil
        )

        await SettingsBackupPresetApplier.apply(
            imported,
            categories: [.tempTargetPresets],
            strategy: .keepExisting,
            tempTargetsStorage: tempTargetsStorage,
            overrideStorage: overrideStorage,
            context: testContext
        )

        let result = try await loadedPresets()
        let byName = Dictionary(
            (result.presets.tempTargets ?? []).map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        #expect(byName.count == 2)
        #expect(byName["Sport"]?.target == 140)
        #expect(byName["New"]?.target == 130)
    }

    @Test("Replace all removes presets missing from the file") func testReplaceAll() async throws {
        try await seedTempTargetPreset(name: "Sport", target: 140)
        try await seedTempTargetPreset(name: "Night", target: 110)

        let imported = SettingsBackup.Presets(
            tempTargets: [
                SettingsBackup.TempTargetPreset(name: "Sport", target: 150, duration: 90, halfBasalTarget: nil, orderPosition: nil)
            ],
            overrides: nil,
            meals: nil
        )

        await SettingsBackupPresetApplier.apply(
            imported,
            categories: [.tempTargetPresets],
            strategy: .replaceAll,
            tempTargetsStorage: tempTargetsStorage,
            overrideStorage: overrideStorage,
            context: testContext
        )

        let result = try await loadedPresets()
        let tempTargets = result.presets.tempTargets ?? []

        #expect(tempTargets.count == 1)
        #expect(tempTargets.first?.name == "Sport")
        #expect(tempTargets.first?.target == 150)
    }

    @Test("A running preset survives replace-all untouched") func testRunningPresetIsProtected() async throws {
        try await seedTempTargetPreset(name: "Sport", target: 140, enabled: true)

        let imported = SettingsBackup.Presets(
            tempTargets: [
                SettingsBackup.TempTargetPreset(name: "Sport", target: 150, duration: 90, halfBasalTarget: nil, orderPosition: nil)
            ],
            overrides: nil,
            meals: nil
        )

        let warnings = await SettingsBackupPresetApplier.apply(
            imported,
            categories: [.tempTargetPresets],
            strategy: .replaceAll,
            tempTargetsStorage: tempTargetsStorage,
            overrideStorage: overrideStorage,
            context: testContext
        )

        let result = try await loadedPresets()
        let tempTargets = result.presets.tempTargets ?? []

        #expect(tempTargets.count == 1)
        #expect(tempTargets.first?.target == 140)
        #expect(result.activeTempTargetNames.contains("Sport"))
        #expect(warnings.contains { $0.contains("Sport") })
    }

    @Test("Override presets round-trip all attributes") func testOverridePresetFidelity() async throws {
        let importedOverride = SettingsBackup.OverridePreset(
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
            orderPosition: nil
        )

        await SettingsBackupPresetApplier.apply(
            SettingsBackup.Presets(tempTargets: nil, overrides: [importedOverride], meals: nil),
            categories: [.overridePresets],
            strategy: .replaceSameNamed,
            tempTargetsStorage: tempTargetsStorage,
            overrideStorage: overrideStorage,
            context: testContext
        )

        let result = try await loadedPresets()
        let stored = try #require(result.presets.overrides?.first)

        #expect(stored.name == importedOverride.name)
        #expect(stored.percentage == importedOverride.percentage)
        #expect(stored.indefinite == importedOverride.indefinite)
        #expect(stored.duration == importedOverride.duration)
        #expect(stored.target == importedOverride.target)
        #expect(stored.advancedSettings == importedOverride.advancedSettings)
        #expect(stored.smbIsScheduledOff == importedOverride.smbIsScheduledOff)
        #expect(stored.start == importedOverride.start)
        #expect(stored.end == importedOverride.end)
        #expect(stored.isfAndCr == importedOverride.isfAndCr)
        #expect(stored.smbMinutes == importedOverride.smbMinutes)
        #expect(stored.uamMinutes == importedOverride.uamMinutes)
    }

    @Test("Meal presets import and replace by dish name") func testMealPresets() async throws {
        let firstImport = SettingsBackup.Presets(
            tempTargets: nil,
            overrides: nil,
            meals: [SettingsBackup.MealPreset(dish: "Pizza", carbs: 80, fat: 30, protein: 25)]
        )
        await SettingsBackupPresetApplier.apply(
            firstImport,
            categories: [.mealPresets],
            strategy: .replaceSameNamed,
            tempTargetsStorage: tempTargetsStorage,
            overrideStorage: overrideStorage,
            context: testContext
        )

        let secondImport = SettingsBackup.Presets(
            tempTargets: nil,
            overrides: nil,
            meals: [
                SettingsBackup.MealPreset(dish: "Pizza", carbs: 90, fat: 35, protein: 30),
                SettingsBackup.MealPreset(dish: "Salad", carbs: 10, fat: 5, protein: 5)
            ]
        )
        await SettingsBackupPresetApplier.apply(
            secondImport,
            categories: [.mealPresets],
            strategy: .replaceSameNamed,
            tempTargetsStorage: tempTargetsStorage,
            overrideStorage: overrideStorage,
            context: testContext
        )

        let result = try await loadedPresets()
        let byDish = Dictionary(
            (result.presets.meals ?? []).map { ($0.dish, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        #expect(byDish.count == 2)
        #expect(byDish["Pizza"]?.carbs == 90)
        #expect(byDish["Salad"]?.carbs == 10)
    }
}
