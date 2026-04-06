import Foundation
import Observation
import Swinject

extension ProfilePresets {
    @Observable final class StateModel: BaseStateModel<Provider> {
        var presets: [ProfilePreset] = []
        var newPresetName: String = ""
        var showingSaveDialog: Bool = false
        var showingActivateConfirmation: Bool = false
        var showingSaveError: Bool = false
        var showingActivateError: Bool = false
        var selectedPreset: ProfilePreset?
        var units: GlucoseUnits = .mgdL

        // Save options
        var includeSMBSettings: Bool = false
        var includeDynamicSettings: Bool = false

        // Percentage adjustment
        var showingAdjustmentSheet: Bool = false
        var adjustmentPercentage: Int = 100
        var adjustmentPresetName: String = ""
        var adjustmentSourcePreset: ProfilePreset?

        override func subscribe() {
            units = settingsManager.settings.units
            presets = provider.loadPresets()
        }

        func saveCurrentProfileAsPreset() {
            guard !newPresetName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            if let preset = provider.saveCurrentAsPreset(
                name: newPresetName.trimmingCharacters(in: .whitespaces),
                includeSMB: includeSMBSettings,
                includeDynamic: includeDynamicSettings
            ) {
                presets.append(preset)
            } else {
                showingSaveError = true
            }
            newPresetName = ""
            includeSMBSettings = false
            includeDynamicSettings = false
        }

        func activatePreset(_ preset: ProfilePreset) {
            if !provider.activatePreset(preset) {
                showingActivateError = true
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
    }
}
