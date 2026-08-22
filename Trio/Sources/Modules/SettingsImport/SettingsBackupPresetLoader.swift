import CoreData
import Foundation

/// Loads the device's presets as backup DTOs. Shared by the export (to build the JSON backup)
/// and the import (to diff the backup against what already exists).
enum SettingsBackupPresetLoader {
    struct LoadedPresets {
        var presets = SettingsBackup.Presets()
        /// Names of presets that are currently running — the import never deletes or replaces these.
        var activeTempTargetNames: Set<String> = []
        var activeOverrideNames: Set<String> = []
    }

    static func load(
        tempTargetsStorage: TempTargetsStorage,
        overrideStorage: OverrideStorage,
        context: NSManagedObjectContext
    ) async throws -> LoadedPresets {
        let tempTargetIDs = try await tempTargetsStorage.fetchForTempTargetPresets()
        let overrideIDs = try await overrideStorage.fetchForOverridePresets()

        return try await context.perform {
            var loaded = LoadedPresets()

            var tempTargets: [SettingsBackup.TempTargetPreset] = []
            for objectID in tempTargetIDs {
                guard let preset = try context.existingObject(with: objectID) as? TempTargetStored else { continue }
                let name = preset.name ?? "Unknown Temp Target"
                tempTargets.append(SettingsBackup.TempTargetPreset(
                    name: name,
                    target: preset.target?.decimalValue ?? 0,
                    duration: preset.duration?.decimalValue ?? 0,
                    halfBasalTarget: preset.halfBasalTarget?.decimalValue,
                    orderPosition: Int(preset.orderPosition)
                ))
                if preset.enabled {
                    loaded.activeTempTargetNames.insert(name)
                }
            }
            loaded.presets.tempTargets = tempTargets

            var overrides: [SettingsBackup.OverridePreset] = []
            for objectID in overrideIDs {
                guard let preset = try context.existingObject(with: objectID) as? OverrideStored else { continue }
                let name = preset.name ?? "Unknown Override"
                let target = preset.target?.decimalValue
                overrides.append(SettingsBackup.OverridePreset(
                    name: name,
                    percentage: preset.percentage,
                    indefinite: preset.indefinite,
                    duration: preset.duration?.decimalValue ?? 0,
                    target: (target ?? 0) != 0 ? target : nil,
                    advancedSettings: preset.advancedSettings,
                    smbIsOff: preset.smbIsOff,
                    smbIsScheduledOff: preset.smbIsScheduledOff,
                    start: preset.start?.decimalValue,
                    end: preset.end?.decimalValue,
                    isfAndCr: preset.isfAndCr,
                    isf: preset.isf,
                    cr: preset.cr,
                    smbMinutes: preset.smbMinutes?.decimalValue,
                    uamMinutes: preset.uamMinutes?.decimalValue,
                    orderPosition: Int(preset.orderPosition)
                ))
                if preset.enabled {
                    loaded.activeOverrideNames.insert(name)
                }
            }
            loaded.presets.overrides = overrides

            let request: NSFetchRequest<MealPresetStored> = MealPresetStored.fetchRequest()
            let mealPresets = try context.fetch(request)
            loaded.presets.meals = mealPresets.map { preset in
                SettingsBackup.MealPreset(
                    dish: preset.dish ?? "Unknown Meal",
                    carbs: preset.carbs?.decimalValue ?? 0,
                    fat: preset.fat?.decimalValue ?? 0,
                    protein: preset.protein?.decimalValue ?? 0
                )
            }

            return loaded
        }
    }
}
