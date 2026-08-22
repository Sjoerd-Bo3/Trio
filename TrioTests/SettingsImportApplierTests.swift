import Foundation
import Testing

@testable import Trio

@Suite("Settings Import Applier Tests") struct SettingsImportApplierTests {
    // MARK: - Mapping totality

    @Test("Every TrioSettings field is mapped or explicitly excluded") func testTrioSettingsTotality() {
        let a = TrioSettings()
        let b = SettingsBackupTestFixtures.maximallyDifferentTrioSettings()

        // Guard for the test itself: the fixture must differ on EVERY stored property, otherwise
        // a newly added field slips through unnoticed. Fails when TrioSettings gains a field the
        // fixture does not vary yet.
        #expect(
            SettingsBackupTestFixtures.differingFieldLabels(a, b).count ==
                SettingsBackupTestFixtures.storedPropertyCount(a)
        )

        // The table plus documented exclusions must cover every stored property.
        #expect(
            SettingsImportApplier.trioSettingsFields.count + SettingsImportApplier.excludedTrioSettingsFieldCount ==
                SettingsBackupTestFixtures.storedPropertyCount(a)
        )

        // Merging every category copies every field except the exclusions.
        let outcome = SettingsImportApplier.merge(
            SettingsImportApplier.trioSettingsFields,
            current: a,
            imported: b,
            categories: Set(SettingsBackupCategory.allCases),
            units: .mgdL
        )
        var expected = b
        expected.closedLoop = a.closedLoop
        #expect(outcome.result == expected)
        #expect(outcome.warnings.isEmpty)
    }

    @Test("Every Preferences field is mapped or explicitly excluded") func testPreferencesTotality() {
        let a = Preferences()
        let b = SettingsBackupTestFixtures.maximallyDifferentPreferences()

        #expect(
            SettingsBackupTestFixtures.differingFieldLabels(a, b).count ==
                SettingsBackupTestFixtures.storedPropertyCount(a)
        )
        #expect(
            SettingsImportApplier.preferencesFields.count + SettingsImportApplier.excludedPreferencesFieldCount ==
                SettingsBackupTestFixtures.storedPropertyCount(a)
        )

        let outcome = SettingsImportApplier.merge(
            SettingsImportApplier.preferencesFields,
            current: a,
            imported: b,
            categories: Set(SettingsBackupCategory.allCases),
            units: .mgdL
        )
        var expected = b
        expected.bolusIncrement = a.bolusIncrement
        expected.timestamp = a.timestamp
        #expect(outcome.result == expected)
        #expect(outcome.warnings.isEmpty)
    }

    @Test("Closed loop and bolus increment are never imported") func testExclusions() {
        var importedSettings = TrioSettings()
        importedSettings.closedLoop = true
        let settingsOutcome = SettingsImportApplier.merge(
            SettingsImportApplier.trioSettingsFields,
            current: TrioSettings(),
            imported: importedSettings,
            categories: Set(SettingsBackupCategory.allCases),
            units: .mgdL
        )
        #expect(settingsOutcome.result.closedLoop == false)

        var importedPreferences = Preferences()
        importedPreferences.bolusIncrement = 0.5
        let preferencesOutcome = SettingsImportApplier.merge(
            SettingsImportApplier.preferencesFields,
            current: Preferences(),
            imported: importedPreferences,
            categories: Set(SettingsBackupCategory.allCases),
            units: .mgdL
        )
        #expect(preferencesOutcome.result.bolusIncrement == Preferences().bolusIncrement)
    }

    // MARK: - Guardrails

    @Test("Out-of-range values clamp to the guardrail bounds with warnings") func testClamping() {
        let guardrails = PickerSettingsProvider.shared.settings

        var imported = Preferences()
        imported.autosensMax = 100
        imported.maxSMBBasalMinutes = 1

        let outcome = SettingsImportApplier.merge(
            SettingsImportApplier.preferencesFields,
            current: Preferences(),
            imported: imported,
            categories: [.algorithm],
            units: .mgdL
        )

        #expect(outcome.result.autosensMax == guardrails.autosensMax.max)
        #expect(outcome.result.maxSMBBasalMinutes == guardrails.maxSMBBasalMinutes.min)
        #expect(outcome.warnings.count == 2)
    }

    @Test("In-range values are preserved exactly") func testInRangeValuesPreserved() {
        var imported = Preferences()
        imported.autosensMax = 1.85 // between picker steps but inside the bounds

        let outcome = SettingsImportApplier.merge(
            SettingsImportApplier.preferencesFields,
            current: Preferences(),
            imported: imported,
            categories: [.algorithm],
            units: .mgdL
        )

        #expect(outcome.result.autosensMax == 1.85)
        #expect(outcome.warnings.isEmpty)
    }

    // MARK: - Category filtering

    @Test("Only fields of the selected categories are merged") func testCategoryFiltering() {
        let a = TrioSettings()
        let b = SettingsBackupTestFixtures.maximallyDifferentTrioSettings()

        let outcome = SettingsImportApplier.merge(
            SettingsImportApplier.trioSettingsFields,
            current: a,
            imported: b,
            categories: [.features],
            units: .mgdL
        )

        // features moved
        #expect(outcome.result.maxCarbs == b.maxCarbs)
        #expect(outcome.result.displayPresets == b.displayPresets)
        // therapy + devices + notifications + services untouched
        #expect(outcome.result.units == a.units)
        #expect(outcome.result.cgm == a.cgm)
        #expect(outcome.result.glucoseBadge == a.glucoseBadge)
        #expect(outcome.result.isUploadEnabled == a.isUploadEnabled)
    }

    // MARK: - Diff parity

    @Test("Change overview matches exactly what merge changes") func testDiffParity() {
        let a = TrioSettings()
        let b = SettingsBackupTestFixtures.maximallyDifferentTrioSettings()

        let changes = SettingsImportApplier.settingChanges(
            SettingsImportApplier.trioSettingsFields,
            current: a,
            imported: b,
            units: .mgdL
        )
        let totalChanges = changes.values.reduce(0) { $0 + $1.count }

        // Every mapped field differs in the fixture, so every mapped field must be listed.
        #expect(totalChanges == SettingsImportApplier.trioSettingsFields.count)

        // Identical values produce no changes at all.
        let noChanges = SettingsImportApplier.settingChanges(
            SettingsImportApplier.trioSettingsFields,
            current: b,
            imported: b,
            units: .mgdL
        )
        #expect(noChanges.isEmpty)
    }

    @Test("Pump settings merge clamps and reports changes") func testPumpSettingsMerge() {
        let guardrails = PickerSettingsProvider.shared.settings
        let current = PumpSettings(insulinActionCurve: 10, maxBolus: 10, maxBasal: 2)
        let imported = PumpSettings(insulinActionCurve: 3, maxBolus: 8, maxBasal: 100)

        let result = SettingsImportApplier.mergePumpSettings(current: current, imported: imported, units: .mgdL)

        #expect(result.result.insulinActionCurve == guardrails.dia.min) // 3 clamps up
        #expect(result.result.maxBolus == 8)
        #expect(result.result.maxBasal == guardrails.maxBasal.max) // 100 clamps down
        #expect(result.warnings.count == 2)
        #expect(result.changes.count == 3)
    }

    // MARK: - Therapy validation

    @Test("Therapy schedules are normalized onto the 30-minute grid") func testTherapyNormalization() throws {
        let therapy = SettingsBackup.Therapy(
            basalProfile: [
                BasalProfileEntry(start: "12:00:00", minutes: 720, rate: 1.0),
                BasalProfileEntry(start: "00:45:00", minutes: 45, rate: 0.8), // off-grid → 00:30
                BasalProfileEntry(start: "12:00:00", minutes: 720, rate: 1.2) // duplicate slot, last wins
            ],
            insulinSensitivities: nil,
            carbRatios: nil,
            bgTargets: nil
        )

        let normalized = try SettingsImportApplier.validateTherapy(therapy)
        let basal = try #require(normalized.basalProfile)

        #expect(basal.count == 2)
        #expect(basal[0].minutes == 0) // first entry forced to midnight
        #expect(basal[0].rate == 0.8)
        #expect(basal[0].start == "00:00:00")
        #expect(basal[1].minutes == 720)
        #expect(basal[1].rate == 1.2)
    }

    @Test("Invalid therapy values are rejected") func testTherapyValidationErrors() {
        func therapy(basal: [BasalProfileEntry]? = nil, isf: [InsulinSensitivityEntry]? = nil,
                     targets: [BGTargetEntry]? = nil) -> SettingsBackup.Therapy
        {
            SettingsBackup.Therapy(
                basalProfile: basal,
                insulinSensitivities: isf
                    .map { InsulinSensitivities(units: .mgdL, userPreferredUnits: .mgdL, sensitivities: $0) },
                carbRatios: nil,
                bgTargets: targets.map { BGTargets(units: .mgdL, userPreferredUnits: .mgdL, targets: $0) }
            )
        }

        #expect(throws: TherapyValidationError.self) {
            _ = try SettingsImportApplier.validateTherapy(therapy(basal: []))
        }
        #expect(throws: TherapyValidationError.self) {
            _ = try SettingsImportApplier.validateTherapy(
                therapy(basal: [BasalProfileEntry(start: "00:00:00", minutes: 0, rate: 0)])
            )
        }
        // mmol/L-looking ISF
        #expect(throws: TherapyValidationError.self) {
            _ = try SettingsImportApplier.validateTherapy(
                therapy(isf: [InsulinSensitivityEntry(sensitivity: 2.5, offset: 0, start: "00:00:00")])
            )
        }
        // mmol/L-looking target
        #expect(throws: TherapyValidationError.self) {
            _ = try SettingsImportApplier.validateTherapy(
                therapy(targets: [BGTargetEntry(low: 5.5, high: 5.5, start: "00:00:00", offset: 0)])
            )
        }
    }

    @Test("Targets normalize to a single value with mg/dL units") func testTargetNormalization() throws {
        let therapy = SettingsBackup.Therapy(
            basalProfile: nil,
            insulinSensitivities: nil,
            carbRatios: nil,
            bgTargets: BGTargets(
                units: .mmolL,
                userPreferredUnits: .mmolL,
                targets: [BGTargetEntry(low: 100, high: 120, start: "00:00:00", offset: 0)]
            )
        )

        let normalized = try SettingsImportApplier.validateTherapy(therapy)
        let targets = try #require(normalized.bgTargets)

        #expect(targets.units == .mgdL)
        #expect(targets.userPreferredUnits == .mgdL)
        #expect(targets.targets[0].high == targets.targets[0].low) // Trio convention: high == low
    }

    @Test("Basal rates snap to pump-supported rates with a warning") func testBasalPumpSnap() throws {
        let therapy = SettingsBackup.Therapy(
            basalProfile: [BasalProfileEntry(start: "00:00:00", minutes: 0, rate: 0.62)],
            insulinSensitivities: nil,
            carbRatios: nil,
            bgTargets: nil
        )

        let normalized = try SettingsImportApplier.validateTherapy(therapy, supportedBasalRates: [0.5, 0.6, 0.7])
        #expect(normalized.basalProfile?[0].rate == 0.6)
        #expect(normalized.warnings.count == 1)
    }

    @Test("Rates that snap to zero on the pump fail the total-basal check") func testZeroTotalBasalAfterSnap() {
        let therapy = SettingsBackup.Therapy(
            basalProfile: [BasalProfileEntry(start: "00:00:00", minutes: 0, rate: 0.01)],
            insulinSensitivities: nil,
            carbRatios: nil,
            bgTargets: nil
        )

        #expect(throws: TherapyValidationError.zeroTotalBasal) {
            _ = try SettingsImportApplier.validateTherapy(therapy, supportedBasalRates: [0, 0.5, 1.0])
        }
    }

    // MARK: - Preset conflict resolution

    private let importedNames = ["Sport", "New"]

    private func resolve(
        strategy: PresetConflictStrategy,
        existing: [String] = ["Sport", "Night"],
        active: Set<String> = []
    ) -> SettingsImportApplier.PresetResolution<String> {
        SettingsImportApplier.resolvePresetConflicts(
            imported: importedNames,
            existingNames: existing,
            activeNames: active,
            strategy: strategy,
            name: { $0 }
        )
    }

    @Test("Replace same-named: replaces duplicates, adds new, keeps the rest") func testReplaceSameNamed() {
        let resolution = resolve(strategy: .replaceSameNamed)

        #expect(resolution.namesToDelete == ["Sport"])
        #expect(resolution.toStore == ["Sport", "New"])
        #expect(resolution.changes == [
            PresetChange(name: "Sport", kind: .replaced),
            PresetChange(name: "New", kind: .added)
        ])
    }

    @Test("Keep existing: only adds unknown names") func testKeepExisting() {
        let resolution = resolve(strategy: .keepExisting)

        #expect(resolution.namesToDelete.isEmpty)
        #expect(resolution.toStore == ["New"])
        #expect(resolution.changes == [
            PresetChange(name: "Sport", kind: .keptExisting),
            PresetChange(name: "New", kind: .added)
        ])
    }

    @Test("Replace all: also removes presets missing from the file") func testReplaceAll() {
        let resolution = resolve(strategy: .replaceAll)

        #expect(Set(resolution.namesToDelete) == ["Sport", "Night"])
        #expect(resolution.toStore == ["Sport", "New"])
        #expect(resolution.changes.contains(PresetChange(name: "Night", kind: .removed)))
    }

    @Test("Running presets are never deleted or replaced") func testActiveSkipped() {
        let resolution = resolve(strategy: .replaceAll, active: ["Sport"])

        #expect(!resolution.namesToDelete.contains("Sport"))
        #expect(!resolution.toStore.contains("Sport"))
        #expect(resolution.changes.contains(PresetChange(name: "Sport", kind: .activeSkipped)))
    }

    @Test("Duplicate names inside the file collapse to the last occurrence") func testDuplicateNamesInFile() {
        let resolution = SettingsImportApplier.resolvePresetConflicts(
            imported: [("Sport", 140), ("Sport", 150)],
            existingNames: [],
            activeNames: [],
            strategy: .replaceSameNamed,
            name: { $0.0 }
        )

        #expect(resolution.toStore.count == 1)
        #expect(resolution.toStore[0].1 == 150)
        #expect(resolution.warnings.count == 1)
    }
}
