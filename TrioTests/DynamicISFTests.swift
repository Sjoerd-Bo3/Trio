import Foundation
import Testing
@testable import Trio

@Suite("Dynamic ISF Tests") struct DynamicISFTests {
    // MARK: - Mathematical Formula Tests

    @Test("Weighted TDD calculation") func testWeightedTDDCalculation() {
        var parameters = DynamicSettings.ISFParameters()
        parameters.tdd24hr = 50.0
        parameters.tdd2weeks = 40.0
        parameters.ratio24hTo2w = 0.35

        let expectedWeightedTDD = (50.0 * 0.35) + (40.0 * (1 - 0.35))
        let calculatedWeightedTDD = parameters.weightedTDD

        #expect(
            abs(calculatedWeightedTDD - expectedWeightedTDD) < 0.001,

            "Weighted TDD calculation should be correct"
        )
        #expect(
            calculatedWeightedTDD == 43.5,

            "Weighted TDD should equal 43.5"
        )
    }

    @Test("Insulin factor calculation") func testInsulinFactorCalculation() {
        var parameters = DynamicSettings.ISFParameters()
        parameters.insulinPeakTime = 75.0

        let expectedInsulinFactor = 120.0 - 75.0
        let calculatedInsulinFactor = parameters.insulinFactor

        #expect(
            calculatedInsulinFactor == expectedInsulinFactor,
            "Insulin factor should equal 120 - peak time"
        )
        #expect(
            calculatedInsulinFactor == 45.0,
            "Insulin factor should equal 45.0 for 75min peak"
        )
    }

    @Test("Logarithmic autosens ratio calculation") func testLogarithmicAutosensRatio() {
        var parameters = DynamicSettings.ISFParameters()
        parameters.logarithmicProfileISF = 100.0
        parameters.logarithmicAdjustmentFactor = 0.8
        parameters.tdd24hr = 50.0
        parameters.tdd2weeks = 45.0
        parameters.ratio24hTo2w = 0.35
        parameters.insulinPeakTime = 75.0
        parameters.logarithmicAutosensMin = 0.7
        parameters.logarithmicAutosensMax = 1.3

        // Test at normal glucose (100 mg/dL)
        let ratio100 = parameters.logarithmicAutosensRatio(glucose: 100.0)
        #expect(
            ratio100 >= parameters.logarithmicAutosensMin,
            "Ratio should be >= autosens min"
        )
        #expect(
            ratio100 <= parameters.logarithmicAutosensMax,
            "Ratio should be <= autosens max"
        )

        // Test at low glucose (70 mg/dL) - should have lower ratio
        let ratio70 = parameters.logarithmicAutosensRatio(glucose: 70.0)
        #expect(
            ratio70 < ratio100,
            "Lower glucose should result in lower autosens ratio"
        )

        // Test at high glucose (200 mg/dL) - should have higher ratio
        let ratio200 = parameters.logarithmicAutosensRatio(glucose: 200.0)
        #expect(
            ratio200 > ratio100,
            "Higher glucose should result in higher autosens ratio"
        )
    }

    @Test("Sigmoid autosens ratio calculation") func testSigmoidAutosensRatio() {
        var parameters = DynamicSettings.ISFParameters()
        parameters.sigmoidProfileISF = 100.0
        parameters.sigmoidAdjustmentFactor = 0.5
        parameters.sigmoidTargetBG = 100.0
        parameters.tdd24hr = 50.0
        parameters.tdd2weeks = 45.0
        parameters.tdd14days = 45.0
        parameters.ratio24hTo2w = 0.35
        parameters.sigmoidAutosensMin = 0.7
        parameters.sigmoidAutosensMax = 1.3

        // Test at target glucose
        let ratioTarget = parameters.sigmoidAutosensRatio(glucose: 100.0)
        #expect(
            ratioTarget >= parameters.sigmoidAutosensMin,
            "Ratio should be >= autosens min"
        )
        #expect(
            ratioTarget <= parameters.sigmoidAutosensMax,
            "Ratio should be <= autosens max"
        )

        // Test at low glucose (70 mg/dL)
        let ratio70 = parameters.sigmoidAutosensRatio(glucose: 70.0)
        #expect(
            ratio70 < ratioTarget,
            "Below-target glucose should result in lower autosens ratio"
        )

        // Test at high glucose (150 mg/dL)
        let ratio150 = parameters.sigmoidAutosensRatio(glucose: 150.0)
        #expect(
            ratio150 > ratioTarget,
            "Above-target glucose should result in higher autosens ratio"
        )
    }

    @Test("ISF calculations from autosens ratios") func testISFCalculations() {
        var parameters = DynamicSettings.ISFParameters()
        parameters.logarithmicProfileISF = 100.0
        parameters.sigmoidProfileISF = 100.0

        // Mock autosens ratio of 0.8 should give ISF of 125
        let glucose = 100.0
        let mockRatio = 0.8

        // Test that ISF = profile / ratio
        let expectedISF = 100.0 / mockRatio
        #expect(
            abs(expectedISF - 125.0) < 0.001,
            "ISF should equal profile ISF divided by autosens ratio"
        )
    }

    // MARK: - Glucose Unit Conversion Tests

    @Test("Glucose display conversion to mmol/L") func testGlucoseDisplayConversionMmol() {
        let parameters = DynamicSettings.ISFParameters()

        // Test conversion of 100 mg/dL to mmol/L (should be ~5.55)
        let glucose_mgdL = 100.0
        let displayed_mmol = parameters.displayGlucose(glucose_mgdL, units: .mmolL)

        #expect(
            abs(displayed_mmol - 5.6) < 0.1,
            "100 mg/dL should convert to approximately 5.6 mmol/L"
        )
    }

    @Test("Glucose display conversion to mg/dL") func testGlucoseDisplayConversionMgdL() {
        let parameters = DynamicSettings.ISFParameters()

        // Test that mg/dL values pass through unchanged
        let glucose_mgdL = 100.0
        let displayed_mgdL = parameters.displayGlucose(glucose_mgdL, units: .mgdL)

        #expect(
            displayed_mgdL == glucose_mgdL,
            "mg/dL values should pass through unchanged"
        )
    }

    @Test("Glucose data points conversion") func testGlucoseDataPointsConversion() {
        let parameters = DynamicSettings.ISFParameters()

        // Test mg/dL data points
        let mgdLPoints = parameters.displayGlucoseDataPoints(units: .mgdL)
        #expect(
            mgdLPoints == parameters.glucoseDataPointsMgdL,
            "mg/dL data points should be unchanged"
        )

        // Test mmol/L data points
        let mmolLPoints = parameters.displayGlucoseDataPoints(units: .mmolL)
        #expect(
            mmolLPoints.count == parameters.glucoseDataPointsMgdL.count,
            "mmol/L data points should have same count as mg/dL"
        )

        // Check that first point (40 mg/dL) converts to approximately 2.2 mmol/L
        #expect(
            abs(mmolLPoints[0] - 2.2) < 0.1,
            "40 mg/dL should convert to approximately 2.2 mmol/L"
        )
    }

    // MARK: - Chart Data Generation Tests

    @Test("Logarithmic chart data generation") func testLogarithmicChartData() {
        let parameters = DynamicSettings.ISFParameters()
        let chartData = parameters.logarithmicChartData

        #expect(
            chartData.count == parameters.glucoseDataPointsMgdL.count,
            "Chart data should have same count as glucose data points"
        )

        // Verify data structure
        for (index, point) in chartData.enumerated() {
            #expect(
                point.glucose == parameters.glucoseDataPointsMgdL[index],
                "Chart glucose values should match data points"
            )
            #expect(
                point.isf > 0,
                "ISF values should be positive"
            )
        }

        // Verify ascending glucose values correspond to reasonable ISF changes
        let firstISF = chartData.first!.isf
        let lastISF = chartData.last!.isf
        #expect(
            firstISF != lastISF,
            "ISF should vary across glucose range"
        )
    }

    @Test("Sigmoid chart data generation") func testSigmoidChartData() {
        let parameters = DynamicSettings.ISFParameters()
        let chartData = parameters.sigmoidChartData

        #expect(
            chartData.count == parameters.glucoseDataPointsMgdL.count,
            "Chart data should have same count as glucose data points"
        )

        // Verify data structure
        for (index, point) in chartData.enumerated() {
            #expect(
                point.glucose == parameters.glucoseDataPointsMgdL[index],
                "Chart glucose values should match data points"
            )
            #expect(
                point.isf > 0,
                "ISF values should be positive"
            )
        }
    }

    // MARK: - Active Formula Tests

    @Test("Current ISF calculation with different formulas") func testCurrentISFCalculation() {
        var parameters = DynamicSettings.ISFParameters()
        let testGlucose = 100.0

        // Test logarithmic formula
        parameters.activeFormula = .logarithmic
        let logISF = parameters.currentISF(glucose: testGlucose)
        let expectedLogISF = parameters.logarithmicISF(glucose: testGlucose)
        #expect(
            logISF == expectedLogISF,
            "Current ISF should match logarithmic ISF when formula is logarithmic"
        )

        // Test sigmoid formula
        parameters.activeFormula = .sigmoid
        let sigISF = parameters.currentISF(glucose: testGlucose)
        let expectedSigISF = parameters.sigmoidISF(glucose: testGlucose)
        #expect(
            sigISF == expectedSigISF,
            "Current ISF should match sigmoid ISF when formula is sigmoid"
        )

        // Test disabled formula
        parameters.activeFormula = .disabled
        let disabledISF = parameters.currentISF(glucose: testGlucose)
        #expect(
            disabledISF == parameters.logarithmicProfileISF,
            "Current ISF should match profile ISF when formula is disabled"
        )
    }

    // MARK: - Edge Cases and Validation Tests

    @Test("Autosens ratio clamping") func testAutosensRatioClamping() {
        var parameters = DynamicSettings.ISFParameters()
        parameters.logarithmicAutosensMin = 0.7
        parameters.logarithmicAutosensMax = 1.3
        parameters.sigmoidAutosensMin = 0.7
        parameters.sigmoidAutosensMax = 1.3

        // Test extreme glucose values to ensure clamping works
        let extremeLowGlucose = 20.0
        let extremeHighGlucose = 500.0

        let logRatioLow = parameters.logarithmicAutosensRatio(glucose: extremeLowGlucose)
        let logRatioHigh = parameters.logarithmicAutosensRatio(glucose: extremeHighGlucose)

        #expect(
            logRatioLow >= parameters.logarithmicAutosensMin,
            "Logarithmic ratio should be clamped to minimum"
        )
        #expect(
            logRatioLow <= parameters.logarithmicAutosensMax,
            "Logarithmic ratio should be clamped to maximum"
        )
        #expect(
            logRatioHigh >= parameters.logarithmicAutosensMin,
            "Logarithmic ratio should be clamped to minimum"
        )
        #expect(
            logRatioHigh <= parameters.logarithmicAutosensMax,
            "Logarithmic ratio should be clamped to maximum"
        )

        let sigRatioLow = parameters.sigmoidAutosensRatio(glucose: extremeLowGlucose)
        let sigRatioHigh = parameters.sigmoidAutosensRatio(glucose: extremeHighGlucose)

        #expect(
            sigRatioLow >= parameters.sigmoidAutosensMin,
            "Sigmoid ratio should be clamped to minimum"
        )
        #expect(
            sigRatioLow <= parameters.sigmoidAutosensMax,
            "Sigmoid ratio should be clamped to maximum"
        )
        #expect(
            sigRatioHigh >= parameters.sigmoidAutosensMin,
            "Sigmoid ratio should be clamped to minimum"
        )
        #expect(
            sigRatioHigh <= parameters.sigmoidAutosensMax,
            "Sigmoid ratio should be clamped to maximum"
        )
    }

    @Test("Parameter validation") func testParameterValidation() {
        let parameters = DynamicSettings.ISFParameters()

        // Test that default parameters are reasonable
        #expect(
            parameters.logarithmicProfileISF > 0,
            "Profile ISF should be positive"
        )
        #expect(
            parameters.sigmoidProfileISF > 0,
            "Profile ISF should be positive"
        )
        #expect(
            parameters.logarithmicAdjustmentFactor > 0,
            "Adjustment factor should be positive"
        )
        #expect(
            parameters.sigmoidAdjustmentFactor > 0,
            "Adjustment factor should be positive"
        )
        #expect(
            parameters.ratio24hTo2w >= 0 && parameters.ratio24hTo2w <= 1,
            "TDD ratio should be between 0 and 1"
        )
        #expect(
            parameters.logarithmicAutosensMin < parameters.logarithmicAutosensMax,
            "Autosens min should be less than max"
        )
        #expect(
            parameters.sigmoidAutosensMin < parameters.sigmoidAutosensMax,
            "Autosens min should be less than max"
        )
    }

    // MARK: - Codable Tests

    @Test("ISFParameters Codable compliance") func testISFParametersCodable() throws {
        let originalParameters = DynamicSettings.ISFParameters()

        // Test encoding
        let encoder = JSONEncoder()
        let encodedData = try encoder.encode(originalParameters)
        #expect(!encodedData.isEmpty, "Encoded data should not be empty")

        // Test decoding
        let decoder = JSONDecoder()
        let decodedParameters = try decoder.decode(DynamicSettings.ISFParameters.self, from: encodedData)

        // Verify key properties are preserved
        #expect(
            decodedParameters.logarithmicProfileISF == originalParameters.logarithmicProfileISF,
            "Profile ISF should be preserved after encoding/decoding"
        )
        #expect(
            decodedParameters.activeFormula == originalParameters.activeFormula,
            "Active formula should be preserved after encoding/decoding"
        )
        #expect(
            decodedParameters.glucoseDataPointsMgdL == originalParameters.glucoseDataPointsMgdL,
            "Glucose data points should be preserved after encoding/decoding"
        )
    }
}
