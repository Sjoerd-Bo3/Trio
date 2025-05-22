import Foundation
import Testing

// Simple validation tests that don't require the full app infrastructure
@Suite("Dynamic ISF Formula Validation") struct DynamicISFValidationTests {
    // Test the mathematical formulas with known values
    @Test("Weighted TDD formula validation") func testWeightedTDDFormula() {
        // Formula: TTDD_weightedAverage = (TTDD_24hr × R_ratio24hTo2w) + (TTDD_2weeks × (1 – R_ratio24hTo2w))

        let tdd24hr = 50.0
        let tdd2weeks = 40.0
        let ratio = 0.35

        let expectedResult = (tdd24hr * ratio) + (tdd2weeks * (1 - ratio))
        let calculatedResult = (50.0 * 0.35) + (40.0 * 0.65)

        #expect(abs(calculatedResult - 43.5) < 0.001, "Weighted TDD should be 43.5")
        #expect(abs(calculatedResult - expectedResult) < 0.001, "Formula should match manual calculation")
    }

    @Test("Insulin factor formula validation") func testInsulinFactorFormula() {
        // Formula: I_insulinFactor = 120 – InsulinPeakTime

        let peakTime75 = 75.0
        let peakTime65 = 65.0

        let factor75 = 120.0 - peakTime75
        let factor65 = 120.0 - peakTime65

        #expect(factor75 == 45.0, "Insulin factor for 75min peak should be 45")
        #expect(factor65 == 55.0, "Insulin factor for 65min peak should be 55")
    }

    @Test("Logarithmic autosens ratio mathematical validation") func testLogarithmicFormulaValidation() {
        // Formula: R_log = (L_profileISF × L_adjustmentFactor × TTDD_weightedAverage × ln(x / I_insulinFactor + 1)) / 1800
        // Then: y_Log = L_profileISF / R_log

        let profileISF = 100.0
        let adjustmentFactor = 0.8
        let weightedTDD = 47.5
        let glucose = 100.0
        let insulinFactor = 45.0
        let autosensMin = 0.7
        let autosensMax = 1.3

        let rawRatio = (profileISF * adjustmentFactor * weightedTDD * log(glucose / insulinFactor + 1)) / 1800
        let clampedRatio = max(autosensMin, min(autosensMax, rawRatio))
        let resultingISF = profileISF / clampedRatio

        #expect(rawRatio > 0, "Raw ratio should be positive")
        #expect(clampedRatio >= autosensMin, "Clamped ratio should be >= min")
        #expect(clampedRatio <= autosensMax, "Clamped ratio should be <= max")
        #expect(resultingISF > 0, "Resulting ISF should be positive")
    }

    @Test("Sigmoid autosens ratio mathematical validation") func testSigmoidFormulaValidation() {
        // Formula components:
        // autosensRange = S_autosensMax – S_autosensMin
        // tdd_factor = TTDD_weightedAverage / TTDD_14days
        // fix_offset = ln(1 / autosensRange – S_autosensMin / autosensRange)
        // exponent = ((x – S_targetBG) × 0.0555 × S_adjustmentFactor × tdd_factor) + fix_offset
        // R_sig = autosensRange / (1 + e^(–exponent)) + S_autosensMin

        let autosensMin = 0.7
        let autosensMax = 1.3
        let weightedTDD = 47.5
        let tdd14days = 45.0
        let glucose = 100.0
        let targetBG = 100.0
        let adjustmentFactor = 0.5

        let autosensRange = autosensMax - autosensMin
        let tddFactor = weightedTDD / tdd14days
        let fixOffset = log(1 / autosensRange - autosensMin / autosensRange)
        let exponent = ((glucose - targetBG) * 0.0555 * adjustmentFactor * tddFactor) + fixOffset
        let ratio = autosensRange / (1 + exp(-exponent)) + autosensMin

        #expect(autosensRange == 0.6, "Autosens range should be 0.6")
        #expect(tddFactor > 1.0, "TDD factor should be > 1 when recent TDD > 14-day average")
        #expect(ratio >= autosensMin, "Sigmoid ratio should be >= min")
        #expect(ratio <= autosensMax, "Sigmoid ratio should be <= max")
    }

    @Test("Glucose unit conversion validation") func testGlucoseConversion() {
        // Known conversions to validate our math
        // 100 mg/dL = 5.55 mmol/L (approximately)
        // 180 mg/dL = 10.0 mmol/L (approximately)

        let glucoseMgdL = 100.0
        let conversionFactor = 18.0 // Standard conversion factor
        let glucoseMmolL = glucoseMgdL / conversionFactor

        #expect(abs(glucoseMmolL - 5.56) < 0.1, "100 mg/dL should convert to ~5.56 mmol/L")

        let glucose180 = 180.0
        let glucose180MmolL = glucose180 / conversionFactor

        #expect(abs(glucose180MmolL - 10.0) < 0.1, "180 mg/dL should convert to ~10.0 mmol/L")
    }

    @Test("Formula boundary conditions") func testFormulaBoundaryConditions() {
        // Test extreme values to ensure formulas behave reasonably

        // Very low glucose
        let lowGlucose = 30.0
        let normalGlucose = 100.0
        let highGlucose = 300.0

        let profileISF = 100.0
        let adjustmentFactor = 0.8
        let weightedTDD = 50.0
        let insulinFactor = 45.0

        // Test logarithmic formula behavior
        let lowRatio = (profileISF * adjustmentFactor * weightedTDD * log(lowGlucose / insulinFactor + 1)) / 1800
        let normalRatio = (profileISF * adjustmentFactor * weightedTDD * log(normalGlucose / insulinFactor + 1)) / 1800
        let highRatio = (profileISF * adjustmentFactor * weightedTDD * log(highGlucose / insulinFactor + 1)) / 1800

        // Ratios should increase with glucose (before clamping)
        #expect(lowRatio < normalRatio, "Low glucose should result in lower ratio")
        #expect(normalRatio < highRatio, "High glucose should result in higher ratio")

        // All ratios should be positive
        #expect(lowRatio > 0, "Ratio should be positive even at low glucose")
        #expect(normalRatio > 0, "Ratio should be positive at normal glucose")
        #expect(highRatio > 0, "Ratio should be positive at high glucose")
    }

    @Test("ISF calculation validation") func testISFCalculation() {
        // Test that ISF = profileISF / autosensRatio works correctly

        let profileISF = 100.0
        let testRatios = [0.5, 0.8, 1.0, 1.2, 1.5]

        for ratio in testRatios {
            let calculatedISF = profileISF / ratio
            let expectedISF = 100.0 / ratio

            #expect(
                abs(calculatedISF - expectedISF) < 0.001,

                "ISF calculation should be accurate for ratio \(ratio)"
            )

            // ISF should be inversely proportional to ratio
            if ratio < 1.0 {
                #expect(
                    calculatedISF > profileISF,

                    "ISF should be higher than profile when ratio < 1"
                )
            } else if ratio > 1.0 {
                #expect(
                    calculatedISF < profileISF,

                    "ISF should be lower than profile when ratio > 1"
                )
            } else {
                #expect(
                    abs(calculatedISF - profileISF) < 0.001,

                    "ISF should equal profile when ratio = 1"
                )
            }
        }
    }

    @Test("Data points validation") func testDataPointsValidation() {
        // Validate that our glucose data points cover a reasonable range
        let glucoseDataPointsMgdL = [40, 54, 70, 100, 140, 180, 250, 400]

        #expect(glucoseDataPointsMgdL.count == 8, "Should have 8 data points")
        #expect(glucoseDataPointsMgdL.first == 40, "First point should be 40 mg/dL")
        #expect(glucoseDataPointsMgdL.last == 400, "Last point should be 400 mg/dL")

        // Check that points are in ascending order
        for i in 1 ..< glucoseDataPointsMgdL.count {
            #expect(
                glucoseDataPointsMgdL[i] > glucoseDataPointsMgdL[i - 1],

                "Glucose points should be in ascending order"
            )
        }

        // Convert to mmol/L and validate
        let conversionFactor = 18.0
        let glucoseDataPointsMmolL = glucoseDataPointsMgdL.map { $0 / conversionFactor }

        #expect(
            abs(glucoseDataPointsMmolL.first! - 2.22) < 0.1,

            "First mmol/L point should be ~2.2"
        )
        #expect(
            abs(glucoseDataPointsMmolL.last! - 22.22) < 0.1,

            "Last mmol/L point should be ~22.2"
        )
    }
}
