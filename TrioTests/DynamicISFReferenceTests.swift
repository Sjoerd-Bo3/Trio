import Foundation
import Testing
@testable import Trio

@Suite("Dynamic ISF Reference Data Validation") struct DynamicISFReferenceTests {
    // Test parameters from provided reference data
    let referenceParameters = {
        var params = DynamicSettings.ISFParameters()

        // Shared variables
        params.tdd24hr = 50.0
        params.tdd2weeks = 50.0
        params.tdd14days = 76.92 // Derived from reference data analysis
        params.ratio24hTo2w = 0.65

        // Logarithmic variables
        params.logarithmicAdjustmentFactor = 0.75
        params.logarithmicProfileISF = 46.0
        params.logarithmicAutosensMax = 1.2
        params.logarithmicAutosensMin = 0.8
        params.insulinPeakTime = 65.0

        // Sigmoid variables
        params.sigmoidAdjustmentFactor = 0.5
        params.sigmoidTargetBG = 100.0 // mg/dL
        params.sigmoidAutosensMax = 1.2
        params.sigmoidAutosensMin = 0.8
        params.sigmoidProfileISF = 46.0

        return params
    }()

    // Reference test cases with expected results
    let referenceTestCases: [(
        glucose: Double,
        expectedLogISF: Double,
        expectedSigISF: Double,
        expectedLogRatio: Double,
        expectedSigRatio: Double
    )] = [
        (40, 87.824632, 51.041231, 0.52377105, 0.90123218),
        (55, 69.249362, 49.836817, 0.66426605, 0.92301241),
        (70, 58.466671, 48.565709, 0.78677303, 0.94717037),
        (100, 46.327935, 46.0, 0.99292143, 1.0),
        (140, 37.924686, 43.023831, 1.2129303, 1.0691749),
        (180, 33.052107, 40.94102, 1.3917418, 1.1235675),
        (250, 28.021366, 39.150832, 1.6416045, 1.1749431),
        (400, 22.716901, 38.39023, 2.0249241, 1.1982215)
    ]

    @Test("Logarithmic autosens ratio matches reference data") func testLogarithmicAutosensRatio() {
        let tolerance = 0.001

        for testCase in referenceTestCases {
            let calculatedRatio = referenceParameters.logarithmicAutosensRatio(glucose: testCase.glucose)
            let expectedRatio = testCase.expectedLogRatio

            #expect(
                abs(calculatedRatio - expectedRatio) < tolerance,
                "Logarithmic ratio for glucose \(testCase.glucose): \(calculatedRatio) vs expected \(expectedRatio)"
            )
        }
    }

    @Test("Logarithmic ISF matches reference data") func testLogarithmicISF() {
        let tolerance = 0.01 // Slightly higher tolerance for ISF values

        for testCase in referenceTestCases {
            let calculatedISF = referenceParameters.logarithmicISF(glucose: testCase.glucose)
            let expectedISF = testCase.expectedLogISF

            #expect(
                abs(calculatedISF - expectedISF) < tolerance,
                "Logarithmic ISF for glucose \(testCase.glucose): \(calculatedISF) vs expected \(expectedISF)"
            )
        }
    }

    @Test("Sigmoid autosens ratio matches reference data") func testSigmoidAutosensRatio() {
        let tolerance = 0.001

        for testCase in referenceTestCases {
            let calculatedRatio = referenceParameters.sigmoidAutosensRatio(glucose: testCase.glucose)
            let expectedRatio = testCase.expectedSigRatio

            #expect(
                abs(calculatedRatio - expectedRatio) < tolerance,
                "Sigmoid ratio for glucose \(testCase.glucose): \(calculatedRatio) vs expected \(expectedRatio)"
            )
        }
    }

    @Test("Sigmoid ISF matches reference data") func testSigmoidISF() {
        let tolerance = 0.01 // Slightly higher tolerance for ISF values

        for testCase in referenceTestCases {
            let calculatedISF = referenceParameters.sigmoidISF(glucose: testCase.glucose)
            let expectedISF = testCase.expectedSigISF

            #expect(
                abs(calculatedISF - expectedISF) < tolerance,
                "Sigmoid ISF for glucose \(testCase.glucose): \(calculatedISF) vs expected \(expectedISF)"
            )
        }
    }

    @Test("Weighted TDD calculation") func testWeightedTDD() {
        let expectedWeightedTDD = (50.0 * 0.65) + (50.0 * 0.35)
        let calculatedWeightedTDD = referenceParameters.weightedTDD

        #expect(
            abs(calculatedWeightedTDD - expectedWeightedTDD) < 0.001,
            "Weighted TDD calculation"
        )
        #expect(
            calculatedWeightedTDD == 50.0,
            "Weighted TDD should equal 50.0 for test parameters"
        )
    }

    @Test("Insulin factor calculation") func testInsulinFactor() {
        let expectedInsulinFactor = 120.0 - 65.0
        let calculatedInsulinFactor = referenceParameters.insulinFactor

        #expect(
            calculatedInsulinFactor == expectedInsulinFactor,
            "Insulin factor should equal 120 - peak time"
        )
        #expect(
            calculatedInsulinFactor == 55.0,
            "Insulin factor should equal 55.0 for 65min peak"
        )
    }

    @Test("Formula behavior at target glucose") func testTargetGlucoseBehavior() {
        let targetGlucose = 100.0

        // At target glucose, sigmoid ratio should be exactly 1.0
        let sigmoidRatio = referenceParameters.sigmoidAutosensRatio(glucose: targetGlucose)
        #expect(
            abs(sigmoidRatio - 1.0) < 0.001,
            "Sigmoid ratio should be 1.0 at target glucose"
        )

        // Sigmoid ISF should equal profile ISF at target
        let sigmoidISF = referenceParameters.sigmoidISF(glucose: targetGlucose)
        #expect(
            abs(sigmoidISF - referenceParameters.sigmoidProfileISF) < 0.01,
            "Sigmoid ISF should equal profile ISF at target glucose"
        )
    }

    @Test("Autosens ratio range behavior") func testAutosensRangeValidation() {
        // Test that ratios can extend beyond autosens min/max limits
        // This is correct behavior as the reference data shows

        let lowGlucose = 40.0
        let highGlucose = 400.0

        let logRatioLow = referenceParameters.logarithmicAutosensRatio(glucose: lowGlucose)
        let logRatioHigh = referenceParameters.logarithmicAutosensRatio(glucose: highGlucose)

        // Based on reference data, ratios can go below 0.8 and above 1.2
        #expect(
            logRatioLow < referenceParameters.logarithmicAutosensMin,
            "Logarithmic ratio should go below autosens min for low glucose"
        )
        #expect(
            logRatioHigh > referenceParameters.logarithmicAutosensMax,
            "Logarithmic ratio should go above autosens max for high glucose"
        )

        // But ISF values should be reasonable
        let isfLow = referenceParameters.logarithmicISF(glucose: lowGlucose)
        let isfHigh = referenceParameters.logarithmicISF(glucose: highGlucose)

        #expect(
            isfLow > 0 && isfLow < 1000,
            "ISF should be in reasonable range for low glucose"
        )
        #expect(
            isfHigh > 0 && isfHigh < 1000,
            "ISF should be in reasonable range for high glucose"
        )
    }

    @Test("Formula monotonicity") func testFormulaMonotonicity() {
        // Test that ISF generally decreases as glucose increases (for most of the range)
        let glucoseValues = [70.0, 100.0, 140.0, 180.0]

        var previousLogISF = Double.infinity
        var previousSigISF = Double.infinity

        for glucose in glucoseValues {
            let logISF = referenceParameters.logarithmicISF(glucose: glucose)
            let sigISF = referenceParameters.sigmoidISF(glucose: glucose)

            if previousLogISF != Double.infinity {
                #expect(
                    logISF <= previousLogISF,
                    "Logarithmic ISF should generally decrease with increasing glucose"
                )
            }

            if previousSigISF != Double.infinity {
                #expect(
                    sigISF <= previousSigISF,
                    "Sigmoid ISF should generally decrease with increasing glucose"
                )
            }

            previousLogISF = logISF
            previousSigISF = sigISF
        }
    }

    @Test("Edge case glucose values") func testEdgeCaseGlucoseValues() {
        // Test very low and very high glucose values
        let extremeValues = [20.0, 500.0]

        for glucose in extremeValues {
            let logISF = referenceParameters.logarithmicISF(glucose: glucose)
            let sigISF = referenceParameters.sigmoidISF(glucose: glucose)

            #expect(
                logISF > 0 && logISF < 10000,
                "Logarithmic ISF should be reasonable for glucose \(glucose)"
            )
            #expect(
                sigISF > 0 && sigISF < 10000,
                "Sigmoid ISF should be reasonable for glucose \(glucose)"
            )

            // Check that we don't get NaN or infinite values
            #expect(
                !logISF.isNaN && !logISF.isInfinite,
                "Logarithmic ISF should be finite for glucose \(glucose)"
            )
            #expect(
                !sigISF.isNaN && !sigISF.isInfinite,
                "Sigmoid ISF should be finite for glucose \(glucose)"
            )
        }
    }
}
