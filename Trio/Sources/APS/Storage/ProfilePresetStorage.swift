import CoreData
import Foundation
import Swinject

protocol ProfilePresetStorage {
    func presets() -> [ProfilePreset]
    func savePresets(_ presets: [ProfilePreset])
    func saveCurrentProfileAsPreset(name: String, icon: String, includeSMB: Bool, includeDynamic: Bool) -> ProfilePreset?
    func currentProfile() -> ProfilePreset?
    func activatePreset(_ preset: ProfilePreset) -> Bool
    func deactivatePreset()
    func deactivateCurrentRun()
    func deletePreset(id: String)
    func renamePreset(id: String, newName: String)
    func updatePresetToCurrentSettings(id: String) -> ProfilePreset?
    func activePresetId() -> String?
    func activePreset() -> ProfilePreset?
    func settingsMatchPreset(_ preset: ProfilePreset) -> Bool
    func openDivertedRun(for preset: ProfilePreset)
    func closeDivertedRun(for preset: ProfilePreset)
    func closeStaleRuns()
    func getProfilePresetRunsNotYetUploadedToNightscout() async throws -> [NightscoutTreatment]
}

final class BaseProfilePresetStorage: ProfilePresetStorage, Injectable {
    @Injected() private var storage: FileStorage!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var auditStorage: SettingsAuditStorage!

    private let viewContext = CoreDataStack.shared.persistentContainer.viewContext
    private let backgroundContext = CoreDataStack.shared.newTaskContext()

    static let profilePresetActivatedNotification = Notification.Name("ProfilePresetActivated")

    init(resolver: Resolver) {
        injectServices(resolver)
    }

    func presets() -> [ProfilePreset] {
        storage.retrieve(OpenAPS.Trio.profilePresets, as: [ProfilePreset].self) ?? []
    }

    func savePresets(_ presets: [ProfilePreset]) {
        storage.save(presets, as: OpenAPS.Trio.profilePresets)
    }

    // MARK: - Private Helpers

    private struct CurrentTherapySettings {
        let basalProfile: [BasalProfileEntry]
        let insulinSensitivities: InsulinSensitivities
        let carbRatios: CarbRatios
        let bgTargets: BGTargets
    }

    private func loadCurrentTherapySettings() -> CurrentTherapySettings? {
        let basalProfile = storage.retrieve(OpenAPS.Settings.basalProfile, as: [BasalProfileEntry].self)
            ?? [BasalProfileEntry](from: OpenAPS.defaults(for: OpenAPS.Settings.basalProfile))
            ?? []

        let insulinSensitivities = storage.retrieve(OpenAPS.Settings.insulinSensitivities, as: InsulinSensitivities.self)
            ?? InsulinSensitivities(from: OpenAPS.defaults(for: OpenAPS.Settings.insulinSensitivities))
            ?? InsulinSensitivities(units: .mgdL, userPreferredUnits: .mgdL, sensitivities: [])

        let carbRatios = storage.retrieve(OpenAPS.Settings.carbRatios, as: CarbRatios.self)
            ?? CarbRatios(from: OpenAPS.defaults(for: OpenAPS.Settings.carbRatios))
            ?? CarbRatios(units: .grams, schedule: [])

        let bgTargets = storage.retrieve(OpenAPS.Settings.bgTargets, as: BGTargets.self)
            ?? BGTargets(from: OpenAPS.defaults(for: OpenAPS.Settings.bgTargets))
            ?? BGTargets(units: .mgdL, userPreferredUnits: .mgdL, targets: [])

        guard !basalProfile.isEmpty,
              !insulinSensitivities.sensitivities.isEmpty,
              !carbRatios.schedule.isEmpty,
              !bgTargets.targets.isEmpty
        else {
            return nil
        }

        return CurrentTherapySettings(
            basalProfile: basalProfile,
            insulinSensitivities: insulinSensitivities,
            carbRatios: carbRatios,
            bgTargets: bgTargets
        )
    }

    private func currentSMBSettings() -> SMBPresetSettings {
        let prefs = settingsManager.preferences
        return SMBPresetSettings(
            enableSMBAlways: prefs.enableSMBAlways,
            enableSMBWithCOB: prefs.enableSMBWithCOB,
            enableSMBWithTemptarget: prefs.enableSMBWithTemptarget,
            enableSMBAfterCarbs: prefs.enableSMBAfterCarbs,
            allowSMBWithHighTemptarget: prefs.allowSMBWithHighTemptarget,
            enableSMBHighBG: prefs.enableSMB_high_bg,
            enableSMBHighBGTarget: prefs.enableSMB_high_bg_target,
            maxSMBBasalMinutes: prefs.maxSMBBasalMinutes,
            maxUAMSMBBasalMinutes: prefs.maxUAMSMBBasalMinutes,
            enableUAM: prefs.enableUAM,
            maxDeltaBGthreshold: prefs.maxDeltaBGthreshold
        )
    }

    private func currentDynamicSettings() -> DynamicPresetSettings {
        let prefs = settingsManager.preferences
        return DynamicPresetSettings(
            useNewFormula: prefs.useNewFormula,
            sigmoid: prefs.sigmoid,
            adjustmentFactor: prefs.adjustmentFactor,
            adjustmentFactorSigmoid: prefs.adjustmentFactorSigmoid,
            weightPercentage: prefs.weightPercentage,
            tddAdjBasal: prefs.tddAdjBasal
        )
    }

    // MARK: - Public API

    func currentProfile() -> ProfilePreset? {
        guard let therapy = loadCurrentTherapySettings() else { return nil }

        return ProfilePreset(
            name: String(localized: "Current Profile", comment: "ProfilePresets: name for the current active profile"),
            basalProfile: therapy.basalProfile,
            insulinSensitivities: therapy.insulinSensitivities,
            carbRatios: therapy.carbRatios,
            bgTargets: therapy.bgTargets,
            smbSettings: currentSMBSettings(),
            dynamicSettings: currentDynamicSettings()
        )
    }

    func saveCurrentProfileAsPreset(name: String, icon: String, includeSMB: Bool, includeDynamic: Bool) -> ProfilePreset? {
        guard let therapy = loadCurrentTherapySettings() else { return nil }

        let preset = ProfilePreset(
            name: name,
            icon: icon,
            basalProfile: therapy.basalProfile,
            insulinSensitivities: therapy.insulinSensitivities,
            carbRatios: therapy.carbRatios,
            bgTargets: therapy.bgTargets,
            smbSettings: includeSMB ? currentSMBSettings() : nil,
            dynamicSettings: includeDynamic ? currentDynamicSettings() : nil
        )

        var existingPresets = presets()
        existingPresets.append(preset)
        savePresets(existingPresets)

        // Log preset creation in audit log
        auditStorage.logChange(
            category: "Profiles",
            subcategory: "Preset Created",
            settingName: "Profile Preset",
            settingKey: SettingsMetadataRegistry.ProfileKeys.presetCreated,
            oldValue: "(none)",
            newValue: name,
            unit: nil,
            note: nil,
            source: "manual"
        )

        return preset
    }

    func activatePreset(_ preset: ProfilePreset) -> Bool {
        guard !preset.basalProfile.isEmpty,
              !preset.insulinSensitivities.sensitivities.isEmpty,
              !preset.carbRatios.schedule.isEmpty,
              !preset.bgTargets.targets.isEmpty
        else {
            return false
        }

        // Skip re-activation if this preset is already the active one and settings match (gap 17.10)
        if activePresetId() == preset.id, settingsMatchPreset(preset) {
            return true
        }

        // Capture old therapy settings for audit log before overwriting
        let oldTherapy = loadCurrentTherapySettings()
        let previousPresetName = activePreset()?.name

        // Close any existing open profile preset run before activating a new one
        closeActiveRun()

        // Isolate this activation from any adjacent manual edits
        let presetSource = "preset:\(preset.name)"
        auditStorage.forceNewGroup()
        auditStorage.currentSource = presetSource

        storage.save(preset.basalProfile, as: OpenAPS.Settings.basalProfile)
        storage.save(preset.insulinSensitivities, as: OpenAPS.Settings.insulinSensitivities)
        storage.save(preset.carbRatios, as: OpenAPS.Settings.carbRatios)
        storage.save(preset.bgTargets, as: OpenAPS.Settings.bgTargets)

        // Log top-level preset activation event
        auditStorage.logChange(
            category: "Profiles",
            subcategory: "Preset Activation",
            settingName: "Active Profile",
            settingKey: SettingsMetadataRegistry.ProfileKeys.activeProfile,
            oldValue: previousPresetName ?? "(none)",
            newValue: preset.name,
            unit: nil,
            note: nil,
            source: presetSource
        )

        // Log individual therapy profile changes
        logTherapyChanges(from: oldTherapy, to: preset, source: presetSource)

        if preset.smbSettings != nil || preset.dynamicSettings != nil {
            var prefs = settingsManager.preferences

            if let smb = preset.smbSettings {
                prefs.enableSMBAlways = smb.enableSMBAlways
                prefs.enableSMBWithCOB = smb.enableSMBWithCOB
                prefs.enableSMBWithTemptarget = smb.enableSMBWithTemptarget
                prefs.enableSMBAfterCarbs = smb.enableSMBAfterCarbs
                prefs.allowSMBWithHighTemptarget = smb.allowSMBWithHighTemptarget
                prefs.enableSMB_high_bg = smb.enableSMBHighBG
                prefs.enableSMB_high_bg_target = smb.enableSMBHighBGTarget
                prefs.maxSMBBasalMinutes = smb.maxSMBBasalMinutes
                prefs.maxUAMSMBBasalMinutes = smb.maxUAMSMBBasalMinutes
                prefs.enableUAM = smb.enableUAM
                prefs.maxDeltaBGthreshold = smb.maxDeltaBGthreshold
            }

            if let dynamic = preset.dynamicSettings {
                prefs.useNewFormula = dynamic.useNewFormula
                prefs.sigmoid = dynamic.sigmoid
                prefs.adjustmentFactor = dynamic.adjustmentFactor
                prefs.adjustmentFactorSigmoid = dynamic.adjustmentFactorSigmoid
                prefs.weightPercentage = dynamic.weightPercentage
                prefs.tddAdjBasal = dynamic.tddAdjBasal
            }

            // currentSource is already set, so SettingsManager's Mirror-based logging
            // will tag the SMB/Dynamic preference changes with the preset source
            settingsManager.preferences = prefs
        }

        // Clear the source override now that all preset changes are logged
        auditStorage.currentSource = nil

        broadcaster.notify(BasalProfileObserver.self, on: .main) {
            $0.basalProfileDidChange(preset.basalProfile)
        }

        broadcaster.notify(BGTargetsObserver.self, on: .main) {
            $0.bgTargetsDidChange(preset.bgTargets)
        }

        broadcaster.notify(InsulinSensitivitiesObserver.self, on: .main) {
            $0.insulinSensitivitiesDidChange(preset.insulinSensitivities)
        }

        broadcaster.notify(CarbRatiosObserver.self, on: .main) {
            $0.carbRatiosDidChange(preset.carbRatios)
        }

        storage.save(preset.id, as: OpenAPS.Trio.activeProfilePresetId)

        // Create a new non-diverged run entry for this activation
        createRun(for: preset, isDiverted: false)

        Foundation.NotificationCenter.default.post(
            name: BaseProfilePresetStorage.profilePresetActivatedNotification,
            object: preset
        )

        return true
    }

    /// Logs individual therapy profile changes (basal, ISF, CR, targets) from old to new preset values.
    private func logTherapyChanges(from oldTherapy: CurrentTherapySettings?, to preset: ProfilePreset, source: String) {
        let oldBasal = oldTherapy?.basalProfile ?? []
        auditStorage.logTherapyProfileChange(
            subcategory: "Basal Rates",
            settingName: "Basal Profile",
            settingKey: "therapy.basalProfile",
            oldEntries: oldBasal.map { "\($0.start): \($0.rate) U/hr" },
            newEntries: preset.basalProfile.map { "\($0.start): \($0.rate) U/hr" },
            unit: "U/hr",
            source: source
        )

        let oldISF = oldTherapy?.insulinSensitivities.sensitivities ?? []
        auditStorage.logTherapyProfileChange(
            subcategory: "Insulin Sensitivity Factor",
            settingName: "ISF Profile",
            settingKey: "therapy.insulinSensitivities",
            oldEntries: oldISF.map { "\($0.start): \($0.sensitivity) mg/dL/U" },
            newEntries: preset.insulinSensitivities.sensitivities.map { "\($0.start): \($0.sensitivity) mg/dL/U" },
            unit: "mg/dL/U",
            source: source
        )

        let oldCR = oldTherapy?.carbRatios.schedule ?? []
        auditStorage.logTherapyProfileChange(
            subcategory: "Carb Ratio",
            settingName: "Carb Ratio Profile",
            settingKey: "therapy.carbRatios",
            oldEntries: oldCR.map { "\($0.start): \($0.ratio) g/U" },
            newEntries: preset.carbRatios.schedule.map { "\($0.start): \($0.ratio) g/U" },
            unit: "g/U",
            source: source
        )

        let oldTargets = oldTherapy?.bgTargets.targets ?? []
        auditStorage.logTherapyProfileChange(
            subcategory: "BG Targets",
            settingName: "BG Target Profile",
            settingKey: "therapy.bgTargets",
            oldEntries: oldTargets.map { "\($0.start): \($0.low)-\($0.high) mg/dL" },
            newEntries: preset.bgTargets.targets.map { "\($0.start): \($0.low)-\($0.high) mg/dL" },
            unit: "mg/dL",
            source: source
        )
    }

    // MARK: - CoreData run management

    /// Closes the currently open ProfilePresetRunStored (sets endDate) if one exists.
    private func closeActiveRun() {
        viewContext.perform {
            let fetchRequest: NSFetchRequest<ProfilePresetRunStored> = ProfilePresetRunStored.fetchRequest()
            fetchRequest.predicate = NSPredicate.activeProfilePresetRun
            fetchRequest.fetchLimit = 1

            do {
                let results = try self.viewContext.fetch(fetchRequest)
                if let activeRun = results.first {
                    activeRun.endDate = Date()
                    activeRun.isUploadedToNS = false
                    guard self.viewContext.hasChanges else { return }
                    try self.viewContext.save()
                }
            } catch let error as NSError {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to close active ProfilePresetRunStored: \(error.userInfo)"
                )
            }
        }
    }

    /// Creates a new ProfilePresetRunStored entry.
    private func createRun(for preset: ProfilePreset, isDiverted: Bool) {
        viewContext.perform {
            let newRun = ProfilePresetRunStored(context: self.viewContext)
            newRun.id = UUID()
            newRun.presetId = preset.id
            newRun.name = preset.name
            newRun.icon = preset.icon
            newRun.startDate = Date()
            newRun.endDate = nil
            newRun.isDiverted = isDiverted
            newRun.isUploadedToNS = false

            do {
                guard self.viewContext.hasChanges else { return }
                try self.viewContext.save()
            } catch let error as NSError {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to save ProfilePresetRunStored: \(error.userInfo)"
                )
            }
        }
    }

    /// Called when the active preset becomes diverged from current settings. Closes the matching run and opens a new diverged one.
    func openDivertedRun(for preset: ProfilePreset) {
        closeActiveRun()
        createRun(for: preset, isDiverted: true)
    }

    /// Called when the active preset is no longer diverged (settings were updated to match). Closes the diverged run and opens a fresh matching one.
    func closeDivertedRun(for preset: ProfilePreset) {
        closeActiveRun()
        createRun(for: preset, isDiverted: false)
    }

    /// Closes any open run without opening a new one (e.g. on deactivation).
    func deactivateCurrentRun() {
        closeActiveRun()
    }

    /// Fully deactivates the current profile preset: clears the stored active preset ID,
    /// closes any open run, and posts a notification with nil to update the UI.
    func deactivatePreset() {
        let previousPresetName = activePreset()?.name
        storage.remove(OpenAPS.Trio.activeProfilePresetId)
        closeActiveRun()

        // Log deactivation in audit log
        if let name = previousPresetName {
            auditStorage.forceNewGroup()
            auditStorage.logChange(
                category: "Profiles",
                subcategory: "Preset Deactivation",
                settingName: "Active Profile",
                settingKey: SettingsMetadataRegistry.ProfileKeys.activeProfile,
                oldValue: name,
                newValue: "(none)",
                unit: nil,
                note: nil,
                source: "preset:\(name)"
            )
        }

        Foundation.NotificationCenter.default.post(
            name: BaseProfilePresetStorage.profilePresetActivatedNotification,
            object: nil
        )
    }

    /// Closes all open runs (endDate == nil) that were left behind from a previous app session.
    /// Called at cold-start so that stale runs don't accumulate or get uploaded with incorrect durations.
    /// Uses `performAndWait` to ensure runs are closed before the caller proceeds.
    func closeStaleRuns() {
        viewContext.performAndWait {
            let fetchRequest: NSFetchRequest<ProfilePresetRunStored> = ProfilePresetRunStored.fetchRequest()
            fetchRequest.predicate = NSPredicate.activeProfilePresetRun

            do {
                let openRuns = try self.viewContext.fetch(fetchRequest)
                guard !openRuns.isEmpty else { return }
                for run in openRuns {
                    run.endDate = Date()
                    run.isUploadedToNS = false
                }
                guard self.viewContext.hasChanges else { return }
                try self.viewContext.save()
            } catch let error as NSError {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Cold-start recovery: failed to close stale ProfilePresetRunStored entries: \(error.userInfo)"
                )
            }
        }
    }

    // MARK: - Nightscout upload support

    func getProfilePresetRunsNotYetUploadedToNightscout() async throws -> [NightscoutTreatment] {
        let results = try await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: ProfilePresetRunStored.self,
            onContext: backgroundContext,
            predicate: NSPredicate.profilePresetRunsNotYetUploadedToNS,
            key: "startDate",
            ascending: false
        )

        return try await backgroundContext.perform {
            guard let fetchedRuns = results as? [ProfilePresetRunStored] else {
                throw CoreDataError.fetchError(function: #function, file: #file)
            }

            return fetchedRuns.map { run in
                let presetName = run.name ?? String(localized: "Profile Preset")
                let notesValue = run.isDiverted
                    ? String(localized: "Profile: \(presetName) (Diverted)")
                    : String(localized: "Profile: \(presetName)")
                var durationInMinutes = (run.endDate?.timeIntervalSince(run.startDate ?? Date()) ?? 1) / 60
                durationInMinutes = durationInMinutes < 1 ? 1 : durationInMinutes
                return NightscoutTreatment(
                    duration: Int(durationInMinutes),
                    rawDuration: nil,
                    rawRate: nil,
                    absolute: nil,
                    rate: nil,
                    eventType: .nsNote,
                    createdAt: run.startDate ?? Date(),
                    enteredBy: NightscoutTreatment.local,
                    bolus: nil,
                    insulin: nil,
                    notes: notesValue,
                    carbs: nil,
                    fat: nil,
                    protein: nil,
                    foodType: nil,
                    targetTop: nil,
                    targetBottom: nil,
                    glucoseType: nil,
                    glucose: nil,
                    units: nil,
                    id: run.id?.uuidString,
                    fpuID: nil
                )
            }
        }
    }

    func activePresetId() -> String? {
        storage.retrieve(OpenAPS.Trio.activeProfilePresetId, as: String.self)
    }

    func activePreset() -> ProfilePreset? {
        guard let id = activePresetId() else { return nil }
        return presets().first { $0.id == id }
    }

    func settingsMatchPreset(_ preset: ProfilePreset) -> Bool {
        guard let therapy = loadCurrentTherapySettings() else { return false }

        guard preset.basalProfile == therapy.basalProfile else { return false }
        guard preset.insulinSensitivities.sensitivities == therapy.insulinSensitivities.sensitivities else { return false }
        guard preset.carbRatios.schedule == therapy.carbRatios.schedule else { return false }
        guard preset.bgTargets.targets == therapy.bgTargets.targets else { return false }

        if let smbSettings = preset.smbSettings {
            guard smbSettings == currentSMBSettings() else { return false }
        }

        if let dynamicSettings = preset.dynamicSettings {
            guard dynamicSettings == currentDynamicSettings() else { return false }
        }

        return true
    }

    func deletePreset(id: String) {
        let presetName = presets().first(where: { $0.id == id })?.name
        // If the deleted preset is the active one, deactivate it first
        if activePresetId() == id {
            deactivatePreset()
        }
        var existingPresets = presets()
        existingPresets.removeAll { $0.id == id }
        savePresets(existingPresets)

        // Log preset deletion in audit log
        if let name = presetName {
            auditStorage.logChange(
                category: "Profiles",
                subcategory: "Preset Deleted",
                settingName: "Profile Preset",
                settingKey: SettingsMetadataRegistry.ProfileKeys.presetDeleted,
                oldValue: name,
                newValue: "(deleted)",
                unit: nil,
                note: nil,
                source: "manual"
            )
        }
    }

    func renamePreset(id: String, newName: String) {
        var existingPresets = presets()
        if let index = existingPresets.firstIndex(where: { $0.id == id }) {
            existingPresets[index].name = newName
            savePresets(existingPresets)

            // If the renamed preset is the active one, post a notification so HomeStateModel
            // updates the displayed name (gap 17.7)
            if activePresetId() == id {
                Foundation.NotificationCenter.default.post(
                    name: BaseProfilePresetStorage.profilePresetActivatedNotification,
                    object: existingPresets[index]
                )
            }
        }
    }

    func updatePresetToCurrentSettings(id: String) -> ProfilePreset? {
        guard let therapy = loadCurrentTherapySettings() else { return nil }
        var existingPresets = presets()
        guard let index = existingPresets.firstIndex(where: { $0.id == id }) else { return nil }

        let existing = existingPresets[index]
        existingPresets[index] = ProfilePreset(
            id: existing.id,
            name: existing.name,
            icon: existing.icon,
            basalProfile: therapy.basalProfile,
            insulinSensitivities: therapy.insulinSensitivities,
            carbRatios: therapy.carbRatios,
            bgTargets: therapy.bgTargets,
            smbSettings: existing.smbSettings != nil ? currentSMBSettings() : nil,
            dynamicSettings: existing.dynamicSettings != nil ? currentDynamicSettings() : nil
        )
        savePresets(existingPresets)

        // Log preset update in audit log (no therapy settings change, only the preset definition)
        auditStorage.logChange(
            category: "Profiles",
            subcategory: "Preset Update",
            settingName: "Profile Preset",
            settingKey: SettingsMetadataRegistry.ProfileKeys.presetUpdated,
            oldValue: "\(existing.name) (previous snapshot)",
            newValue: "\(existing.name) (updated to current settings)",
            unit: nil,
            note: nil,
            source: "preset-update:\(existing.name)"
        )

        // If this is the active preset, close the diverged run and open a matching one (gap 17.8)
        if activePresetId() == id {
            closeActiveRun()
            createRun(for: existingPresets[index], isDiverted: false)
        }

        return existingPresets[index]
    }
}
