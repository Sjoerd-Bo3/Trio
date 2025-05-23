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
        // Generate smooth curve with many data points for better visualization
        let glucoseDataPointsMgdL: [Double] = {
            var points: [Double] = []
            // Generate points from 40 to 400 mg/dL with smaller steps for smoothness
            for i in stride(from: 40, through: 400, by: 5) {
                points.append(Double(i))
            }
            return points
        }()

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
        // Based on JavaScript: sensitivity * adjustmentFactor * tdd * Math.log(BG/insulinFactor+1) / 1800
        func logarithmicAutosensRatio(glucose: Double) -> Double {
            // Direct implementation of JavaScript formula
            let newRatio = logarithmicProfileISF * logarithmicAdjustmentFactor * weightedTDD * log(glucose / insulinFactor + 1) /
                1800

            // Apply autosens limits
            let clampedRatio = max(logarithmicAutosensMin, min(logarithmicAutosensMax, newRatio))

            return clampedRatio
        }

        // Calculate logarithmic ISF for given glucose value (mg/dL)
        func logarithmicISF(glucose: Double) -> Double {
            // JavaScript implementation: Line 298 and 343
            // var newRatio = sensitivity * adjustmentFactor * tdd * Math.log(BG/insulinFactor+1) / 1800;
            // const isf = sensitivity / newRatio;
            let newRatio = logarithmicProfileISF * logarithmicAdjustmentFactor * weightedTDD * log(glucose / insulinFactor + 1) /
                1800
            let isf = logarithmicProfileISF / newRatio

            return isf
        }

        // Calculate unbounded logarithmic ISF (for showing domain extensions)
        func logarithmicISFUnbounded(glucose: Double) -> Double {
            // Same as logarithmicISF since autosens limits aren't applied to the calculation
            logarithmicISF(glucose: glucose)
        }

        // Calculate sigmoid autosens ratio for given glucose value (mg/dL)
        // Based on JavaScript implementation lines 303-320
        func sigmoidAutosensRatio(glucose: Double) -> Double {
            let as_min = sigmoidAutosensMin
            let autosens_interval = sigmoidAutosensMax - as_min
            let bg_dev = (glucose - sigmoidTargetBG) * 0.0555

            // Use ratio24hTo2w as TDD factor (similar to tdd24h_14d_Ratio in JS)
            let tdd_factor = ratio24hTo2w

            // Calculate fix_offset to make sigmoid factor = 1 when BG deviation = 0
            var max_minus_one = sigmoidAutosensMax - 1
            if sigmoidAutosensMax == 1 {
                max_minus_one = sigmoidAutosensMax + 0.01 - 1
            }
            let fix_offset = log10(1 / max_minus_one - as_min / max_minus_one) / log10(M_E)

            let exponent = bg_dev * sigmoidAdjustmentFactor * tdd_factor + fix_offset
            let sigmoid_factor = autosens_interval / (1 + exp(-exponent)) + as_min

            return sigmoid_factor
        }

        // Calculate sigmoid ISF for given glucose value (mg/dL)
        func sigmoidISF(glucose: Double) -> Double {
            let ratio = sigmoidAutosensRatio(glucose: glucose)
            let isf = sigmoidProfileISF / ratio

            // No autosens clamping applied (consistent with logarithmic implementation)
            return isf
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

        // Generate chart data points for logarithmic curve (bounded)
        var logarithmicChartData: [(glucose: Double, isf: Double)] {
            glucoseDataPointsMgdL.map { glucose in
                (glucose: glucose, isf: logarithmicISF(glucose: glucose))
            }
        }

        // Generate chart data points for logarithmic curve (unbounded - for domain extension)
        var logarithmicUnboundedChartData: [(glucose: Double, isf: Double)] {
            glucoseDataPointsMgdL.map { glucose in
                (glucose: glucose, isf: logarithmicISFUnbounded(glucose: glucose))
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
                let decimal = Decimal(glucoseMgdL)
                return Double(decimal.asMmolL)
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
        let isOutsideDomain: Bool

        init(glucose: Double, isf: Double, formula: DynamicSensitivityType, isOutsideDomain: Bool = false) {
            self.glucose = glucose
            self.isf = isf
            self.formula = formula.displayName
            self.isOutsideDomain = isOutsideDomain
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
