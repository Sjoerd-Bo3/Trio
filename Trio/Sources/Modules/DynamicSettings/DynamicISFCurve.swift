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

        @State private var selectedGlucose: Double?
        @State private var showDebugValues: Bool = false

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

        private var xAxisRange: ClosedRange<Double> {
            // Fixed scale based on units for consistent comparison
            if units == .mmolL {
                return 2.0 ... 22.0 // mmol/L range
            } else {
                return 40 ... 400 // mg/dL range
            }
        }

        private var yAxisRange: ClosedRange<Double> {
            // Fixed scale for ISF values based on units
            if units == .mmolL {
                return displayISF(20) ... displayISF(160) // Convert 20-160 mg/dL to mmol/L (≈1.1-8.9)
            } else {
                return 20 ... 160 // mg/dL range
            }
        }

        private func getAllISFValues() -> [Double] {
            var values: [Double] = []

            if showLogarithmicCurve {
                values.append(contentsOf: parameters.logarithmicChartData.map { displayISF($0.isf) })
                values.append(contentsOf: parameters.logarithmicUnboundedChartData.map { displayISF($0.isf) })
            }

            if showSigmoidCurve {
                values.append(contentsOf: parameters.sigmoidChartData.map { displayISF($0.isf) })
            }

            return values
        }

        private var logarithmicChartPoints: [ISFChartPoint] {
            // Split into within domain and outside domain for different styling
            let maxBoundedISF = parameters.logarithmicProfileISF / parameters.logarithmicAutosensMin
            let minBoundedISF = parameters.logarithmicProfileISF / parameters.logarithmicAutosensMax

            return parameters.logarithmicChartData.map { data in
                let isOutsideDomain = data.isf < minBoundedISF || data.isf > maxBoundedISF

                return ISFChartPoint(
                    glucose: parameters.displayGlucose(data.glucose, units: units),
                    isf: displayISF(data.isf),
                    formula: .logarithmic,
                    isOutsideDomain: isOutsideDomain
                )
            }
        }

        // Find intersection points for domain visualization
        private var domainIntersections: (maxIntersection: Double?, minIntersection: Double?) {
            let maxBoundedISF = parameters.logarithmicProfileISF / parameters.logarithmicAutosensMin
            let minBoundedISF = parameters.logarithmicProfileISF / parameters.logarithmicAutosensMax

            var maxIntersection: Double?
            var minIntersection: Double?

            // Find where curve intersects max and min bounds using crossing detection
            let chartData = parameters.logarithmicChartData
            for i in 0 ..< (chartData.count - 1) {
                let current = chartData[i]
                let next = chartData[i + 1]

                // Check for max bound crossing (curve going from above to below bound)
                if maxIntersection == nil {
                    if (current.isf >= maxBoundedISF && next.isf <= maxBoundedISF) ||
                        (current.isf <= maxBoundedISF && next.isf >= maxBoundedISF)
                    {
                        // Linear interpolation to find exact intersection
                        let ratio = (maxBoundedISF - current.isf) / (next.isf - current.isf)
                        let glucoseIntersection = current.glucose + ratio * (next.glucose - current.glucose)
                        maxIntersection = parameters.displayGlucose(glucoseIntersection, units: units)
                    }
                }

                // Check for min bound crossing (curve going from below to above bound)
                if minIntersection == nil {
                    if (current.isf >= minBoundedISF && next.isf <= minBoundedISF) ||
                        (current.isf <= minBoundedISF && next.isf >= minBoundedISF)
                    {
                        // Linear interpolation to find exact intersection
                        let ratio = (minBoundedISF - current.isf) / (next.isf - current.isf)
                        let glucoseIntersection = current.glucose + ratio * (next.glucose - current.glucose)
                        minIntersection = parameters.displayGlucose(glucoseIntersection, units: units)
                    }
                }

                // Early exit if both intersections found
                if maxIntersection != nil, minIntersection != nil {
                    break
                }
            }

            return (maxIntersection, minIntersection)
        }

        private var sigmoidChartPoints: [ISFChartPoint] {
            parameters.sigmoidChartData.map { data in
                ISFChartPoint(
                    glucose: parameters.displayGlucose(data.glucose, units: units),
                    isf: displayISF(data.isf),
                    formula: .sigmoid,
                    isOutsideDomain: false // Sigmoid doesn't have domain restrictions for styling
                )
            }
        }

        private var currentGlucoseMarker: ISFChartPoint? {
            guard let glucose = currentGlucose else { return nil }

            let currentISF: Double
            let clampedISF: Double

            switch parameters.activeFormula {
            case .logarithmic:
                let rawISF = parameters.logarithmicISF(glucose: glucose)
                currentISF = displayISF(rawISF)

                // Calculate clamped ISF based on autosens bounds
                let maxBoundedISF = parameters.logarithmicProfileISF / parameters.logarithmicAutosensMin
                let minBoundedISF = parameters.logarithmicProfileISF / parameters.logarithmicAutosensMax
                let clampedRawISF = min(max(rawISF, minBoundedISF), maxBoundedISF)
                clampedISF = displayISF(clampedRawISF)

            case .sigmoid:
                let rawISF = parameters.sigmoidISF(glucose: glucose)
                currentISF = displayISF(rawISF)
                clampedISF = currentISF // Sigmoid doesn't get clamped

            case .disabled:
                currentISF = displayISF(parameters.logarithmicProfileISF)
                clampedISF = currentISF
            }

            return ISFChartPoint(
                glucose: parameters.displayGlucose(glucose, units: units),
                isf: clampedISF, // Use clamped value for display
                formula: parameters.activeFormula,
                isOutsideDomain: abs(currentISF - clampedISF) > 0.1 // Mark as outside domain if clamping occurred
            )
        }

        private func getISFValues(for glucoseValue: Double) -> (logarithmic: Double?, sigmoid: Double?) {
            // Convert display glucose back to mg/dL for calculations
            let glucoseMgdL: Double
            if units == .mmolL {
                let decimal = Decimal(glucoseValue)
                glucoseMgdL = Double(decimal.asMgdL)
            } else {
                glucoseMgdL = glucoseValue
            }

            var logarithmicISF: Double?
            if showLogarithmicCurve {
                let rawISF = parameters.logarithmicISF(glucose: glucoseMgdL)
                // Apply clamping for logarithmic ISF
                let maxBoundedISF = parameters.logarithmicProfileISF / parameters.logarithmicAutosensMin
                let minBoundedISF = parameters.logarithmicProfileISF / parameters.logarithmicAutosensMax
                logarithmicISF = min(max(rawISF, minBoundedISF), maxBoundedISF)
            }

            let sigmoidISF = showSigmoidCurve ? parameters.sigmoidISF(glucose: glucoseMgdL) : nil

            return (logarithmic: logarithmicISF, sigmoid: sigmoidISF)
        }

        // Convert ISF to display units
        private func displayISF(_ isfMgdL: Double) -> Double {
            if units == .mmolL {
                return isfMgdL * 0.0555 // Convert mg/dL to mmol/L
            } else {
                return isfMgdL
            }
        }

        // ISF unit label
        private var isfUnitLabel: String {
            units == .mmolL ? "mmol/L/U" : "mg/dL/U"
        }

        private func updateSelectedGlucose(at location: CGPoint, geometry: GeometryProxy, chartProxy _: ChartProxy) {
            let relativeXPosition = location.x / geometry.size.width
            let glucoseRange = xAxisRange
            let glucoseValue = glucoseRange.lowerBound + (glucoseRange.upperBound - glucoseRange.lowerBound) * relativeXPosition

            selectedGlucose = max(glucoseRange.lowerBound, min(glucoseRange.upperBound, glucoseValue))
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                if !isPlayground {
                    HStack {
                        Text("Dynamic ISF Curves")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Spacer()
                        Button("Debug") {
                            showDebugValues = true
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                }

                Chart {
                    // ISF domain boundary visualization
                    if showLogarithmicCurve {
                        let maxBoundedISF = displayISF(parameters.logarithmicProfileISF / parameters.logarithmicAutosensMin)
                        let minBoundedISF = displayISF(parameters.logarithmicProfileISF / parameters.logarithmicAutosensMax)
                        
                        // Show autosens bounds as shaded area
                        AreaMark(
                            x: .value("Glucose", xAxisRange.lowerBound),
                            yStart: .value("Min ISF", minBoundedISF),
                            yEnd: .value("Max ISF", maxBoundedISF)
                        )
                        .foregroundStyle(.red.opacity(0.1))
                        
                        AreaMark(
                            x: .value("Glucose", xAxisRange.upperBound),
                            yStart: .value("Min ISF", minBoundedISF),
                            yEnd: .value("Max ISF", maxBoundedISF)
                        )
                        .foregroundStyle(.red.opacity(0.1))

                        // Boundary lines
                        RuleMark(y: .value("Max ISF", maxBoundedISF))
                            .foregroundStyle(.red.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [8, 4]))

                        RuleMark(y: .value("Min ISF", minBoundedISF))
                            .foregroundStyle(.red.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [8, 4]))
                    }

                    // Logarithmic curve - different styling for within/outside domain
                    if showLogarithmicCurve {
                        // Within domain - solid red line
                        ForEach(logarithmicChartPoints.filter { !$0.isOutsideDomain }) { point in
                            LineMark(
                                x: .value("Glucose", point.glucose),
                                y: .value("ISF", point.isf)
                            )
                            .foregroundStyle(by: .value("Formula", "Logarithmic"))
                            .lineStyle(StrokeStyle(lineWidth: isPlayground ? 3 : 2))
                        }

                        // Outside domain - dimmed dashed red line
                        ForEach(logarithmicChartPoints.filter { $0.isOutsideDomain }) { point in
                            LineMark(
                                x: .value("Glucose", point.glucose),
                                y: .value("ISF", point.isf)
                            )
                            .foregroundStyle(by: .value("Formula", "Logarithmic Outside"))
                            .lineStyle(StrokeStyle(lineWidth: isPlayground ? 2 : 1, dash: [6, 3]))
                        }

                        // Algorithm visualization - show where clamping occurs
                        let intersections = domainIntersections
                        let maxBoundedISF = displayISF(parameters.logarithmicProfileISF / parameters.logarithmicAutosensMin)
                        let minBoundedISF = displayISF(parameters.logarithmicProfileISF / parameters.logarithmicAutosensMax)

                        // Show autosens bounds as horizontal reference lines
                        RuleMark(y: .value("ISF", maxBoundedISF))
                            .foregroundStyle(.red.opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [6, 3]))

                        RuleMark(y: .value("ISF", minBoundedISF))
                            .foregroundStyle(.red.opacity(0.4))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [6, 3]))

                        // Show actual clamped behavior with solid lines
                        if let maxIntersection = intersections.maxIntersection {
                            // Solid horizontal line showing clamped ISF from left edge to intersection
                            LineMark(
                                x: .value("Glucose", xAxisRange.lowerBound),
                                y: .value("ISF", maxBoundedISF)
                            )
                            .foregroundStyle(.red.opacity(0.8))
                            .lineStyle(StrokeStyle(lineWidth: 2))

                            LineMark(
                                x: .value("Glucose", maxIntersection),
                                y: .value("ISF", maxBoundedISF)
                            )
                            .foregroundStyle(.red.opacity(0.8))
                            .lineStyle(StrokeStyle(lineWidth: 2))

                            // Vertical marker at intersection point
                            RuleMark(x: .value("Glucose", maxIntersection))
                                .foregroundStyle(.red.opacity(0.6))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 2]))

                            // Add intersection point marker
                            PointMark(
                                x: .value("Glucose", maxIntersection),
                                y: .value("ISF", maxBoundedISF)
                            )
                            .foregroundStyle(.red)
                            .symbolSize(36)
                            .symbol(.circle)
                        }

                        if let minIntersection = intersections.minIntersection {
                            // Solid horizontal line showing clamped ISF from intersection to right edge
                            LineMark(
                                x: .value("Glucose", minIntersection),
                                y: .value("ISF", minBoundedISF)
                            )
                            .foregroundStyle(.red.opacity(0.8))
                            .lineStyle(StrokeStyle(lineWidth: 2))

                            LineMark(
                                x: .value("Glucose", xAxisRange.upperBound),
                                y: .value("ISF", minBoundedISF)
                            )
                            .foregroundStyle(.red.opacity(0.8))
                            .lineStyle(StrokeStyle(lineWidth: 2))

                            // Vertical marker at intersection point
                            RuleMark(x: .value("Glucose", minIntersection))
                                .foregroundStyle(.red.opacity(0.6))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 2]))

                            // Add intersection point marker
                            PointMark(
                                x: .value("Glucose", minIntersection),
                                y: .value("ISF", minBoundedISF)
                            )
                            .foregroundStyle(.red)
                            .symbolSize(36)
                            .symbol(.circle)
                        }
                    }

                    // Sigmoid curve
                    if showSigmoidCurve {
                        ForEach(sigmoidChartPoints) { point in
                            LineMark(
                                x: .value("Glucose", point.glucose),
                                y: .value("ISF", point.isf)
                            )
                            .foregroundStyle(by: .value("Formula", "Sigmoid"))
                            .lineStyle(StrokeStyle(lineWidth: isPlayground ? 3 : 2))
                        }
                    }

                    // Current glucose marker
                    if let marker = currentGlucoseMarker {
                        PointMark(
                            x: .value("Glucose", marker.glucose),
                            y: .value("ISF", marker.isf)
                        )
                        .foregroundStyle(by: .value("Formula", "Current"))
                        .symbolSize(isPlayground ? 100 : 64)
                        .symbol {
                            Image(systemName: "circle.fill")
                                .foregroundStyle(Color.insulin)
                        }
                    }

                    // Selection overlay points
                    if let selectedGlucose = selectedGlucose {
                        let isfValues = getISFValues(for: selectedGlucose)

                        if let logarithmicISF = isfValues.logarithmic {
                            PointMark(
                                x: .value("Glucose", selectedGlucose),
                                y: .value("ISF", displayISF(logarithmicISF))
                            )
                            .foregroundStyle(.blue)
                            .symbolSize(64)
                        }

                        if let sigmoidISF = isfValues.sigmoid {
                            PointMark(
                                x: .value("Glucose", selectedGlucose),
                                y: .value("ISF", displayISF(sigmoidISF))
                            )
                            .foregroundStyle(.orange)
                            .symbolSize(64)
                        }
                    }
                }
                .frame(height: chartHeight)
                .chartXScale(domain: xAxisRange)
                .chartYScale(domain: yAxisRange)
                .chartForegroundStyleScale([
                    "Logarithmic": .red,
                    "Logarithmic Outside": .red.opacity(0.4),
                    "Sigmoid": .green,
                    "Current": Color.insulin
                ])
                .chartXSelection(value: .constant(selectedGlucose))
                .chartBackground { chartProxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .onTapGesture { location in
                                updateSelectedGlucose(at: location, geometry: geometry, chartProxy: chartProxy)
                            }
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        updateSelectedGlucose(at: value.location, geometry: geometry, chartProxy: chartProxy)
                                    }
                                    .onEnded { _ in
                                        selectedGlucose = nil
                                    }
                            )
                    }
                }
                .chartXAxis {
                    AxisMarks(position: .bottom) { value in
                        AxisGridLine(stroke: .init(lineWidth: 0.5, dash: [2, 3]))
                        if let glucoseValue = value.as(Double.self) {
                            // Check if this is an intersection point - only when logarithmic is visible
                            let isMaxIntersection = showLogarithmicCurve ?
                                (domainIntersections.maxIntersection.map { abs($0 - glucoseValue) < 1.0 } ?? false) : false
                            let isMinIntersection = showLogarithmicCurve ?
                                (domainIntersections.minIntersection.map { abs($0 - glucoseValue) < 1.0 } ?? false) : false

                            AxisValueLabel {
                                Text(String(format: units == .mmolL ? "%.1f" : "%.0f", glucoseValue))
                                    .font(.footnote)
                                    .foregroundStyle(
                                        (isMaxIntersection || isMinIntersection) && showLogarithmicCurve ? .red :
                                            Color.primary
                                    )
                                    .fontWeight(
                                        (isMaxIntersection || isMinIntersection) && showLogarithmicCurve ? .semibold :
                                            .regular
                                    )
                            }
                        }
                    }

                    // Add custom marks for intersection points - only when logarithmic is visible
                    if showLogarithmicCurve {
                        let intersections = domainIntersections
                        if let maxIntersection = intersections.maxIntersection {
                            AxisMarks(values: [maxIntersection]) { _ in
                                AxisValueLabel {
                                    Text(String(format: units == .mmolL ? "%.1f" : "%.0f", maxIntersection))
                                        .font(.footnote)
                                        .foregroundStyle(.red)
                                        .fontWeight(.semibold)
                                }
                            }
                        }

                        if let minIntersection = intersections.minIntersection {
                            AxisMarks(values: [minIntersection]) { _ in
                                AxisValueLabel {
                                    Text(String(format: units == .mmolL ? "%.1f" : "%.0f", minIntersection))
                                        .font(.footnote)
                                        .foregroundStyle(.red)
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing) { value in
                        AxisGridLine(stroke: .init(lineWidth: 0.5, dash: [2, 3]))
                        if let isfValue = value.as(Double.self), isfValue >= 0 {
                            // Check if this is an intersection ISF value - only when logarithmic is visible
                            let intersections = domainIntersections
                            let maxBoundedISF = displayISF(parameters.logarithmicProfileISF / parameters.logarithmicAutosensMin)
                            let minBoundedISF = displayISF(parameters.logarithmicProfileISF / parameters.logarithmicAutosensMax)
                            let isMaxISF = showLogarithmicCurve && abs(isfValue - maxBoundedISF) < (units == .mmolL ? 0.05 : 1.0)
                            let isMinISF = showLogarithmicCurve && abs(isfValue - minBoundedISF) < (units == .mmolL ? 0.05 : 1.0)

                            AxisValueLabel {
                                Text(isfValue.formatted(.number.precision(.fractionLength(0))))
                                    .font(.footnote)
                                    .foregroundStyle(isMaxISF || isMinISF ? .red : Color.primary)
                                    .fontWeight(isMaxISF || isMinISF ? .semibold : .regular)
                            }
                        }
                    }

                    // Add custom marks for intersection ISF values - only when logarithmic is visible
                    if showLogarithmicCurve {
                        let maxBoundedISF = displayISF(parameters.logarithmicProfileISF / parameters.logarithmicAutosensMin)
                        let minBoundedISF = displayISF(parameters.logarithmicProfileISF / parameters.logarithmicAutosensMax)

                        AxisMarks(values: [maxBoundedISF]) { _ in
                            AxisValueLabel {
                                Text(maxBoundedISF.formatted(.number.precision(.fractionLength(0))))
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                                    .fontWeight(.semibold)
                            }
                        }

                        AxisMarks(values: [minBoundedISF]) { _ in
                            AxisValueLabel {
                                Text(minBoundedISF.formatted(.number.precision(.fractionLength(0))))
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                }
                .chartYAxisLabel(position: .trailing, alignment: .center) {
                    Text("ISF (\(isfUnitLabel))")
                        .font(.footnote)
                        .foregroundStyle(.primary)
                        .padding(.leading, 8)
                }
                .chartXAxisLabel(position: .bottom, alignment: .center) {
                    Text("Glucose (\(units.rawValue))")
                        .font(.footnote)
                        .foregroundStyle(.primary)
                        .padding(.top, 4)
                }
                .background(Color.chart)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .overlay(alignment: .topTrailing) {
                // Selection popover
                if let selectedGlucose = selectedGlucose {
                    selectionPopover(for: selectedGlucose)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                        .animation(.easeInOut(duration: 0.2), value: selectedGlucose)
                }
            }
            .sheet(isPresented: $showDebugValues) {
                debugValuesSheet
            }
        }

        @ViewBuilder private func selectionPopover(for glucoseValue: Double) -> some View {
            let isfValues = getISFValues(for: glucoseValue)

            VStack(alignment: .leading, spacing: 4) {
                Text("Glucose: \(String(format: units == .mmolL ? "%.1f" : "%.0f", glucoseValue)) \(units.rawValue)")
                    .font(.caption)
                    .fontWeight(.medium)

                if let logarithmicISF = isfValues.logarithmic {
                    HStack {
                        Circle()
                            .fill(.red)
                            .frame(width: 8, height: 8)
                        Text(
                            "Log ISF: \(String(format: units == .mmolL ? "%.1f" : "%.0f", displayISF(logarithmicISF))) \(isfUnitLabel)"
                        )
                        .font(.caption)
                    }
                }

                if let sigmoidISF = isfValues.sigmoid {
                    HStack {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                        Text(
                            "Sigmoid ISF: \(String(format: units == .mmolL ? "%.1f" : "%.0f", displayISF(sigmoidISF))) \(isfUnitLabel)"
                        )
                        .font(.caption)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(.regularMaterial)
                    .shadow(radius: 4)
            )
            .padding(.trailing, 8)
            .padding(.top, 8)
        }

        private var debugValuesSheet: some View {
            NavigationView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        parametersSection
                        isfValuesTable
                    }
                    .padding()
                }
                .navigationTitle("Debug Values")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            showDebugValues = false
                        }
                    }
                }
            }
        }

        private var parametersSection: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("Current Parameters")
                    .font(.headline)
                    .foregroundColor(.primary)

                Group {
                    Text("TDD 24h: \(String(format: "%.0f", parameters.tdd24hr))U")
                    Text("TDD 2w: \(String(format: "%.0f", parameters.tdd2weeks))U")
                    Text("Weighted TDD: \(String(format: "%.1f", parameters.weightedTDD))U")
                    Text("Insulin Factor: \(String(format: "%.0f", parameters.insulinFactor))")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }

        private var isfValuesTable: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text("ISF Values at Test Points")
                    .font(.headline)
                    .foregroundColor(.primary)

                tableHeader
                tableRows
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }

        private var tableHeader: some View {
            HStack {
                Text("Glucose")
                    .font(.caption)
                    .fontWeight(.medium)
                    .frame(minWidth: 60, alignment: .leading)

                Text("Logarithmic")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.red)
                    .frame(minWidth: 80, alignment: .center)

                Text("Sigmoid")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.green)
                    .frame(minWidth: 80, alignment: .center)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.1))
        }

        private var tableRows: some View {
            LazyVStack(spacing: 0) {
                ForEach([40, 55, 70, 100, 140, 180, 250, 400], id: \.self) { glucoseMgdL in
                    tableRow(for: glucoseMgdL)
                }
            }
        }

        private func tableRow(for glucoseMgdL: Double) -> some View {
            let displayGlucose = parameters.displayGlucose(glucoseMgdL, units: units)
            let logISF = displayISF(parameters.logarithmicISF(glucose: glucoseMgdL))
            let sigISF = displayISF(parameters.sigmoidISF(glucose: glucoseMgdL))

            return HStack {
                Text(String(format: units == .mmolL ? "%.1f" : "%.0f", displayGlucose))
                    .font(.caption)
                    .monospacedDigit()
                    .frame(minWidth: 60, alignment: .leading)

                Text(String(format: "%.5g", logISF))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundColor(.red)
                    .frame(minWidth: 80, alignment: .center)

                Text(String(format: "%.5g", sigISF))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundColor(.green)
                    .frame(minWidth: 80, alignment: .center)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
    }
}
