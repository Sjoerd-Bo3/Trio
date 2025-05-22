import Combine
import Foundation
import SwiftUI
import Swinject

extension DynamicSettings {
    final class GraphViewModel: ObservableObject, Injectable, SettingsObserver, PreferencesObserver {
        @Published var parameters: ISFParameters
        @Published var showLogarithmicCurve: Bool = true
        @Published var showSigmoidCurve: Bool = true
        @Published var showPlayground: Bool = false

        private let settingsManager: SettingsManager
        private let glucoseStorage: GlucoseStorage

        @Injected() private var storage: FileStorage!
        @Injected() private var broadcaster: Broadcaster!

        var units: GlucoseUnits {
            settingsManager.settings.units
        }

        var currentGlucose: Double? {
            // Get current glucose from storage and convert to mg/dL for calculations
            guard let latestGlucose = getCurrentGlucoseValue() else { return nil }
            return Double(latestGlucose)
        }

        init(settingsManager: SettingsManager, glucoseStorage: GlucoseStorage, resolver: Resolver) {
            self.settingsManager = settingsManager
            self.glucoseStorage = glucoseStorage

            // Initialize parameters from settings
            parameters = Self.loadParametersFromSettings(settingsManager)

            // Inject dependencies
            injectServices(resolver)

            // Update parameters with therapy settings
            updateParametersFromStorage()

            // Subscribe to settings changes
            setupSubscriptions()
        }

        deinit {
            broadcaster.unregister(SettingsObserver.self, observer: self)
            broadcaster.unregister(PreferencesObserver.self, observer: self)
        }

        private static func loadParametersFromSettings(_ settingsManager: SettingsManager) -> ISFParameters {
            var parameters = ISFParameters()

            // Load from preferences
            let prefs = settingsManager.preferences

            // Set active formula based on current dynamic sensitivity settings
            if prefs.useNewFormula {
                parameters.activeFormula = prefs.sigmoid ? .sigmoid : .logarithmic
            } else {
                parameters.activeFormula = .disabled
            }

            // Load adjustment factors
            parameters.logarithmicAdjustmentFactor = Double(prefs.adjustmentFactor)
            parameters.sigmoidAdjustmentFactor = Double(prefs.adjustmentFactorSigmoid)

            // Load TDD weighting
            parameters.ratio24hTo2w = Double(prefs.weightPercentage)

            // Default ISF values (will be updated later when storage is available)
            parameters.logarithmicProfileISF = 50.0
            parameters.sigmoidProfileISF = 50.0

            // Default target BG (will be updated later when storage is available)
            parameters.sigmoidTargetBG = 100.0

            // Load autosens settings
            parameters.logarithmicAutosensMin = Double(prefs.autosensMin)
            parameters.logarithmicAutosensMax = Double(prefs.autosensMax)
            parameters.sigmoidAutosensMin = Double(prefs.autosensMin)
            parameters.sigmoidAutosensMax = Double(prefs.autosensMax)

            // Load insulin peak time from preferences
            switch settingsManager.preferences.curve {
            case .rapidActing:
                parameters.insulinPeakTime = 75
            case .ultraRapid:
                parameters.insulinPeakTime = 55
            case .bilinear:
                parameters.insulinPeakTime = 75 // Default for bilinear
            }

            return parameters
        }

        private func setupSubscriptions() {
            // Register as observer for settings and preferences changes
            broadcaster.register(SettingsObserver.self, observer: self)
            broadcaster.register(PreferencesObserver.self, observer: self)
        }

        // MARK: - Observer Protocol Methods

        func settingsDidChange(_: TrioSettings) {
            DispatchQueue.main.async { [weak self] in
                self?.updateParametersFromStorage()
            }
        }

        func preferencesDidChange(_: Preferences) {
            DispatchQueue.main.async { [weak self] in
                self?.updateParametersFromSettings()
            }
        }

        private func updateParametersFromSettings() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.parameters = Self.loadParametersFromSettings(self.settingsManager)
                self.updateParametersFromStorage()
            }
        }

        private func updateParametersFromStorage() {
            // Load ISF from therapy settings (stored internally as mg/dL)
            let insulinSensitivities = loadInsulinSensitivities()
            if let firstISF = insulinSensitivities.sensitivities.first {
                let profileISF = Double(firstISF.sensitivity)
                parameters.logarithmicProfileISF = profileISF
                parameters.sigmoidProfileISF = profileISF
            }

            // Load target BG for sigmoid (stored internally as mg/dL)
            let bgTargets = loadBGTargets()
            if let firstTarget = bgTargets.targets.first {
                let targetMgdL = Double(firstTarget.low + firstTarget.high) / 2.0
                parameters.sigmoidTargetBG = targetMgdL
            }
        }

        private func getCurrentGlucoseValue() -> Decimal? {
            // This should be implemented to get the latest glucose value from storage
            // For now, return a default value
            100 // mg/dL
        }

        func saveParameters(_ newParameters: ISFParameters) {
            // Update the parameters
            parameters = newParameters

            // Save to settings
            var preferences = settingsManager.preferences

            // Update dynamic sensitivity settings
            switch newParameters.activeFormula {
            case .disabled:
                preferences.useNewFormula = false
                preferences.sigmoid = false
            case .logarithmic:
                preferences.useNewFormula = true
                preferences.sigmoid = false
            case .sigmoid:
                preferences.useNewFormula = true
                preferences.sigmoid = true
            }

            // Update adjustment factors
            preferences.adjustmentFactor = Decimal(newParameters.logarithmicAdjustmentFactor)
            preferences.adjustmentFactorSigmoid = Decimal(newParameters.sigmoidAdjustmentFactor)

            // Update TDD weighting
            preferences.weightPercentage = Decimal(newParameters.ratio24hTo2w)

            // Update autosens settings
            preferences.autosensMin = Decimal(newParameters.logarithmicAutosensMin)
            preferences.autosensMax = Decimal(newParameters.logarithmicAutosensMax)

            // Save preferences
            settingsManager.preferences = preferences

            // Update therapy settings if needed
            updateTherapySettings(newParameters)
        }

        private func updateTherapySettings(_ parameters: ISFParameters) {
            var settings = settingsManager.settings

            // Update ISF schedule
            var insulinSensitivities = loadInsulinSensitivities()
            if !insulinSensitivities.sensitivities.isEmpty {
                let existingISF = insulinSensitivities.sensitivities[0]
                let updatedISF = InsulinSensitivityEntry(
                    sensitivity: Decimal(parameters.logarithmicProfileISF),
                    offset: existingISF.offset,
                    start: existingISF.start
                )
                insulinSensitivities.sensitivities[0] = updatedISF
                saveInsulinSensitivities(insulinSensitivities)
            }

            // Update target schedule for sigmoid
            var bgTargets = loadBGTargets()
            if !bgTargets.targets.isEmpty {
                let targetMgdL = parameters.sigmoidTargetBG
                let range: Double = 10.0 // ±5 mg/dL range
                let existingTarget = bgTargets.targets[0]
                let updatedTarget = BGTargetEntry(
                    low: Decimal(targetMgdL - range),
                    high: Decimal(targetMgdL + range),
                    start: existingTarget.start,
                    offset: existingTarget.offset
                )
                bgTargets.targets[0] = updatedTarget
                saveBGTargets(bgTargets)
            }

            // Settings are saved individually through storage methods
        }

        func toggleLogarithmicCurve() {
            showLogarithmicCurve.toggle()
        }

        func toggleSigmoidCurve() {
            showSigmoidCurve.toggle()
        }

        func openPlayground() {
            showPlayground = true
        }

        // MARK: - Storage Helpers

        private func loadInsulinSensitivities() -> InsulinSensitivities {
            storage.retrieve(OpenAPS.Settings.insulinSensitivities, as: InsulinSensitivities.self)
                ?? InsulinSensitivities(from: OpenAPS.defaults(for: OpenAPS.Settings.insulinSensitivities))
                ?? InsulinSensitivities(units: .mgdL, userPreferredUnits: .mgdL, sensitivities: [])
        }

        private func saveInsulinSensitivities(_ sensitivities: InsulinSensitivities) {
            storage.save(sensitivities, as: OpenAPS.Settings.insulinSensitivities)
        }

        private func loadBGTargets() -> BGTargets {
            storage.retrieve(OpenAPS.Settings.bgTargets, as: BGTargets.self)
                ?? BGTargets(from: OpenAPS.defaults(for: OpenAPS.Settings.bgTargets))
                ?? BGTargets(units: .mgdL, userPreferredUnits: .mgdL, targets: [])
        }

        private func saveBGTargets(_ targets: BGTargets) {
            storage.save(targets, as: OpenAPS.Settings.bgTargets)
        }
    }
}
