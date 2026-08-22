import CoreData
import Foundation
import SwiftUI
import Swinject

extension SettingsImport {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() private var broadcaster: Broadcaster!
        @Injected() private var storage: FileStorage!
        @Injected() var overrideStorage: OverrideStorage!
        @Injected() var tempTargetsStorage: TempTargetsStorage!
        @Injected() private var keychain: Keychain!
        @Injected() private var fetchGlucoseManager: FetchGlucoseManager!
        @Injected() private var nightscout: NightscoutManager!
        @Injected() private var tidepoolManager: TidepoolManager!

        let viewContext = CoreDataStack.shared.persistentContainer.viewContext

        enum Phase: Equatable {
            case pickFile
            case preview
            case applying
            case results
        }

        @Published var phase: Phase = .pickFile
        @Published var backup: SettingsBackup?
        @Published var changeSet = ImportChangeSet()
        @Published var selectedCategories: Set<SettingsBackupCategory> = []
        @Published var conflictStrategy: PresetConflictStrategy = .replaceSameNamed {
            didSet { recomputeChangeSet() }
        }

        @Published var importCredentials: Bool = false
        @Published var importDevicePairing: Bool = false
        @Published var warnings: [String] = []
        @Published var appliedCategories: [SettingsBackupCategory] = []
        @Published var importErrorMessage: String?
        @Published var therapyValidationMessage: String?

        private var loadedPresets = SettingsBackupPresetLoader.LoadedPresets()

        enum ImportError: LocalizedError {
            case fileAccessDenied
            case unreadableFile(String)
            case notATrioBackup

            var errorDescription: String? {
                switch self {
                case .fileAccessDenied:
                    return String(localized: "Could not access the selected file.")
                case let .unreadableFile(message):
                    return String(localized: "Could not read the backup file: \(message)")
                case .notATrioBackup:
                    return String(localized: "This file is not a Trio settings backup.")
                }
            }
        }

        // MARK: - Derived state

        /// Categories the loaded backup actually contains — only these are selectable.
        var availableCategories: Set<SettingsBackupCategory> {
            guard let backup = backup else { return [] }
            var categories: Set<SettingsBackupCategory> = []
            if backup.trioSettings != nil || backup.preferences != nil || backup.devices?.pumpState != nil {
                categories.formUnion([.devices, .features, .notifications, .services, .algorithm])
            }
            if backup.therapy != nil || backup.pumpSettings != nil || backup.trioSettings != nil {
                categories.insert(.therapy)
            }
            if backup.presets?.tempTargets?.isNotEmpty == true { categories.insert(.tempTargetPresets) }
            if backup.presets?.overrides?.isNotEmpty == true { categories.insert(.overridePresets) }
            if backup.presets?.meals?.isNotEmpty == true { categories.insert(.mealPresets) }
            if backup.profilePresets?.isNotEmpty == true { categories.insert(.profilePresets) }
            return categories
        }

        private var currentProfilePresets: [ProfilePreset] {
            storage.retrieve(OpenAPS.Trio.profilePresets, as: [ProfilePreset].self) ?? []
        }

        private var activeProfilePresetName: String? {
            guard let activePresetId = storage.retrieve(OpenAPS.Trio.activeProfilePresetId, as: String.self) else {
                return nil
            }
            return currentProfilePresets.first { $0.id == activePresetId }?.name
        }

        var presetCategorySelected: Bool {
            !selectedCategories.isDisjoint(with: [.tempTargetPresets, .overridePresets, .mealPresets])
        }

        var backupSchemaIsNewer: Bool {
            (backup?.schemaVersion ?? 0) > SettingsBackup.currentSchemaVersion
        }

        var closedLoopActive: Bool {
            settingsManager.settings.closedLoop
        }

        var willAdoptPumpState: Bool {
            importDevicePairing && selectedCategories.contains(.devices) && backup?.devices?.pumpState != nil
        }

        var willAdoptCGMState: Bool {
            importDevicePairing && selectedCategories.contains(.devices) && backup?.devices?.cgmState != nil &&
                backup?.trioSettings?.cgm == .plugin
        }

        /// Units the merged state ends up with — used for snapping and rendering the overview.
        var effectiveUnits: GlucoseUnits {
            if selectedCategories.contains(.therapy), let imported = backup?.trioSettings {
                return imported.units
            }
            return settingsManager.settings.units
        }

        /// Items that are deliberately never restored, shown in the preview.
        var notImportedNotes: [String] {
            guard let backup = backup else { return [] }
            var notes: [String] = [
                String(localized: "Closed Loop mode is never changed by an import."),
                String(localized: "Bolus increment is controlled by the pump and is never imported.")
            ]
            if let pumpType = backup.devices?.pumpType {
                if backup.devices?.pumpState == nil || !importDevicePairing {
                    notes.append(
                        String(
                            localized: "The backup was created with pump \"\(pumpType)\". Pumps must be paired manually under Devices > Insulin Pump."
                        )
                    )
                }
            }
            if backup.profilePresets?.isNotEmpty == true {
                notes.append(String(localized: "The active profile is never switched by an import."))
            }
            return notes
        }

        // MARK: - Loading

        func loadBackup(from url: URL) {
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch {
                importErrorMessage = ImportError.unreadableFile(error.localizedDescription).localizedDescription
                return
            }

            let decoded: SettingsBackup
            do {
                decoded = try JSONCoding.decoder.decode(SettingsBackup.self, from: data)
            } catch {
                debug(.default, "❌ IMPORT: Failed to decode backup: \(error)")
                importErrorMessage = ImportError.notATrioBackup.localizedDescription
                return
            }

            backup = decoded

            Task {
                let loaded = (try? await SettingsBackupPresetLoader.load(
                    tempTargetsStorage: tempTargetsStorage,
                    overrideStorage: overrideStorage,
                    context: viewContext
                )) ?? SettingsBackupPresetLoader.LoadedPresets()

                await MainActor.run {
                    self.loadedPresets = loaded
                    self.selectedCategories = self.availableCategories
                    self.recomputeChangeSet()
                    self.phase = .preview
                }
            }
        }

        // MARK: - Change overview

        /// Rebuilds the change overview from the same tables and guardrails the apply uses.
        func recomputeChangeSet() {
            guard let backup = backup else {
                changeSet = ImportChangeSet()
                return
            }

            let units = effectiveUnits
            var newChangeSet = ImportChangeSet()

            if let importedTrio = backup.trioSettings {
                let changes = SettingsImportApplier.settingChanges(
                    SettingsImportApplier.trioSettingsFields,
                    current: settingsManager.settings,
                    imported: importedTrio,
                    units: units
                )
                newChangeSet.settingChanges.merge(changes) { $0 + $1 }
            }

            if let importedPreferences = backup.preferences {
                let changes = SettingsImportApplier.settingChanges(
                    SettingsImportApplier.preferencesFields,
                    current: settingsManager.preferences,
                    imported: importedPreferences,
                    units: units
                )
                newChangeSet.settingChanges.merge(changes) { $0 + $1 }
            }

            if let importedPumpSettings = backup.pumpSettings {
                let mergeResult = SettingsImportApplier.mergePumpSettings(
                    current: settingsManager.pumpSettings,
                    imported: importedPumpSettings,
                    units: units
                )
                if mergeResult.changes.isNotEmpty {
                    newChangeSet.settingChanges[.therapy, default: []].append(contentsOf: mergeResult.changes)
                }
            }

            therapyValidationMessage = nil
            if let therapy = backup.therapy {
                do {
                    let normalized = try SettingsImportApplier.validateTherapy(
                        therapy,
                        supportedBasalRates: provider.supportedBasalRates
                    )
                    newChangeSet.therapyChanges = therapyChanges(normalized: normalized, units: units)
                } catch {
                    therapyValidationMessage = error.localizedDescription
                }
            }

            if let tempTargets = backup.presets?.tempTargets {
                newChangeSet.presetChanges[.tempTargetPresets] = SettingsImportApplier.resolvePresetConflicts(
                    imported: tempTargets,
                    existingNames: (loadedPresets.presets.tempTargets ?? []).map(\.name),
                    activeNames: loadedPresets.activeTempTargetNames,
                    strategy: conflictStrategy,
                    name: \.name
                ).changes
            }
            if let overrides = backup.presets?.overrides {
                newChangeSet.presetChanges[.overridePresets] = SettingsImportApplier.resolvePresetConflicts(
                    imported: overrides,
                    existingNames: (loadedPresets.presets.overrides ?? []).map(\.name),
                    activeNames: loadedPresets.activeOverrideNames,
                    strategy: conflictStrategy,
                    name: \.name
                ).changes
            }
            if let meals = backup.presets?.meals {
                newChangeSet.presetChanges[.mealPresets] = SettingsImportApplier.resolvePresetConflicts(
                    imported: meals,
                    existingNames: (loadedPresets.presets.meals ?? []).map(\.dish),
                    activeNames: [],
                    strategy: conflictStrategy,
                    name: \.dish
                ).changes
            }
            if let profilePresets = backup.profilePresets {
                newChangeSet.presetChanges[.profilePresets] = SettingsImportApplier.mergeProfilePresets(
                    existing: currentProfilePresets,
                    imported: profilePresets,
                    activeName: activeProfilePresetName,
                    strategy: conflictStrategy
                ).changes
            }

            changeSet = newChangeSet
        }

        private func therapyChanges(normalized: NormalizedTherapy, units: GlucoseUnits) -> [TherapyScheduleChange] {
            var changes: [TherapyScheduleChange] = []

            func glucoseDisplay(_ value: Decimal) -> String {
                BackupDisplay.glucose(value, units)
            }

            if let imported = normalized.basalProfile {
                let current = storage.retrieve(OpenAPS.Settings.basalProfile, as: [BasalProfileEntry].self) ?? []
                if let change = SettingsImportApplier.therapyScheduleChange(
                    label: String(localized: "Basal Rates"),
                    current: current.map { ($0.minutes, "\($0.rate) \(String(localized: "U/hr", comment: "Insulin unit per hour abbreviation"))") },
                    imported: imported.map { ($0.minutes, "\($0.rate) \(String(localized: "U/hr", comment: "Insulin unit per hour abbreviation"))") }
                ) {
                    changes.append(change)
                }
            }

            if let imported = normalized.bgTargets {
                let current = storage.retrieve(OpenAPS.Settings.bgTargets, as: BGTargets.self)?.targets ?? []
                if let change = SettingsImportApplier.therapyScheduleChange(
                    label: String(localized: "Glucose Targets"),
                    current: current.map { ($0.offset, glucoseDisplay($0.low)) },
                    imported: imported.targets.map { ($0.offset, glucoseDisplay($0.low)) }
                ) {
                    changes.append(change)
                }
            }

            if let imported = normalized.carbRatios {
                let current = storage.retrieve(OpenAPS.Settings.carbRatios, as: CarbRatios.self)?.schedule ?? []
                if let change = SettingsImportApplier.therapyScheduleChange(
                    label: String(localized: "Carb Ratios"),
                    current: current.map { ($0.offset, "\($0.ratio) \(String(localized: "g/U"))") },
                    imported: imported.schedule.map { ($0.offset, "\($0.ratio) \(String(localized: "g/U"))") }
                ) {
                    changes.append(change)
                }
            }

            if let imported = normalized.insulinSensitivities {
                let current = storage.retrieve(OpenAPS.Settings.insulinSensitivities, as: InsulinSensitivities.self)?
                    .sensitivities ?? []
                if let change = SettingsImportApplier.therapyScheduleChange(
                    label: String(localized: "Insulin Sensitivities"),
                    current: current.map { ($0.offset, glucoseDisplay($0.sensitivity)) },
                    imported: imported.sensitivities.map { ($0.offset, glucoseDisplay($0.sensitivity)) }
                ) {
                    changes.append(change)
                }
            }

            return changes
        }

        // MARK: - Apply

        func applyImport() async {
            guard let backup = backup else { return }

            await MainActor.run { phase = .applying }
            debug(.default, "🔄 IMPORT: Applying backup (categories: \(selectedCategories.map(\.rawValue).sorted()))")

            var collectedWarnings: [String] = []
            let categories = selectedCategories
            let units = effectiveUnits

            // 1. TrioSettings — one atomic assignment persists and broadcasts SettingsObserver.
            let previousCgm = settingsManager.settings.cgm
            let previousCgmPluginId = settingsManager.settings.cgmPluginIdentifier
            if let importedTrio = backup.trioSettings {
                let current = settingsManager.settings
                let mergeOutcome = SettingsImportApplier.merge(
                    SettingsImportApplier.trioSettingsFields,
                    current: current,
                    imported: importedTrio,
                    categories: categories,
                    units: units
                )
                var merged = mergeOutcome.result
                collectedWarnings.append(contentsOf: mergeOutcome.warnings)

                if categories.contains(.devices), merged.cgm == .plugin, !willAdoptCGMState {
                    // A plugin CGM without its adopted state would be a dead glucose source.
                    merged.cgm = current.cgm
                    merged.cgmPluginIdentifier = current.cgmPluginIdentifier
                    let pluginName = backup.devices?.cgmDisplayName ?? importedTrio.cgmPluginIdentifier
                    collectedWarnings.append(
                        String(
                            localized: "The backup used CGM plugin \"\(pluginName)\". Add it manually under Devices > CGM."
                        )
                    )
                }
                if categories.contains(.devices), merged.cgm == .enlite, provider.deviceManager.pumpManager == nil {
                    collectedWarnings.append(
                        String(localized: "Medtronic Enlite needs a paired Medtronic pump before glucose readings arrive.")
                    )
                }

                settingsManager.settings = merged
            }

            // 2. Preferences — before presets, whose half basal comparison reads preferences.
            if let importedPreferences = backup.preferences {
                let (merged, mergeWarnings) = SettingsImportApplier.merge(
                    SettingsImportApplier.preferencesFields,
                    current: settingsManager.preferences,
                    imported: importedPreferences,
                    categories: categories,
                    units: units
                )
                collectedWarnings.append(contentsOf: mergeWarnings)
                settingsManager.preferences = merged
            }

            // 3. Device pairing state, then CGM re-initialization.
            if willAdoptPumpState, let pumpStateBase64 = backup.devices?.pumpState {
                if let rawValue = SettingsBackup.decodeManagerState(pumpStateBase64),
                   provider.deviceManager.adoptPumpManager(fromRawValue: rawValue)
                {
                    debug(.default, "✅ IMPORT: Adopted pump manager state from backup")
                } else {
                    collectedWarnings.append(
                        String(
                            localized: "Pump pairing could not be restored. Pair your pump manually under Devices > Insulin Pump."
                        )
                    )
                }
            }

            let newCgm = settingsManager.settings.cgm
            let newCgmPluginId = settingsManager.settings.cgmPluginIdentifier
            if willAdoptCGMState, let cgmStateBase64 = backup.devices?.cgmState {
                let adopted = await MainActor.run { () -> Bool in
                    guard let rawValue = SettingsBackup.decodeManagerState(cgmStateBase64) else { return false }
                    return fetchGlucoseManager.adoptCGMManagerState(rawValue, cgmGlucosePluginId: newCgmPluginId)
                }
                if adopted {
                    debug(.default, "✅ IMPORT: Adopted CGM manager state from backup")
                } else {
                    collectedWarnings.append(
                        String(localized: "CGM pairing could not be restored. Add your CGM manually under Devices > CGM.")
                    )
                }
            } else if newCgm != previousCgm || newCgmPluginId != previousCgmPluginId {
                await MainActor.run {
                    fetchGlucoseManager.updateGlucoseSource(cgmGlucoseSourceType: newCgm, cgmGlucosePluginId: newCgmPluginId)
                    broadcaster.notify(GlucoseObserver.self, on: .main) {
                        $0.glucoseDidUpdate([])
                    }
                }
            }

            // 4. Delivery limits + DIA — pump sync first; nothing persisted when the pump rejects.
            if categories.contains(.therapy), let importedPumpSettings = backup.pumpSettings {
                let mergeResult = SettingsImportApplier.mergePumpSettings(
                    current: settingsManager.pumpSettings,
                    imported: importedPumpSettings,
                    units: units
                )
                collectedWarnings.append(contentsOf: mergeResult.warnings)
                do {
                    try await provider.savePumpSettings(mergeResult.result)
                } catch {
                    collectedWarnings.append(
                        String(
                            localized: "Delivery limits could not be synced to the pump and were not changed: \(error.localizedDescription)"
                        )
                    )
                }
            }

            // 5. Therapy schedules.
            if categories.contains(.therapy), let therapy = backup.therapy {
                await applyTherapy(therapy, warnings: &collectedWarnings)
            }

            // 6. Presets.
            let presetCategories = categories.intersection([.tempTargetPresets, .overridePresets, .mealPresets])
            if presetCategories.isNotEmpty, let presets = backup.presets {
                let presetWarnings = await SettingsBackupPresetApplier.apply(
                    presets,
                    categories: presetCategories,
                    strategy: conflictStrategy,
                    tempTargetsStorage: tempTargetsStorage,
                    overrideStorage: overrideStorage,
                    context: viewContext
                )
                collectedWarnings.append(contentsOf: presetWarnings)
            }
            if categories.contains(.profilePresets), let importedProfilePresets = backup.profilePresets {
                let mergeResult = SettingsImportApplier.mergeProfilePresets(
                    existing: currentProfilePresets,
                    imported: importedProfilePresets,
                    activeName: activeProfilePresetName,
                    strategy: conflictStrategy
                )
                collectedWarnings.append(contentsOf: mergeResult.warnings)
                storage.save(mergeResult.result, as: OpenAPS.Trio.profilePresets)
            }

            // 7. UserDefaults-backed extras.
            if categories.contains(.features), let userDefaultsValues = backup.userDefaults {
                if let colorScheme = userDefaultsValues.colorSchemePreference {
                    UserDefaults.standard.set(colorScheme, forKey: "colorSchemePreference")
                }
                if let remoteControlEnabled = userDefaultsValues.isTrioRemoteControlEnabled {
                    UserDefaults.standard.set(remoteControlEnabled, forKey: "isTrioRemoteControlEnabled")
                }
            }

            // 8. Credentials — consumers read these lazily, so no observer poke is needed.
            if importCredentials, let credentials = backup.credentials {
                if let url = credentials.nightscoutURL {
                    keychain.setValue(url, forKey: NightscoutConfig.Config.urlKey)
                }
                if let secret = credentials.nightscoutSecret {
                    keychain.setValue(secret, forKey: NightscoutConfig.Config.secretKey)
                }
                if let sharedSecret = credentials.remoteControlSharedSecret {
                    UserDefaults.standard.set(sharedSecret, forKey: "trioRemoteControlSharedSecret")
                }
                collectedWarnings.append(
                    String(localized: "Nightscout credentials imported — verify the connection under Services > Nightscout.")
                )
            }

            // 9. Match the therapy editors' post-save behavior. profile.json needs no manual
            // rebuild: the loop regenerates it at the start of every cycle.
            Task.detached(priority: .low) {
                do {
                    try await self.nightscout.uploadProfiles()
                } catch {
                    debug(.default, "❌ IMPORT: Failed to upload profiles to Nightscout: \(error)")
                }
            }
            Task.detached(priority: .low) {
                await self.tidepoolManager.uploadSettings()
            }

            debug(.default, "✅ IMPORT: Backup applied with \(collectedWarnings.count) warning(s)")

            let finalWarnings = collectedWarnings
            await MainActor.run {
                warnings = finalWarnings
                appliedCategories = SettingsBackupCategory.allCases.filter { categories.contains($0) }
                phase = .results
            }
        }

        private func applyTherapy(_ therapy: SettingsBackup.Therapy, warnings: inout [String]) async {
            let normalized: NormalizedTherapy
            do {
                normalized = try SettingsImportApplier.validateTherapy(
                    therapy,
                    supportedBasalRates: provider.supportedBasalRates
                )
            } catch {
                warnings.append(String(localized: "Therapy schedules were not imported: \(error.localizedDescription)"))
                return
            }
            warnings.append(contentsOf: normalized.warnings)

            if let targets = normalized.bgTargets {
                storage.save(targets, as: OpenAPS.Settings.bgTargets)
                await MainActor.run {
                    broadcaster.notify(BGTargetsObserver.self, on: .main) {
                        $0.bgTargetsDidChange(targets)
                    }
                }
            }
            if let sensitivities = normalized.insulinSensitivities {
                storage.save(sensitivities, as: OpenAPS.Settings.insulinSensitivities)
                await MainActor.run {
                    broadcaster.notify(InsulinSensitivitiesObserver.self, on: .main) {
                        $0.insulinSensitivitiesDidChange(sensitivities)
                    }
                }
            }
            if let carbRatios = normalized.carbRatios {
                storage.save(carbRatios, as: OpenAPS.Settings.carbRatios)
                await MainActor.run {
                    broadcaster.notify(CarbRatiosObserver.self, on: .main) {
                        $0.carbRatiosDidChange(carbRatios)
                    }
                }
            }
            if let basalProfile = normalized.basalProfile {
                do {
                    let syncedToPump = try await provider.saveBasalProfile(basalProfile)
                    if !syncedToPump {
                        warnings.append(
                            String(
                                localized: "No pump is paired — the basal profile was saved in Trio and will be programmed onto your pump during pump setup."
                            )
                        )
                    }
                    await MainActor.run {
                        broadcaster.notify(BasalProfileObserver.self, on: .main) {
                            $0.basalProfileDidChange(basalProfile)
                        }
                    }
                } catch {
                    warnings.append(
                        String(
                            localized: "The basal profile could not be synced to the pump and was not changed: \(error.localizedDescription)"
                        )
                    )
                }
            }
        }

    }
}
