import Foundation
import SwiftUI

/// Restore-from-backup during onboarding: the backup prefills the existing onboarding editors so
/// the user still reviews every screen; nothing persists until `saveOnboardingData()`, which then
/// applies the categories onboarding has no screens for.
extension Onboarding.StateModel {
    func loadOnboardingBackup(from url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            backupImportError = TrioBackupImportError(message: error.localizedDescription)
            return
        }

        guard let decoded = try? JSONCoding.decoder.decode(SettingsBackup.self, from: data) else {
            backupImportError = TrioBackupImportError(
                message: String(localized: "This file is not a Trio settings backup.")
            )
            return
        }

        importedBackup = decoded
        applyBackupToOnboardingState()
    }

    /// Prefills the onboarding editors from the backup — the same nearest-picker-value snapping
    /// the Nightscout import uses. Units are assigned first so the picker value arrays have the
    /// right size before any index is computed.
    func applyBackupToOnboardingState() {
        guard let backup = importedBackup else { return }

        if let importedUnits = backup.trioSettings?.units {
            units = importedUnits
        }

        if let therapy = backup.therapy {
            do {
                let normalized = try SettingsImportApplier.validateTherapy(therapy)

                if let targets = normalized.bgTargets {
                    targetItems = targets.targets.map { entry in
                        let timeIndex = closestIndex(for: TimeInterval(Double(entry.offset * 60)), in: targetTimeValues)
                        let lowIndex = closestIndex(for: entry.low, in: targetRateValues)
                        return TargetsEditor.Item(lowIndex: lowIndex, highIndex: lowIndex, timeIndex: timeIndex)
                    }
                    initialTargetItems = targetItems
                }

                if let basalProfile = normalized.basalProfile {
                    basalProfileItems = basalProfile.map { entry in
                        let timeIndex = closestIndex(for: TimeInterval(Double(entry.minutes * 60)), in: basalProfileTimeValues)
                        let rateIndex = closestIndex(for: entry.rate, in: basalProfileRateValues)
                        return BasalProfileEditor.Item(rateIndex: rateIndex, timeIndex: timeIndex)
                    }
                    initialBasalProfileItems = basalProfileItems
                }

                if let carbRatios = normalized.carbRatios {
                    carbRatioItems = carbRatios.schedule.map { entry in
                        let timeIndex = closestIndex(for: TimeInterval(Double(entry.offset * 60)), in: carbRatioTimeValues)
                        let rateIndex = closestIndex(for: entry.ratio, in: carbRatioRateValues)
                        return CarbRatioEditor.Item(rateIndex: rateIndex, timeIndex: timeIndex)
                    }
                    initialCarbRatioItems = carbRatioItems
                }

                if let sensitivities = normalized.insulinSensitivities {
                    isfItems = sensitivities.sensitivities.map { entry in
                        let timeIndex = closestIndex(for: TimeInterval(Double(entry.offset * 60)), in: isfTimeValues)
                        let rateIndex = closestIndex(for: entry.sensitivity, in: isfRateValues)
                        return ISFEditor.Item(rateIndex: rateIndex, timeIndex: timeIndex)
                    }
                    initialISFItems = isfItems
                }

                // The backup already carries therapy — suggest skipping the Nightscout import.
                if nightscoutImportOption == .noSelection {
                    nightscoutImportOption = .skipImport
                }
            } catch {
                backupImportError = TrioBackupImportError(
                    message: String(localized: "Therapy settings in the backup are invalid: \(error.localizedDescription)")
                )
            }
        }

        let providedSettings = PickerSettingsProvider.shared.settings
        if let pumpSettings = backup.pumpSettings {
            maxBolus = pumpSettings.maxBolus.clamp(to: providedSettings.maxBolus)
            maxBasal = pumpSettings.maxBasal.clamp(to: providedSettings.maxBasal)
        }

        if let preferences = backup.preferences {
            maxIOB = preferences.maxIOB.clamp(to: providedSettings.maxIOB)
            maxCOB = preferences.maxCOB.clamp(to: providedSettings.maxCOB)
            minimumSafetyThreshold = preferences.threshold_setting.clamp(to: providedSettings.threshold_setting)

            autosensMin = preferences.autosensMin.clamp(to: providedSettings.autosensMin)
            autosensMax = preferences.autosensMax.clamp(to: providedSettings.autosensMax)
            rewindResetsAutosens = preferences.rewindResetsAutosens

            enableSMBAlways = preferences.enableSMBAlways
            enableSMBWithCOB = preferences.enableSMBWithCOB
            enableSMBWithTempTarget = preferences.enableSMBWithTemptarget
            enableSMBAfterCarbs = preferences.enableSMBAfterCarbs
            enableSMBWithHighGlucoseTarget = preferences.enableSMB_high_bg
            highGlucoseTarget = preferences.enableSMB_high_bg_target.clamp(to: providedSettings.enableSMB_high_bg_target)
            allowSMBWithHighTempTarget = preferences.allowSMBWithHighTemptarget
            enableUAM = preferences.enableUAM
            maxSMBMinutes = preferences.maxSMBBasalMinutes.clamp(to: providedSettings.maxSMBBasalMinutes)
            maxUAMMinutes = preferences.maxUAMSMBBasalMinutes.clamp(to: providedSettings.maxUAMSMBBasalMinutes)
            maxDeltaGlucoseThreshold = preferences.maxDeltaBGthreshold.clamp(to: providedSettings.maxDeltaBGthreshold)

            highTempTargetRaisesSensitivity = preferences.highTemptargetRaisesSensitivity
            lowTempTargetLowersSensitivity = preferences.lowTemptargetLowersSensitivity
            sensitivityRaisesTarget = preferences.sensitivityRaisesTarget
            resistanceLowersTarget = preferences.resistanceLowersTarget
            halfBasalTarget = preferences.halfBasalExerciseTarget.clamp(to: providedSettings.halfBasalExerciseTarget)
        }

        if let credentials = backup.credentials {
            if let url = credentials.nightscoutURL, url.isNotEmpty {
                nightscoutUrl = url
            }
            if let secret = credentials.nightscoutSecret, secret.isNotEmpty {
                nightscoutSecret = secret
            }
        }
    }

    /// Applies backup categories onboarding has no review screens for. Runs from
    /// `saveOnboardingData()`: the preferences base merge runs before `applyToPreferences()`
    /// (whose reviewed values win for the fields onboarding covers); everything else runs after
    /// the onboarding values were persisted.
    func applyBackupPreferencesBase() {
        guard let backup = importedBackup, let importedPreferences = backup.preferences else { return }

        // Full algorithm/devices/features merge; the onboarding-reviewed subset is overridden
        // right after by applyToPreferences().
        let merged = SettingsImportApplier.merge(
            SettingsImportApplier.preferencesFields,
            current: settingsManager.preferences,
            imported: importedPreferences,
            categories: [.devices, .algorithm, .features, .therapy],
            units: units
        )
        settingsManager.preferences = merged.result
    }

    func applyRemainingBackupCategories() {
        guard let backup = importedBackup else { return }

        let currentUnits = settingsManager.settings.units

        if let importedTrio = backup.trioSettings {
            let current = settingsManager.settings
            let mergeOutcome = SettingsImportApplier.merge(
                SettingsImportApplier.trioSettingsFields,
                current: current,
                imported: importedTrio,
                categories: [.devices, .features, .notifications, .services],
                units: currentUnits
            )
            var merged = mergeOutcome.result

            let adoptsCGMState = importBackupDevicePairing && backup.devices?.cgmState != nil && importedTrio.cgm == .plugin
            if merged.cgm == .plugin, !adoptsCGMState {
                // A plugin CGM without its adopted state would be a dead glucose source.
                merged.cgm = current.cgm
                merged.cgmPluginIdentifier = current.cgmPluginIdentifier
            }

            // Onboarding's own Nightscout decisions win over the backup.
            if nightscoutSetupOption == .setupNightscout {
                merged.isUploadEnabled = isUploadEnabled
                merged.uploadGlucose = uploadGlucose
            }
            merged.units = units

            settingsManager.settings = merged

            let newCgm = merged.cgm
            let newCgmPluginId = merged.cgmPluginIdentifier
            if adoptsCGMState, let cgmStateBase64 = backup.devices?.cgmState,
               let rawValue = SettingsBackup.decodeManagerState(cgmStateBase64)
            {
                _ = fetchGlucoseManager.adoptCGMManagerState(rawValue, cgmGlucosePluginId: newCgmPluginId)
            } else if newCgm != current.cgm || newCgmPluginId != current.cgmPluginIdentifier {
                fetchGlucoseManager.updateGlucoseSource(cgmGlucoseSourceType: newCgm, cgmGlucosePluginId: newCgmPluginId)
            }
        }

        if importBackupDevicePairing, let pumpStateBase64 = backup.devices?.pumpState,
           let rawValue = SettingsBackup.decodeManagerState(pumpStateBase64)
        {
            _ = deviceManager.adoptPumpManager(fromRawValue: rawValue)
        }

        if let userDefaultsValues = backup.userDefaults {
            if let colorScheme = userDefaultsValues.colorSchemePreference {
                UserDefaults.standard.set(colorScheme, forKey: "colorSchemePreference")
            }
            if let remoteControlEnabled = userDefaultsValues.isTrioRemoteControlEnabled {
                UserDefaults.standard.set(remoteControlEnabled, forKey: "isTrioRemoteControlEnabled")
            }
        }

        if importBackupCredentials, let credentials = backup.credentials {
            if let url = credentials.nightscoutURL, url.isNotEmpty {
                keychain.setValue(url, forKey: NightscoutConfig.Config.urlKey)
            }
            if let secret = credentials.nightscoutSecret, secret.isNotEmpty {
                keychain.setValue(secret, forKey: NightscoutConfig.Config.secretKey)
            }
            if let sharedSecret = credentials.remoteControlSharedSecret {
                UserDefaults.standard.set(sharedSecret, forKey: "trioRemoteControlSharedSecret")
            }
        }

        if let presets = backup.presets {
            Task {
                await SettingsBackupPresetApplier.apply(
                    presets,
                    strategy: .replaceSameNamed,
                    tempTargetsStorage: tempTargetsStorage,
                    overrideStorage: overrideStorage,
                    context: CoreDataStack.shared.persistentContainer.viewContext
                )
            }
        }

        if let importedProfilePresets = backup.profilePresets, importedProfilePresets.isNotEmpty {
            let existing = fileStorage.retrieve(OpenAPS.Trio.profilePresets, as: [ProfilePreset].self) ?? []
            let mergeResult = SettingsImportApplier.mergeProfilePresets(
                existing: existing,
                imported: importedProfilePresets,
                activeName: nil,
                strategy: .replaceSameNamed
            )
            fileStorage.save(mergeResult.result, as: OpenAPS.Trio.profilePresets)
        }
    }
}

struct TrioBackupImportError: Identifiable {
    let id = UUID()
    let message: String
}

enum TrioBackupImportOption: String, Equatable, CaseIterable, Identifiable {
    case useImport
    case skipImport
    case noSelection

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .useImport:
            return String(localized: "Restore from Trio Backup")
        case .skipImport:
            return String(localized: "Set Up Manually")
        case .noSelection:
            return ""
        }
    }
}
