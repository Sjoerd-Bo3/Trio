import Charts
import CoreData
import Foundation
import SwiftUI

struct ForeCastChart: View {
    @StateObject var state: Bolus.StateModel
    @Environment(\.colorScheme) var colorScheme
    @Binding var units: GlucoseUnits

    @State private var startMarker = Date(timeIntervalSinceNow: -4 * 60 * 60)
    @State private var endMarker = Date(timeIntervalSinceNow: 3 * 60 * 60)

    private var conversionFactor: Decimal {
        units == .mmolL ? 0.0555 : 1
    }

    var body: some View {
        forecastChart
    }

    private var forecastChart: some View {
        Chart {
            drawGlucose()
            drawCurrentTimeMarker()
//            drawForecasts()
            drawForecastArea()
        }
        .chartXAxis { forecastChartXAxis }
        .chartXScale(domain: startMarker ... endMarker)
        .chartYAxis { forecastChartYAxis }
    }

    private func drawGlucose() -> some ChartContent {
        ForEach(state.glucoseFromPersistence) { item in
            if item.glucose > Int(state.highGlucose) {
                PointMark(
                    x: .value("Time", item.date ?? Date(), unit: .second),
                    y: .value("Value", Decimal(item.glucose) * conversionFactor)
                )
                .foregroundStyle(Color.orange.gradient)
                .symbolSize(20)
            } else if item.glucose < Int(state.lowGlucose) {
                PointMark(
                    x: .value("Time", item.date ?? Date(), unit: .second),
                    y: .value("Value", Decimal(item.glucose) * conversionFactor)
                )
                .foregroundStyle(Color.red.gradient)
                .symbolSize(20)
            } else {
                PointMark(
                    x: .value("Time", item.date ?? Date(), unit: .second),
                    y: .value("Value", Decimal(item.glucose) * conversionFactor)
                )
                .foregroundStyle(Color.green.gradient)
                .symbolSize(20)
            }
        }
    }

    private func timeForIndex(_ index: Int32) -> Date {
        let currentTime = Date()
        let timeInterval = TimeInterval(index * 300)
        return currentTime.addingTimeInterval(timeInterval)
    }

    private func drawForecastArea() -> some ChartContent {
        ForEach(state.minForecast.indices, id: \.self) { index in
            AreaMark(
                x: .value("Time", timeForIndex(Int32(index))),
                yStart: .value("Min Value", Decimal(state.minForecast[index]) * conversionFactor),
                yEnd: .value("Max Value", Decimal(state.maxForecast[index]) * conversionFactor)
            )
            .foregroundStyle(Color.blue.opacity(0.3))
        }
    }

//    private func drawForecasts() -> some ChartContent {
//        let predictions = state.predictionsForChart
//
//        let predictionData = [
//            ("IOB", predictions?.iob),
//            ("ZT", predictions?.zt),
//            ("COB", predictions?.cob),
//            ("UAM", predictions?.uam)
//        ]
//
//        return ForEach(predictionData, id: \.0) { name, values in
//            if let values = values {
//                ForEach(values.indices, id: \.self) { index in
//                    LineMark(
//                        x: .value("Time", timeForIndex(Int32(index))),
//                        y: .value("Value", Decimal(values[index]) * conversionFactor)
//                    )
//                    .foregroundStyle(by: .value("Prediction Type", name))
//                }
//            }
//        }
//    }

    private func drawCurrentTimeMarker() -> some ChartContent {
        RuleMark(
            x: .value(
                "",
                Date(timeIntervalSince1970: TimeInterval(NSDate().timeIntervalSince1970)),
                unit: .second
            )
        ).lineStyle(.init(lineWidth: 2, dash: [3])).foregroundStyle(Color(.systemGray2))
    }

    private var forecastChartXAxis: some AxisContent {
        AxisMarks(values: .stride(by: .hour, count: 2)) { _ in
            AxisGridLine(stroke: .init(lineWidth: 0.5, dash: [2, 3]))
            AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .narrow)), anchor: .top)
                .font(.footnote)
                .foregroundStyle(Color.primary)
        }
    }

    private var forecastChartYAxis: some AxisContent {
        AxisMarks(position: .trailing) { _ in
            AxisGridLine(stroke: .init(lineWidth: 0.5, dash: [2, 3]))
            AxisTick(length: 3, stroke: .init(lineWidth: 3)).foregroundStyle(Color.secondary)
            AxisValueLabel().font(.footnote).foregroundStyle(Color.primary)
        }
    }
}
