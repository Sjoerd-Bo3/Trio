import Foundation
import Observation

/// Shared coordinator that manages the divergence-save-prompt flow when switching
/// between profile presets. Used by both `AdjustmentsStateModel` and `ProfilePresetsStateModel`
/// to avoid duplicating the same state machine logic (DRY).
///
/// **Flow:**
/// 1. `requestSwitch(to:)` checks if the current preset is diverged.
/// 2. If diverged → stores the pending preset and shows the divergence prompt.
/// 3. If not diverged → proceeds directly to the activation confirmation.
/// 4. From the prompt the user can: Update current + switch, Save as new + switch, Discard + switch, or Cancel.
@Observable final class PresetSwitchCoordinator {
    // MARK: - State

    /// Whether the "Unsaved Changes" confirmation dialog is visible.
    var showingDivergenceSavePrompt: Bool = false

    /// The preset the user wants to switch to (stored while awaiting the prompt decision).
    var pendingPresetSwitch: ProfilePreset?

    // MARK: - Callbacks

    /// Called when the coordinator determines a switch should proceed through the
    /// normal activation confirmation flow (either directly or after update/discard).
    var onProceedWithSwitch: ((ProfilePreset) -> Void)?

    /// Called when the user chooses "Update" in the divergence prompt.
    /// The implementation should persist the current settings into the active preset.
    var onUpdateCurrentPreset: (() -> Void)?

    /// Called when the user chooses "Save as New Preset" in the divergence prompt.
    /// The implementation should save the current settings as a brand-new preset.
    var onSaveAsNewPreset: (() -> Void)?

    // MARK: - Actions

    /// Initiates a preset switch. Shows the divergence prompt if the active preset
    /// has unsaved changes; otherwise proceeds directly.
    ///
    /// - Parameters:
    ///   - preset: The preset the user wants to activate.
    ///   - isDiverged: Whether the currently active preset's settings have been modified.
    ///   - hasActivePreset: Whether there is an active preset at all.
    func requestSwitch(to preset: ProfilePreset, isDiverged: Bool, hasActivePreset: Bool) {
        if isDiverged, hasActivePreset {
            pendingPresetSwitch = preset
            showingDivergenceSavePrompt = true
        } else {
            onProceedWithSwitch?(preset)
        }
    }

    /// Updates the current active preset with diverged settings, then switches to the pending preset.
    func updateCurrentPresetAndSwitch() {
        guard let pending = pendingPresetSwitch else { return }
        onUpdateCurrentPreset?()
        proceedWithPendingSwitch(pending)
    }

    /// Saves the diverged settings as a new preset, then switches to the pending preset.
    func saveAsNewPresetAndSwitch() {
        guard let pending = pendingPresetSwitch else { return }
        onSaveAsNewPreset?()
        proceedWithPendingSwitch(pending)
    }

    /// Discards the diverged changes and switches directly to the pending preset.
    func discardChangesAndSwitch() {
        guard let pending = pendingPresetSwitch else { return }
        proceedWithPendingSwitch(pending)
    }

    /// Cancels the pending preset switch entirely.
    /// - Note: The `showingDivergenceSavePrompt` binding is automatically dismissed by SwiftUI
    ///   when the cancel-role button is tapped in a `.confirmationDialog`.
    func cancelPendingSwitch() {
        pendingPresetSwitch = nil
    }

    // MARK: - Private

    /// Clears the pending state and triggers the normal activation confirmation.
    private func proceedWithPendingSwitch(_ preset: ProfilePreset) {
        pendingPresetSwitch = nil
        onProceedWithSwitch?(preset)
    }
}
