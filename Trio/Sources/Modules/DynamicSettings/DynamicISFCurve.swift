import Charts
import Foundation
import SwiftUI

extension DynamicSettings {
    struct ISFCurveView: View {
        let parameters: ISFParameters
        let units: GlucoseUnits
        let showLogarithmicCurve: Bool
        let showSigmoidCurve: Bool
        let currentGlucose: Double?
        let isPlayground: Bool

        init(
            parameters: ISFParameters,
            units: GlucoseUnits,
            showLogarithmicCurve: Bool = true,
            showSigmoidCurve: Bool = true,
            currentGlucose: Double? = nil,
            isPlayground: Bool = false
        ) {
            self.parameters = parameters
            self.units = units
            self.showLogarithmicCurve = showLogarithmicCurve
            self.showSigmoidCurve = showSigmoidCurve
            self.currentGlucose = currentGlucose
            self.isPlayground = isPlayground
        }

        private var chartHeight: CGFloat {
            isPlayground ? 300 : 200
        }

        private var yAxisRange: ClosedRange<Double> {
            let allISFValues = getAllISFValues()
            let minISF = allISFValues.min() ?? 50
            let maxISF = allISFValues.max() ?? 200
            let padding = (maxISF - minISF) * 0.1
            return (minISF - padding) ... (maxISF + padding)
        }

        private var xAxisRange: ClosedRange<Double> {
            let glucoseValues = parameters.displayGlucoseDataPoints(units: units)
            let minGlucose = glucoseValues.min() ?? 2.0
            let maxGlucose = glucoseValues.max() ?? 22.0
            return minGlucose ... maxGlucose
        }

        private func getAllISFValues() -> [Double] {
            var values: [Double] = []

            if showLogarithmicCurve {
                values.append(contentsOf: parameters.logarithmicChartData.map(\.isf))
            }

            if showSigmoidCurve {
                values.append(contentsOf: parameters.sigmoidChartData.map(\.isf))
            }

            return values
        }

        private var logarithmicChartPoints: [ISFChartPoint] {
            parameters.logarithmicChartData.map { data in
                ISFChartPoint(
                    glucose: parameters.displayGlucose(data.glucose, units: units),
                    isf: data.isf,
                    formula: .logarithmic
                )
            }
        }

        private var sigmoidChartPoints: [ISFChartPoint] {
            parameters.sigmoidChartData.map { data in
                ISFChartPoint(
                    glucose: parameters.displayGlucose(data.glucose, units: units),
                    isf: data.isf,
                    formula: .sigmoid
                )
            }
        }

        private var currentGlucoseMarker: ISFChartPoint? {
            guard let glucose = currentGlucose else { return nil }

            let currentISF: Double
            switch parameters.activeFormula {
            case .logarithmic:
                currentISF = parameters.logarithmicISF(glucose: glucose)
            case .sigmoid:
                currentISF = parameters.sigmoidISF(glucose: glucose)
            case .disabled:
                currentISF = parameters.logarithmicProfileISF
            }

            return ISFChartPoint(
                glucose: parameters.displayGlucose(glucose, units: units),
                isf: currentISF,
                formula: parameters.activeFormula
            )
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                if !isPlayground {
                    Text("Dynamic ISF Curves")
                        .font(.headline)
                        .foregroundColor(.primary)
                }

                Chart {
                    // Logarithmic curve
                    if showLogarithmicCurve {
                        ForEach(logarithmicChartPoints) { point in
                            LineMark(
                                x: .value("Glucose", point.glucose),
                                y: .value("ISF", point.isf)
                            )
                            .foregroundStyle(.blue)
                            .lineStyle(.init(lineWidth: isPlayground ? 3 : 2))
                        }
                    }

                    // Sigmoid curve
                    if showSigmoidCurve {
                        ForEach(sigmoidChartPoints) { point in
                            LineMark(
                                x: .value("Glucose", point.glucose),
                                y: .value("ISF", point.isf)
                            )
                            .foregroundStyle(.red)
                            .lineStyle(.init(lineWidth: isPlayground ? 3 : 2))
                        }
                    }

                    // Current glucose marker
                    if let marker = currentGlucoseMarker {
                        PointMark(
                            x: .value("Glucose", marker.glucose),
                            y: .value("ISF", marker.isf)
                        )
                        .foregroundStyle(Color.insulin)
                        .symbolSize(isPlayground ? 100 : 64)
                        .symbol {
                            Image(systemName: "circle.fill")
                                .foregroundStyle(Color.insulin)
                        }
                    }
                }
                .frame(height: chartHeight)
                .chartXScale(domain: xAxisRange)
                .chartYScale(domain: yAxisRange)
                .chartXAxis {
                    AxisMarks(position: .bottom) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let glucoseValue = value.as(Double.self) {
                                Text(String(format: units == .mmolL ? "%.1f" : "%.0f", glucoseValue))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let isfValue = value.as(Double.self) {
                                Text(String(format: "%.0f", isfValue))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .background(Color.chart)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Axis labels
                if isPlayground {
                    HStack {
                        Text("Glucose (\(units.rawValue))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("ISF (mg/dL/U)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
}
