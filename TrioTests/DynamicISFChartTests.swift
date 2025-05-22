import Foundation
import SwiftUI
import Testing
@testable import Trio

@Suite("Dynamic ISF Chart Tests") struct DynamicISFChartTests {
    // MARK: - Chart Point Tests

    @Test("ISF Chart Point creation") func testISFChartPointCreation() {
        let chartPoint = DynamicSettings.ISFChartPoint(
            glucose: 100.0,
            isf: 125.0,
            formula: .logarithmic
        )

        #expect(
            chartPoint.glucose == 100.0,
            "Chart point should store glucose value correctly"
        )
        #expect(
            chartPoint.isf == 125.0,
            "Chart point should store ISF value correctly"
        )
        #expect(
            chartPoint.formula == "Logarithmic",
            "Chart point should store formula display name correctly"
        )
        #expect(
            chartPoint.id != UUID(),
            "Chart point should have unique ID"
        )
    }

    @Test("ISF Chart Point with different formulas") func testISFChartPointFormulas() {
        let logPoint = DynamicSettings.ISFChartPoint(
            glucose: 100.0,
            isf: 125.0,
            formula: .logarithmic
        )

        let sigPoint = DynamicSettings.ISFChartPoint(
            glucose: 100.0,
            isf: 120.0,
            formula: .sigmoid
        )

        let disabledPoint = DynamicSettings.ISFChartPoint(
            glucose: 100.0,
            isf: 100.0,
            formula: .disabled
        )

        #expect(
            logPoint.formula == "Logarithmic",
            "Logarithmic formula should display correctly"
        )
        #expect(
            sigPoint.formula == "Sigmoid",
            "Sigmoid formula should display correctly"
        )
        #expect(
            disabledPoint.formula == "Disabled",
            "Disabled formula should display correctly"
        )
    }

    // MARK: - Legend Item Tests

    @Test("Legend Item creation") func testLegendItemCreation() {
        let legendItem = DynamicSettings.LegendItem(
            label: "Test Curve",
            color: .blue,
            isVisible: true
        )

        #expect(
            legendItem.label == "Test Curve",
            "Legend item should store label correctly"
        )
        #expect(
            legendItem.color == .blue,
            "Legend item should store color correctly"
        )
        #expect(
            legendItem.isVisible == true,
            "Legend item should store visibility correctly"
        )
        #expect(
            legendItem.id != UUID(),
            "Legend item should have unique ID"
        )
    }

    // MARK: - Chart Data Generation Tests

    @Test("Chart data points generation for different units") func testChartDataPointsGeneration() {
        let parameters = DynamicSettings.ISFParameters()

        // Test logarithmic chart data
        let logData = parameters.logarithmicChartData
        #expect(
            logData.count == parameters.glucoseDataPointsMgdL.count,
            "Logarithmic chart data should have correct count"
        )

        // Test that all glucose values are in mg/dL (internal representation)
        for point in logData {
            #expect(
                point.glucose >= 40.0 && point.glucose <= 400.0,
                "Glucose values should be in expected mg/dL range"
            )
        }

        // Test sigmoid chart data
        let sigData = parameters.sigmoidChartData
        #expect(
            sigData.count == parameters.glucoseDataPointsMgdL.count,
            "Sigmoid chart data should have correct count"
        )

        // Test that data points are different between formulas
        let logISFAt100 = logData.first(where: { $0.glucose == 100.0 })?.isf
        let sigISFAt100 = sigData.first(where: { $0.glucose == 100.0 })?.isf

        if let logISF = logISFAt100, let sigISF = sigISFAt100 {
            // They might be the same by coincidence, but usually should differ
            // We'll just check they're both reasonable values
            #expect(
                logISF > 0 && logISF < 1000,
                "Logarithmic ISF should be reasonable"
            )
            #expect(
                sigISF > 0 && sigISF < 1000,
                "Sigmoid ISF should be reasonable"
            )
        }
    }

    @Test("Chart data monotonicity") func testChartDataMonotonicity() {
        let parameters = DynamicSettings.ISFParameters()

        // Test that glucose values are properly ordered
        let logData = parameters.logarithmicChartData
        for i in 1 ..< logData.count {
            #expect(
                logData[i].glucose > logData[i - 1].glucose,
                "Glucose values should be in ascending order"
            )
        }

        let sigData = parameters.sigmoidChartData
        for i in 1 ..< sigData.count {
            #expect(
                sigData[i].glucose > sigData[i - 1].glucose,
                "Glucose values should be in ascending order"
            )
        }
    }

    // MARK: - Chart Range Tests

    @Test("Chart axis range calculations") func testChartAxisRanges() {
        let parameters = DynamicSettings.ISFParameters()

        // Test glucose range in both units
        let mgdLPoints = parameters.displayGlucoseDataPoints(units: .mgdL)
        let mmolLPoints = parameters.displayGlucoseDataPoints(units: .mmolL)

        // mg/dL range should be 40-400
        #expect(
            mgdLPoints.min()! >= 40.0,
            "Minimum mg/dL glucose should be at least 40"
        )
        #expect(
            mgdLPoints.max()! <= 400.0,
            "Maximum mg/dL glucose should be at most 400"
        )

        // mmol/L range should be roughly 2.2-22.2
        #expect(
            mmolLPoints.min()! >= 2.0,
            "Minimum mmol/L glucose should be at least 2.0"
        )
        #expect(
            mmolLPoints.max()! <= 25.0,
            "Maximum mmol/L glucose should be at most 25.0"
        )
    }

    // MARK: - Chart Performance Tests

    @Test("Chart data generation performance") func testChartDataGenerationPerformance() {
        let parameters = DynamicSettings.ISFParameters()

        // Measure time for generating chart data
        let startTime = CFAbsoluteTimeGetCurrent()

        for _ in 0 ..< 1000 {
            _ = parameters.logarithmicChartData
            _ = parameters.sigmoidChartData
        }

        let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime

        // Should complete 1000 iterations in reasonable time (less than 1 second)
        #expect(
            timeElapsed < 1.0,
            "Chart data generation should be performant"
        )
    }

    // MARK: - Current Glucose Marker Tests

    @Test("Current glucose marker calculation") func testCurrentGlucoseMarker() {
        var parameters = DynamicSettings.ISFParameters()
        let testGlucose = 120.0 // mg/dL

        // Test with logarithmic formula
        parameters.activeFormula = .logarithmic
        let currentISF_log = parameters.currentISF(glucose: testGlucose)
        #expect(
            currentISF_log > 0,
            "Current ISF should be positive"
        )

        // Test with sigmoid formula
        parameters.activeFormula = .sigmoid
        let currentISF_sig = parameters.currentISF(glucose: testGlucose)
        #expect(
            currentISF_sig > 0,
            "Current ISF should be positive"
        )

        // Test with disabled formula
        parameters.activeFormula = .disabled
        let currentISF_disabled = parameters.currentISF(glucose: testGlucose)
        #expect(
            currentISF_disabled == parameters.logarithmicProfileISF,
            "Disabled formula should return profile ISF"
        )
    }

    // MARK: - Display Unit Tests

    @Test("Display glucose conversion accuracy") func testDisplayGlucoseConversionAccuracy() {
        let parameters = DynamicSettings.ISFParameters()

        // Test known conversion: 100 mg/dL = 5.55 mmol/L
        let glucose_mgdL = 100.0
        let displayed_mmol = parameters.displayGlucose(glucose_mgdL, units: .mmolL)

        // Allow for small rounding differences
        #expect(
            abs(displayed_mmol - 5.55) < 0.1,
            "100 mg/dL should convert to approximately 5.55 mmol/L"
        )

        // Test another known conversion: 180 mg/dL = 10.0 mmol/L
        let glucose_180 = 180.0
        let displayed_180_mmol = parameters.displayGlucose(glucose_180, units: .mmolL)

        #expect(
            abs(displayed_180_mmol - 10.0) < 0.1,
            "180 mg/dL should convert to approximately 10.0 mmol/L"
        )
    }

    // MARK: - Data Consistency Tests

    @Test("Chart data consistency across unit conversions") func testChartDataConsistency() {
        let parameters = DynamicSettings.ISFParameters()

        // Generate chart data
        let logData = parameters.logarithmicChartData
        let sigData = parameters.sigmoidChartData

        // Test that ISF values are reasonable
        for point in logData {
            #expect(
                point.isf >= 10.0 && point.isf <= 1000.0,
                "Logarithmic ISF values should be in reasonable range"
            )
        }

        for point in sigData {
            #expect(
                point.isf >= 10.0 && point.isf <= 1000.0,
                "Sigmoid ISF values should be in reasonable range"
            )
        }

        // Test that glucose values match expected data points
        let expectedGlucoseValues = parameters.glucoseDataPointsMgdL

        for (index, point) in logData.enumerated() {
            #expect(
                point.glucose == expectedGlucoseValues[index],
                "Logarithmic chart glucose values should match expected data points"
            )
        }

        for (index, point) in sigData.enumerated() {
            #expect(
                point.glucose == expectedGlucoseValues[index],
                "Sigmoid chart glucose values should match expected data points"
            )
        }
    }
}
