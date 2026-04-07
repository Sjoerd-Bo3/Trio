import Foundation
import Observation
import Swinject

extension ProfilePresets {
    @Observable final class StateModel: BaseStateModel<Provider> {
        var presets: [ProfilePreset] = []
        var newPresetName: String = ""
        var newPresetIcon: String = ProfilePreset.defaultIcon
        var showingSaveDialog: Bool = false
        var showingActivateConfirmation: Bool = false
        var showingSaveError: Bool = false
        var showingActivateError: Bool = false
        var selectedPreset: ProfilePreset?
        var units: GlucoseUnits = .mgdL
        var activePreset: ProfilePreset?
        var isProfileDiverged: Bool = false
        let presetSwitchCoordinator = PresetSwitchCoordinator()

        // Percentage adjustment
        var showingAdjustmentSheet: Bool = false
        var adjustmentPercentage: Int = 100
        var adjustmentPresetName: String = ""
        var adjustmentSourcePreset: ProfilePreset?

        // Detail view
        var detailPreset: ProfilePreset?

        // Comparison
        var showingComparisonSheet: Bool = false
        var comparisonPresetA: ProfilePreset?
        var comparisonPresetB: ProfilePreset?
        var currentProfile: ProfilePreset?

        // Save preview
        var savePreviewProfile: ProfilePreset?

        // Rename
        var showingRenameDialog: Bool = false
        var presetToRename: ProfilePreset?
        var renameNewName: String = ""

        override func subscribe() {
            units = settingsManager.settings.units
            presets = provider.loadPresets()
            currentProfile = provider.loadCurrentProfile()
            activePreset = provider.loadActivePreset()
            refreshProfileDivergence()
            configurePresetSwitchCoordinator()
        }

        func refreshCurrentProfile() {
            currentProfile = provider.loadCurrentProfile()
        }

        func refreshProfileDivergence() {
            guard let preset = activePreset else {
                isProfileDiverged = false
                return
            }
            isProfileDiverged = !provider.settingsMatchPreset(preset)
        }

        func saveCurrentProfileAsPreset() {
            guard !newPresetName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            if let preset = provider.saveCurrentAsPreset(
                name: newPresetName.trimmingCharacters(in: .whitespaces),
                icon: newPresetIcon,
                includeSMB: true,
                includeDynamic: true
            ) {
                presets.append(preset)
            } else {
                showingSaveError = true
            }
            newPresetName = ""
            newPresetIcon = ProfilePreset.defaultIcon
            savePreviewProfile = nil
        }

        /// Wires the shared `PresetSwitchCoordinator` callbacks to this state model's logic.
        private func configurePresetSwitchCoordinator() {
            presetSwitchCoordinator.onProceedWithSwitch = { [weak self] preset in
                self?.selectedPreset = preset
                self?.showingActivateConfirmation = true
            }
            presetSwitchCoordinator.onUpdateCurrentPreset = { [weak self] in
                guard let self, let active = self.activePreset else { return }
                self.updatePresetToCurrentSettings(active)
            }
            presetSwitchCoordinator.onSaveAsNewPreset = { [weak self] in
                self?.showingSaveDialog = true
            }
        }

        /// Initiates a profile preset switch via the shared coordinator.
        func requestPresetSwitch(_ preset: ProfilePreset) {
            presetSwitchCoordinator.requestSwitch(
                to: preset,
                isDiverged: isProfileDiverged,
                hasActivePreset: activePreset != nil
            )
        }

        func activatePreset(_ preset: ProfilePreset) {
            if !provider.activatePreset(preset) {
                showingActivateError = true
            } else {
                activePreset = preset
                isProfileDiverged = false
            }
        }

        func deletePreset(_ preset: ProfilePreset) {
            let wasActive = activePreset?.id == preset.id
            provider.deletePreset(id: preset.id)
            presets.removeAll { $0.id == preset.id }
            if wasActive {
                activePreset = nil
                isProfileDiverged = false
            }
        }

        func beginRename(for preset: ProfilePreset) {
            presetToRename = preset
            renameNewName = preset.name
            showingRenameDialog = true
        }

        func confirmRename() {
            guard let preset = presetToRename else { return }
            let trimmed = renameNewName.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return }

            provider.renamePreset(id: preset.id, newName: trimmed)
            if let index = presets.firstIndex(where: { $0.id == preset.id }) {
                presets[index].name = trimmed
            }
            // activePreset is a separate copy, update it independently
            if activePreset?.id == preset.id {
                activePreset?.name = trimmed
            }
            presetToRename = nil
            renameNewName = ""
        }

        func updatePresetToCurrentSettings(_ preset: ProfilePreset) {
            guard let updated = provider.updatePresetToCurrentSettings(id: preset.id) else { return }
            if let index = presets.firstIndex(where: { $0.id == preset.id }) {
                presets[index] = updated
            }
            if activePreset?.id == preset.id {
                activePreset = updated
                isProfileDiverged = false
            }
        }

        func formattedBasalTotal(_ preset: ProfilePreset) -> String {
            String(format: "%.2f", NSDecimalNumber(decimal: preset.totalDailyBasal).doubleValue)
        }

        // MARK: - Percentage Adjustment

        func beginAdjustment(for preset: ProfilePreset) {
            adjustmentSourcePreset = preset
            adjustmentPercentage = 100
            adjustmentPresetName = "\(preset.name) (Adjusted)"
            showingAdjustmentSheet = true
        }

        func createAdjustedPreset() {
            guard let source = adjustmentSourcePreset else { return }
            let trimmedName = adjustmentPresetName.trimmingCharacters(in: .whitespaces)
            guard !trimmedName.isEmpty else { return }

            guard let adjusted = source.scaled(by: adjustmentPercentage, name: trimmedName) else { return }
            provider.savePreset(adjusted)
            presets.append(adjusted)

            adjustmentSourcePreset = nil
            adjustmentPresetName = ""
            adjustmentPercentage = 100
        }

        // MARK: - Save Preview

        func prepareSavePreview() {
            savePreviewProfile = provider.loadCurrentProfile()
        }

        // MARK: - Comparison

        var defaultComparisonPresetA: ProfilePreset? {
            comparisonPresetA ?? presets.first
        }

        var defaultComparisonPresetB: ProfilePreset? {
            comparisonPresetB ?? (presets.count > 1 ? presets[1] : currentProfile)
        }

        func beginComparison(presetA: ProfilePreset, presetB: ProfilePreset?) {
            comparisonPresetA = presetA
            comparisonPresetB = presetB ?? currentProfile
            showingComparisonSheet = true
        }

        // MARK: - Formatting

        func formatDecimal(_ value: Decimal, decimals: Int = 1) -> String {
            String(format: "%.\(decimals)f", NSDecimalNumber(decimal: value).doubleValue)
        }

        func formatGlucose(_ value: Decimal) -> String {
            let displayValue = units == .mmolL ? value.asMmolL : value
            return units == .mmolL
                ? formatDecimal(displayValue, decimals: 1)
                : formatDecimal(displayValue, decimals: 0)
        }

        func dynamicISFType(for settings: DynamicPresetSettings) -> String {
            if settings.useNewFormula {
                return settings.sigmoid
                    ? String(localized: "Sigmoid", comment: "ProfilePresets: sigmoid dynamic ISF type")
                    : String(localized: "Logarithmic", comment: "ProfilePresets: logarithmic dynamic ISF type")
            }
            return String(localized: "Disabled", comment: "ProfilePresets: disabled dynamic ISF type")
        }
    }
}
