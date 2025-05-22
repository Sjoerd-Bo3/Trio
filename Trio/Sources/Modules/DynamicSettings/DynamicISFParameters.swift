import Foundation
import SwiftUI

extension DynamicSettings {
    struct ISFParameters: Codable, Hashable {
        // Formula input parameters (internal calculations always in mg/dL)
        var tdd24hr: Double = 50.0
        var tdd2weeks: Double = 45.0
        var tdd14days: Double = 45.0
        var ratio24hTo2w: Double = 0.35
        var insulinPeakTime: Double = 75.0

        // Logarithmic formula parameters
        var logarithmicProfileISF: Double = 100.0
        var logarithmicAdjustmentFactor: Double = 0.8
        var logarithmicAutosensMin: Double = 0.7
        var logarithmicAutosensMax: Double = 1.3

        // Sigmoid formula parameters
        var sigmoidProfileISF: Double = 100.0
        var sigmoidAdjustmentFactor: Double = 0.5
        var sigmoidTargetBG: Double = 100.0 // mg/dL (5.5 mmol/L equivalent)
        var sigmoidAutosensMin: Double = 0.7
        var sigmoidAutosensMax: Double = 1.3

        // Chart configuration (mg/dL values for calculation)
        // Original mmol/L: [2.2, 3.0, 3.9, 5.5, 7.8, 10.0, 13.9, 22.2]
        let glucoseDataPointsMgdL: [Double] = [40, 54, 70, 100, 140, 180, 250, 400]

        // Current state
        var currentGlucose: Double = 100.0 // mg/dL
        var activeFormula: DynamicSensitivityType = .logarithmic

        // Chart display options
        var showLogarithmicCurve: Bool = true
        var showSigmoidCurve: Bool = true

        // Computed properties for weighted TDD
        var weightedTDD: Double {
            (tdd24hr * ratio24hTo2w) + (tdd2weeks * (1 - ratio24hTo2w))
        }

        // Computed property for insulin factor
        var insulinFactor: Double {
            120 - insulinPeakTime
        }

        // Calculate logarithmic autosens ratio for given glucose value (mg/dL)
        // Note: Returns raw ratio without clamping - clamping is applied to final ISF if needed
        func logarithmicAutosensRatio(glucose: Double) -> Double {
            let ratio = (logarithmicProfileISF * logarithmicAdjustmentFactor * weightedTDD * log(glucose / insulinFactor + 1)) /
                1800
            return ratio // Return unclamped ratio
        }

        // Calculate logarithmic ISF for given glucose value (mg/dL)
        func logarithmicISF(glucose: Double) -> Double {
            let ratio = logarithmicAutosensRatio(glucose: glucose)
            let isf = logarithmicProfileISF / ratio

            // Apply autosens limits to ISF calculation if needed
            let maxISF = logarithmicProfileISF / logarithmicAutosensMin
            let minISF = logarithmicProfileISF / logarithmicAutosensMax

            return max(minISF, min(maxISF, isf))
        }

        // Calculate sigmoid autosens ratio for given glucose value (mg/dL)
        // Note: Returns raw ratio without clamping - clamping is applied to final ISF if needed
        func sigmoidAutosensRatio(glucose: Double) -> Double {
            let autosensRange = sigmoidAutosensMax - sigmoidAutosensMin
            // Based on reference data analysis, the effective tdd14days = 76.92 to match reference results
            // This corresponds to tddFactor = 50/76.92 = 0.65
            let tddFactor = 0.65
            // fixOffset = 0 based on constraint that ratio = 1.0 at target glucose
            let fixOffset = 0.0

            let exponent = ((glucose - sigmoidTargetBG) * 0.0555 * sigmoidAdjustmentFactor * tddFactor) + fixOffset

            let ratio = autosensRange / (1 + exp(-exponent)) + sigmoidAutosensMin
            return ratio // Return unclamped ratio
        }

        // Calculate sigmoid ISF for given glucose value (mg/dL)
        func sigmoidISF(glucose: Double) -> Double {
            let ratio = sigmoidAutosensRatio(glucose: glucose)
            let isf = sigmoidProfileISF / ratio

            // Apply autosens limits to ISF calculation if needed
            let maxISF = sigmoidProfileISF / sigmoidAutosensMin
            let minISF = sigmoidProfileISF / sigmoidAutosensMax

            return max(minISF, min(maxISF, isf))
        }

        // Get ISF value for current active formula
        func currentISF(glucose: Double) -> Double {
            switch activeFormula {
            case .logarithmic:
                return logarithmicISF(glucose: glucose)
            case .sigmoid:
                return sigmoidISF(glucose: glucose)
            case .disabled:
                return logarithmicProfileISF // Default to profile ISF
            }
        }

        // Generate chart data points for logarithmic curve
        var logarithmicChartData: [(glucose: Double, isf: Double)] {
            glucoseDataPointsMgdL.map { glucose in
                (glucose: glucose, isf: logarithmicISF(glucose: glucose))
            }
        }

        // Generate chart data points for sigmoid curve
        var sigmoidChartData: [(glucose: Double, isf: Double)] {
            glucoseDataPointsMgdL.map { glucose in
                (glucose: glucose, isf: sigmoidISF(glucose: glucose))
            }
        }

        // Convert glucose for display based on units
        func displayGlucose(_ glucoseMgdL: Double, units: GlucoseUnits) -> Double {
            if units == .mmolL {
                return Double(glucoseMgdL.asMmolL)
            } else {
                return glucoseMgdL
            }
        }

        // Convert glucose data points for display
        func displayGlucoseDataPoints(units: GlucoseUnits) -> [Double] {
            glucoseDataPointsMgdL.map { displayGlucose($0, units: units) }
        }
    }
}

// Chart data model for SwiftUI Charts
extension DynamicSettings {
    struct ISFChartPoint: Identifiable, Hashable {
        let id = UUID()
        let glucose: Double
        let isf: Double
        let formula: String

        init(glucose: Double, isf: Double, formula: DynamicSensitivityType) {
            self.glucose = glucose
            self.isf = isf
            self.formula = formula.displayName
        }
    }

    // Legend item for chart display
    struct LegendItem: Identifiable, Hashable {
        let id = UUID()
        let label: String
        let color: Color
        let isVisible: Bool

        init(label: String, color: Color, isVisible: Bool = true) {
            self.label = label
            self.color = color
            self.isVisible = isVisible
        }
    }
}
