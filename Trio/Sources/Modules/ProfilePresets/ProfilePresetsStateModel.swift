import Foundation
import Observation
import Swinject

extension ProfilePresets {
    @Observable final class StateModel: BaseStateModel<Provider> {
        var presets: [ProfilePreset] = []
        var newPresetName: String = ""
        var newPresetIcon: String = "person.crop.circle"
        var showingSaveDialog: Bool = false
        var showingActivateConfirmation: Bool = false
        var showingSaveError: Bool = false
        var showingActivateError: Bool = false
        var selectedPreset: ProfilePreset?
        var units: GlucoseUnits = .mgdL
        var activePreset: ProfilePreset?

        // Save options
        var includeSMBSettings: Bool = false
        var includeDynamicSettings: Bool = false

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

        override func subscribe() {
            units = settingsManager.settings.units
            presets = provider.loadPresets()
            currentProfile = provider.loadCurrentProfile()
            activePreset = provider.loadActivePreset()
        }

        func refreshCurrentProfile() {
            currentProfile = provider.loadCurrentProfile()
        }

        func saveCurrentProfileAsPreset() {
            guard !newPresetName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            if let preset = provider.saveCurrentAsPreset(
                name: newPresetName.trimmingCharacters(in: .whitespaces),
                icon: newPresetIcon,
                includeSMB: includeSMBSettings,
                includeDynamic: includeDynamicSettings
            ) {
                presets.append(preset)
            } else {
                showingSaveError = true
            }
            newPresetName = ""
            newPresetIcon = "person.crop.circle"
            includeSMBSettings = false
            includeDynamicSettings = false
            savePreviewProfile = nil
        }

        func activatePreset(_ preset: ProfilePreset) {
            if !provider.activatePreset(preset) {
                showingActivateError = true
            } else {
                activePreset = preset
            }
        }

        func deletePreset(_ preset: ProfilePreset) {
            provider.deletePreset(id: preset.id)
            presets.removeAll { $0.id == preset.id }
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

            let adjusted = source.scaled(by: adjustmentPercentage, name: trimmedName)
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
            comparisonPresetB ?? (presets.count > 1 ? presets[1] : nil)
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
