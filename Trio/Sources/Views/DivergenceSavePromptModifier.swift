import SwiftUI

/// A reusable `ViewModifier` that attaches the "Unsaved Changes" divergence save prompt
/// confirmation dialog to a view. This eliminates duplication of the same dialog in
/// `AdjustmentsRootView` and `ProfilePresetsRootView`.
struct DivergenceSavePromptModifier: ViewModifier {
    @Bindable var coordinator: PresetSwitchCoordinator

    /// The display name of the currently active preset (shown in the prompt messages).
    /// When `nil`, falls back to a localised "Unknown Preset" string.
    let activePresetName: String?

    private static let unknownPreset = String(
        localized: "Unknown Preset",
        comment: "DivergenceSavePrompt: fallback name when active preset name is unavailable"
    )

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                Text(
                    "Unsaved Changes",
                    comment: "DivergenceSavePrompt: title for divergence save prompt when switching presets"
                ),
                isPresented: $coordinator.showingDivergenceSavePrompt,
                titleVisibility: .visible
            ) {
                Button(String(
                    localized: "Update '\(resolvedName)'",
                    comment: "DivergenceSavePrompt: update existing preset with current settings before switching"
                )) {
                    coordinator.updateCurrentPresetAndSwitch()
                }
                Button(String(
                    localized: "Save as New Preset",
                    comment: "DivergenceSavePrompt: save diverged settings as a new preset before switching"
                )) {
                    coordinator.saveAsNewPresetAndSwitch()
                }
                Button(String(
                    localized: "Discard Changes",
                    comment: "DivergenceSavePrompt: discard diverged settings and switch preset"
                ), role: .destructive) {
                    coordinator.discardChangesAndSwitch()
                }
                Button(String(
                    localized: "Cancel",
                    comment: "DivergenceSavePrompt: cancel button"
                ), role: .cancel) {
                    coordinator.cancelPendingSwitch()
                }
            } message: {
                Text(
                    "Your current therapy settings have been modified since '\(resolvedName)' was activated. What would you like to do with these changes?",
                    comment: "DivergenceSavePrompt: message explaining diverged settings before preset switch"
                )
            }
    }

    /// Returns the active preset name, falling back to a localised "Unknown Preset" string
    /// to prevent blank button labels.
    private var resolvedName: String {
        if let name = activePresetName, !name.isEmpty {
            return name
        }
        return Self.unknownPreset
    }
}

extension View {
    /// Attaches the divergence save prompt for profile preset switching.
    func divergenceSavePrompt(coordinator: PresetSwitchCoordinator, activePresetName: String?) -> some View {
        modifier(DivergenceSavePromptModifier(coordinator: coordinator, activePresetName: activePresetName))
    }
}
