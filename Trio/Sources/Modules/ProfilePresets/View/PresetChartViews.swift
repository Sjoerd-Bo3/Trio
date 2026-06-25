import Charts
import SwiftUI

extension ProfilePresets {
    /// Non-editable chart view for basal rates matching the settings page layout
    struct BasalChartView: View {
        let basalProfile: [BasalProfileEntry]

        private let now = Date()

        var body: some View {
            Chart {
                ForEach(Array(basalProfile.enumerated()), id: \.offset) { index, entry in
                    let startDate = Calendar.current
                        .startOfDay(for: now)
                        .addingTimeInterval(TimeInterval(entry.minutes * 60))

                    let endMinutes: Int = {
                        if index + 1 < basalProfile.count {
                            return basalProfile[index + 1].minutes
                        }
                        return 24 * 60
                    }()

                    let endDate = Calendar.current
                        .startOfDay(for: now)
                        .addingTimeInterval(TimeInterval(endMinutes * 60))

                    let rate = NSDecimalNumber(decimal: entry.rate).doubleValue

                    RectangleMark(
                        xStart: .value("start", startDate),
                        xEnd: .value("end", endDate),
                        yStart: .value("rate-start", rate),
                        yEnd: .value("rate-end", 0)
                    ).foregroundStyle(
                        .linearGradient(
                            colors: [
                                Color.purple.opacity(0.6),
                                Color.purple.opacity(0.1)
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    ).alignsMarkStylesWithPlotArea()

                    LineMark(x: .value("End Date", startDate), y: .value("Rate", rate))
                        .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.purple)

                    LineMark(x: .value("Start Date", endDate), y: .value("Rate", rate))
                        .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.purple)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisValueLabel(format: .dateTime.hour())
                    AxisGridLine(centered: true, stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                }
            }
            .chartXScale(
                domain: Calendar.current.startOfDay(for: now) ... Calendar.current.startOfDay(for: now)
                    .addingTimeInterval(60 * 60 * 24)
            )
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisValueLabel()
                    AxisGridLine(centered: true, stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                }
            }
            .frame(height: 180)
        }
    }

    /// Non-editable chart view for ISF values matching the settings page layout
    struct ISFChartView: View {
        let sensitivities: [InsulinSensitivityEntry]
        let units: GlucoseUnits

        private let now = Date()

        var body: some View {
            Chart {
                ForEach(Array(sensitivities.enumerated()), id: \.offset) { index, entry in
                    let displayValue = units == .mgdL
                        ? NSDecimalNumber(decimal: entry.sensitivity).doubleValue
                        : NSDecimalNumber(decimal: entry.sensitivity.asMmolL).doubleValue

                    let startDate = Calendar.current
                        .startOfDay(for: now)
                        .addingTimeInterval(TimeInterval(entry.offset * 60))

                    let endMinutes: Int = {
                        if index + 1 < sensitivities.count {
                            return sensitivities[index + 1].offset
                        }
                        return 24 * 60
                    }()

                    let endDate = Calendar.current
                        .startOfDay(for: now)
                        .addingTimeInterval(TimeInterval(endMinutes * 60))

                    RectangleMark(
                        xStart: .value("start", startDate),
                        xEnd: .value("end", endDate),
                        yStart: .value("rate-start", displayValue),
                        yEnd: .value("rate-end", 0)
                    ).foregroundStyle(
                        .linearGradient(
                            colors: [
                                Color.cyan.opacity(0.6),
                                Color.cyan.opacity(0.1)
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    ).alignsMarkStylesWithPlotArea()

                    LineMark(x: .value("End Date", startDate), y: .value("ISF", displayValue))
                        .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.cyan)

                    LineMark(x: .value("Start Date", endDate), y: .value("ISF", displayValue))
                        .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.cyan)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisValueLabel(format: .dateTime.hour())
                    AxisGridLine(centered: true, stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                }
            }
            .chartXScale(
                domain: Calendar.current.startOfDay(for: now) ... Calendar.current.startOfDay(for: now)
                    .addingTimeInterval(60 * 60 * 24)
            )
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisValueLabel()
                    AxisGridLine(centered: true, stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                }
            }
            .frame(height: 180)
        }
    }

    /// Non-editable chart view for carb ratios matching the settings page layout
    struct CRChartView: View {
        let schedule: [CarbRatioEntry]

        private let now = Date()

        var body: some View {
            Chart {
                ForEach(Array(schedule.enumerated()), id: \.offset) { index, entry in
                    let displayValue = NSDecimalNumber(decimal: entry.ratio).doubleValue

                    let startDate = Calendar.current
                        .startOfDay(for: now)
                        .addingTimeInterval(TimeInterval(entry.offset * 60))

                    let endMinutes: Int = {
                        if index + 1 < schedule.count {
                            return schedule[index + 1].offset
                        }
                        return 24 * 60
                    }()

                    let endDate = Calendar.current
                        .startOfDay(for: now)
                        .addingTimeInterval(TimeInterval(endMinutes * 60))

                    RectangleMark(
                        xStart: .value("start", startDate),
                        xEnd: .value("end", endDate),
                        yStart: .value("rate-start", displayValue),
                        yEnd: .value("rate-end", 0)
                    ).foregroundStyle(
                        .linearGradient(
                            colors: [
                                Color.orange.opacity(0.6),
                                Color.orange.opacity(0.1)
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    ).alignsMarkStylesWithPlotArea()

                    LineMark(x: .value("End Date", startDate), y: .value("Ratio", displayValue))
                        .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.orange)

                    LineMark(x: .value("Start Date", endDate), y: .value("Ratio", displayValue))
                        .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.orange)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisValueLabel(format: .dateTime.hour())
                    AxisGridLine(centered: true, stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                }
            }
            .chartXScale(
                domain: Calendar.current.startOfDay(for: now) ... Calendar.current.startOfDay(for: now)
                    .addingTimeInterval(60 * 60 * 24)
            )
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisValueLabel()
                    AxisGridLine(centered: true, stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                }
            }
            .frame(height: 180)
        }
    }

    /// Non-editable chart view for glucose targets
    struct TargetsChartView: View {
        let targets: [BGTargetEntry]
        let units: GlucoseUnits

        private let now = Date()

        var body: some View {
            Chart {
                ForEach(Array(targets.enumerated()), id: \.offset) { index, entry in
                    let lowValue = units == .mgdL
                        ? NSDecimalNumber(decimal: entry.low).doubleValue
                        : NSDecimalNumber(decimal: entry.low.asMmolL).doubleValue
                    let highValue = units == .mgdL
                        ? NSDecimalNumber(decimal: entry.high).doubleValue
                        : NSDecimalNumber(decimal: entry.high.asMmolL).doubleValue

                    let startDate = Calendar.current
                        .startOfDay(for: now)
                        .addingTimeInterval(TimeInterval(entry.offset * 60))

                    let endMinutes: Int = {
                        if index + 1 < targets.count {
                            return targets[index + 1].offset
                        }
                        return 24 * 60
                    }()

                    let endDate = Calendar.current
                        .startOfDay(for: now)
                        .addingTimeInterval(TimeInterval(endMinutes * 60))

                    RectangleMark(
                        xStart: .value("start", startDate),
                        xEnd: .value("end", endDate),
                        yStart: .value("low", lowValue),
                        yEnd: .value("high", highValue)
                    ).foregroundStyle(
                        Color.loopGreen.opacity(0.3)
                    ).alignsMarkStylesWithPlotArea()

                    LineMark(x: .value("Start", startDate), y: .value("Low", lowValue))
                        .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.loopGreen)
                    LineMark(x: .value("End", endDate), y: .value("Low", lowValue))
                        .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.loopGreen)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisValueLabel(format: .dateTime.hour())
                    AxisGridLine(centered: true, stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                }
            }
            .chartXScale(
                domain: Calendar.current.startOfDay(for: now) ... Calendar.current.startOfDay(for: now)
                    .addingTimeInterval(60 * 60 * 24)
            )
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisValueLabel()
                    AxisGridLine(centered: true, stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                }
            }
            .frame(height: 180)
        }
    }
}
