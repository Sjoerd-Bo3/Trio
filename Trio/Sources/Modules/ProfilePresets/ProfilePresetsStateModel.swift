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

        override func subscribe() {
            units = settingsManager.settings.units
            presets = provider.loadPresets()
        }

        func saveCurrentProfileAsPreset() {
            guard !newPresetName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            if let preset = provider.saveCurrentAsPreset(name: newPresetName.trimmingCharacters(in: .whitespaces)) {
                presets.append(preset)
            } else {
                showingSaveError = true
            }
            newPresetName = ""
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
            let total = preset.basalProfile.enumerated().reduce(Decimal.zero) { result, entry in
                let current = entry.element
                let nextMinutes: Int
                if entry.offset + 1 < preset.basalProfile.count {
                    nextMinutes = preset.basalProfile[entry.offset + 1].minutes
                } else {
                    nextMinutes = 24 * 60
                }
                let durationHours = Decimal(nextMinutes - current.minutes) / 60
                return result + current.rate * durationHours
            }
            return String(format: "%.2f", NSDecimalNumber(decimal: total).doubleValue)
        }
    }
}
