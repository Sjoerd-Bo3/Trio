import Foundation
import SwiftUI

enum BackupRestoreOption: Equatable {
    /// Restore from a backup file.
    case restore
    case restoreICloud
    case startFresh
    case noSelection
}

/// Restore from a backup during onboarding: the backup is applied once through the restore engine
/// (journaled, Open Loop, nothing sent to a pump), and the onboarding editors are then prefilled from the
/// restored settings so the user still reviews every screen.
extension Onboarding.StateModel {
    @MainActor func chooseBackupRestoreOption(_ option: BackupRestoreOption) {
        // A restore that has been applied cannot be taken back by choosing another option.
        guard !backupWasRestored, !backupRestoreInProgress else { return }
        if option != backupRestoreOption {
            pendingBackup = nil
            pendingBackupWarnings = []
            pendingBackupOverview = nil
            sensitiveModel.reset()
        }
        backupRestoreOption = option
    }

    /// A backup picked from the iCloud list; applied only after the user confirms.
    @MainActor func selectCloudBackup(_ backup: TrioSettingsBackup) {
        guard !backupWasRestored, !backupRestoreInProgress else { return }
        pendingBackup = backup
        pendingBackupWarnings = []
        pendingBackupOverview = nil
        sensitiveModel.reset()
        Task { @MainActor in
            pendingBackupOverview = await BackupService.shared.changeOverview(for: backup, onboarding: true)
        }
    }

    @MainActor func loadBackupFile(from url: URL) async {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let opened = try BackupFileService.open(url: url)
            pendingBackup = opened.snapshot
            pendingBackupWarnings = opened.warnings
            sensitiveModel.reset(tier: opened.sensitive)
            pendingBackupOverview = await BackupService.shared.changeOverview(for: opened.snapshot, onboarding: true)
            backupRestoreError = nil
        } catch {
            if (error as? CocoaError)?.code != .userCancelled { backupRestoreError = error.localizedDescription }
        }
    }

    /// `adoptionAccepted` is true only when the user accepted the final dialog naming the pump to adopt.
    @MainActor func applyPendingBackup(adoptionAccepted: Bool = false) async {
        guard let backup = pendingBackup, !backupRestoreInProgress, appliedBackupID != backup.id else { return }
        backupRestoreInProgress = true
        defer { backupRestoreInProgress = false }
        do {
            let selection = sensitiveModel.selection(allowsPairing: true, adoptionAccepted: adoptionAccepted)
            let report = try await BackupService.shared.restoreDuringOnboarding(backup, sensitive: selection)
            restoreWarnings = report.warnings
            appliedBackupID = backup.id
            prefillFromRestoredSettings()
        } catch {
            backupRestoreError = String(localized: "Restore stopped. No pump settings were sent.") + "\n\n" +
                error.localizedDescription
        }
    }

    /// Prefills the onboarding editors from the settings the restore just wrote. Units are assigned first so
    /// the picker value arrays have the right size before any index is computed.
    @MainActor func prefillFromRestoredSettings() {
        let restoredSettings = settingsManager.settings
        let restoredPreferences = settingsManager.preferences
        let providedSettings = PickerSettingsProvider.shared.settings

        units = restoredSettings.units
        fetchExistingTherapySettingsFromFile()
        fetchExistingDeliveryLimtisFromFile()

        autosensMin = restoredPreferences.autosensMin.clamp(to: providedSettings.autosensMin)
        autosensMax = restoredPreferences.autosensMax.clamp(to: providedSettings.autosensMax)
        rewindResetsAutosens = restoredPreferences.rewindResetsAutosens

        enableSMBAlways = restoredPreferences.enableSMBAlways
        enableSMBWithCOB = restoredPreferences.enableSMBWithCOB
        enableSMBWithTempTarget = restoredPreferences.enableSMBWithTemptarget
        enableSMBAfterCarbs = restoredPreferences.enableSMBAfterCarbs
        enableSMBWithHighGlucoseTarget = restoredPreferences.enableSMB_high_bg
        highGlucoseTarget = restoredPreferences.enableSMB_high_bg_target.clamp(to: providedSettings.enableSMB_high_bg_target)
        allowSMBWithHighTempTarget = restoredPreferences.allowSMBWithHighTemptarget
        enableUAM = restoredPreferences.enableUAM
        maxSMBMinutes = restoredPreferences.maxSMBBasalMinutes.clamp(to: providedSettings.maxSMBBasalMinutes)
        maxUAMMinutes = restoredPreferences.maxUAMSMBBasalMinutes.clamp(to: providedSettings.maxUAMSMBBasalMinutes)
        maxDeltaGlucoseThreshold = restoredPreferences.maxDeltaBGthreshold.clamp(to: providedSettings.maxDeltaBGthreshold)

        highTempTargetRaisesSensitivity = restoredPreferences.highTemptargetRaisesSensitivity
        lowTempTargetLowersSensitivity = restoredPreferences.lowTemptargetLowersSensitivity
        sensitivityRaisesTarget = restoredPreferences.sensitivityRaisesTarget
        resistanceLowersTarget = restoredPreferences.resistanceLowersTarget
        halfBasalTarget = restoredPreferences.halfBasalExerciseTarget.clamp(to: providedSettings.halfBasalExerciseTarget)
    }
}
