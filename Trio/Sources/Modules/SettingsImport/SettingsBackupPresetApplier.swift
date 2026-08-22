import CoreData
import Foundation

/// Applies backup presets to Core Data according to a conflict strategy. Shared by Settings
/// Import and the onboarding backup restore. Presets that are currently running are never
/// deleted or replaced.
enum SettingsBackupPresetApplier {
    /// Applies the preset categories in `categories` and returns user-facing warnings.
    @discardableResult
    static func apply(
        _ presets: SettingsBackup.Presets,
        categories: Set<SettingsBackupCategory> = [.tempTargetPresets, .overridePresets, .mealPresets],
        strategy: PresetConflictStrategy,
        tempTargetsStorage: TempTargetsStorage,
        overrideStorage: OverrideStorage,
        context: NSManagedObjectContext
    ) async -> [String] {
        var warnings: [String] = []

        let loaded = (try? await SettingsBackupPresetLoader.load(
            tempTargetsStorage: tempTargetsStorage,
            overrideStorage: overrideStorage,
            context: context
        )) ?? SettingsBackupPresetLoader.LoadedPresets()

        if categories.contains(.tempTargetPresets), let tempTargets = presets.tempTargets {
            let resolution = SettingsImportApplier.resolvePresetConflicts(
                imported: tempTargets,
                existingNames: (loaded.presets.tempTargets ?? []).map(\.name),
                activeNames: loaded.activeTempTargetNames,
                strategy: strategy,
                name: \.name
            )
            collectWarnings(from: resolution.changes, resolutionWarnings: resolution.warnings, into: &warnings)

            do {
                let namesToDelete = Set(resolution.namesToDelete)
                if namesToDelete.isNotEmpty {
                    let presetIDs = try await tempTargetsStorage.fetchForTempTargetPresets()
                    let idsToDelete: [NSManagedObjectID] = await context.perform {
                        presetIDs.filter { objectID in
                            guard let preset = try? context.existingObject(with: objectID) as? TempTargetStored,
                                  let name = preset.name else { return false }
                            return namesToDelete.contains(name) && !preset.enabled
                        }
                    }
                    for objectID in idsToDelete {
                        await tempTargetsStorage.deleteTempTargetPreset(objectID)
                    }
                }

                for preset in resolution.toStore {
                    try await tempTargetsStorage.storeTempTarget(tempTarget: TempTarget(
                        name: preset.name,
                        createdAt: Date(),
                        targetTop: preset.target,
                        targetBottom: preset.target,
                        duration: preset.duration,
                        enteredBy: TempTarget.local,
                        reason: nil,
                        isPreset: true,
                        enabled: false,
                        halfBasalTarget: preset.halfBasalTarget
                    ))
                }
            } catch {
                warnings.append(String(localized: "Temp target presets could not be imported: \(error.localizedDescription)"))
            }
        }

        if categories.contains(.overridePresets), let overrides = presets.overrides {
            let resolution = SettingsImportApplier.resolvePresetConflicts(
                imported: overrides,
                existingNames: (loaded.presets.overrides ?? []).map(\.name),
                activeNames: loaded.activeOverrideNames,
                strategy: strategy,
                name: \.name
            )
            collectWarnings(from: resolution.changes, resolutionWarnings: resolution.warnings, into: &warnings)

            do {
                let namesToDelete = Set(resolution.namesToDelete)
                if namesToDelete.isNotEmpty {
                    let presetIDs = try await overrideStorage.fetchForOverridePresets()
                    let idsToDelete: [NSManagedObjectID] = await context.perform {
                        presetIDs.filter { objectID in
                            guard let preset = try? context.existingObject(with: objectID) as? OverrideStored,
                                  let name = preset.name else { return false }
                            return namesToDelete.contains(name) && !preset.enabled
                        }
                    }
                    for objectID in idsToDelete {
                        await overrideStorage.deleteOverridePreset(objectID)
                    }
                }

                for preset in resolution.toStore {
                    try await overrideStorage.storeOverride(override: Override(
                        name: preset.name,
                        enabled: false,
                        date: Date(),
                        duration: preset.duration,
                        indefinite: preset.indefinite,
                        percentage: preset.percentage,
                        smbIsOff: preset.smbIsOff,
                        isPreset: true,
                        id: UUID().uuidString,
                        overrideTarget: preset.target != nil,
                        target: preset.target ?? 0,
                        advancedSettings: preset.advancedSettings,
                        isfAndCr: preset.isfAndCr,
                        isf: preset.isf,
                        cr: preset.cr,
                        smbIsScheduledOff: preset.smbIsScheduledOff,
                        start: preset.start ?? 0,
                        end: preset.end ?? 0,
                        smbMinutes: preset.smbMinutes ?? 30,
                        uamMinutes: preset.uamMinutes ?? 30
                    ))
                }
            } catch {
                warnings.append(String(localized: "Override presets could not be imported: \(error.localizedDescription)"))
            }
        }

        if categories.contains(.mealPresets), let meals = presets.meals {
            let resolution = SettingsImportApplier.resolvePresetConflicts(
                imported: meals,
                existingNames: (loaded.presets.meals ?? []).map(\.dish),
                activeNames: [],
                strategy: strategy,
                name: \.dish
            )
            collectWarnings(from: resolution.changes, resolutionWarnings: resolution.warnings, into: &warnings)

            do {
                let namesToDelete = Set(resolution.namesToDelete)
                let toStore = resolution.toStore
                try await context.perform {
                    if namesToDelete.isNotEmpty {
                        let request: NSFetchRequest<MealPresetStored> = MealPresetStored.fetchRequest()
                        let existing = try context.fetch(request)
                        for preset in existing where namesToDelete.contains(preset.dish ?? "") {
                            context.delete(preset)
                        }
                    }
                    for preset in toStore {
                        let newPreset = MealPresetStored(context: context)
                        newPreset.dish = preset.dish
                        newPreset.carbs = preset.carbs as NSDecimalNumber
                        newPreset.fat = preset.fat as NSDecimalNumber
                        newPreset.protein = preset.protein as NSDecimalNumber
                    }
                    guard context.hasChanges else { return }
                    try context.save()
                }
            } catch {
                warnings.append(String(localized: "Meal presets could not be imported: \(error.localizedDescription)"))
            }
        }

        return warnings
    }

    private static func collectWarnings(
        from changes: [PresetChange],
        resolutionWarnings: [String],
        into warnings: inout [String]
    ) {
        warnings.append(contentsOf: resolutionWarnings)
        for change in changes where change.kind == .activeSkipped {
            warnings.append(String(localized: "Preset \"\(change.name)\" is currently running and was not changed."))
        }
    }
}
