import ActivityKit
import Charts
import SwiftUI
import WidgetKit

private enum Size {
    case minimal
    case compact
    case expanded
}

struct LiveActivity: Widget {
    private let dateFormatter: DateFormatter = {
        var f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    private var bolusFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.decimalSeparator = "."
        return formatter
    }

    private var carbsFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }

    @ViewBuilder private func changeLabel(context: ActivityViewContext<LiveActivityAttributes>) -> some View {
        if !context.state.change.isEmpty {
            if context.isStale {
                Text(context.state.change).foregroundStyle(.primary.opacity(0.5)).font(.headline)
                    .strikethrough(pattern: .solid, color: .red.opacity(0.6)).font(.callout)
            } else {
                HStack {
                    Text(context.state.change).font(.headline)
                }
            }
        } else {
            Text("--")
        }
    }

    @ViewBuilder func mealLabel(context: ActivityViewContext<LiveActivityAttributes>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1, content: {
                HStack {
                    Image(systemName: "fork.knife")
                        .font(.title3)
                        .foregroundColor(.yellow)
                }
                HStack {
                    Image(systemName: "syringe.fill")
                        .font(.title3)
                        .foregroundColor(.blue)
                }
            })
            VStack(alignment: .trailing, spacing: 1, content: {
                HStack {
                    if context.isStale {
                        Text(
                            carbsFormatter.string(from: context.state.cob as NSNumber) ?? "--"
                        ).fontWeight(.bold).font(.headline).strikethrough(pattern: .solid, color: .red.opacity(0.6))
                            .font(.callout)
                        Text(NSLocalizedString(" g", comment: "grams of carbs")).foregroundStyle(.secondary).font(.footnote)
                    } else {
                        Text(
                            carbsFormatter.string(from: context.state.cob as NSNumber) ?? "--"
                        ).fontWeight(.bold).font(.headline)
                        Text(NSLocalizedString(" g", comment: "grams of carbs")).foregroundStyle(.secondary).font(.footnote)
                    }
                }
                HStack {
                    if context.isStale {
                        Text(
                            bolusFormatter.string(from: context.state.iob as NSNumber) ?? "--"
                        ).font(.headline).fontWeight(.bold).strikethrough(pattern: .solid, color: .red.opacity(0.6))
                            .font(.callout)
                        Text(NSLocalizedString(" U", comment: "Unit in number of units delivered (keep the space character!)"))
                            .foregroundStyle(.secondary).font(.footnote)
                    } else {
                        Text(
                            bolusFormatter.string(from: context.state.iob as NSNumber) ?? "--"
                        ).font(.headline).fontWeight(.bold)
                        Text(NSLocalizedString(" U", comment: "Unit in number of units delivered (keep the space character!)"))
                            .foregroundStyle(.secondary).font(.footnote)
                    }
                }
            })
        }
    }

    @ViewBuilder func trend(context: ActivityViewContext<LiveActivityAttributes>) -> some View {
        if context.isStale {
            Text("--")
        } else {
            if let trendSystemImage = context.state.direction {
                Image(systemName: trendSystemImage)
            }
        }
    }

    private func updatedLabel(context: ActivityViewContext<LiveActivityAttributes>) -> Text {
        let text = Text("Updated: \(dateFormatter.string(from: context.state.date))")
            .font(.caption2)
        if context.isStale {
            // foregroundStyle is not available in <iOS 17 hence the check here
            if #available(iOSApplicationExtension 17.0, *) {
                return text.bold().foregroundStyle(.red)
            } else {
                return text.bold().foregroundColor(.red)
            }
        } else {
            if #available(iOSApplicationExtension 17.0, *) {
                return text.bold().foregroundStyle(.secondary)
            } else {
                return text.bold().foregroundColor(.red)
            }
        }
    }

    @ViewBuilder private func bgLabel(context: ActivityViewContext<LiveActivityAttributes>) -> some View {
        HStack(alignment: .center) {
            Text(context.state.bg)
                .fontWeight(.bold)
                .font(.largeTitle)
                .strikethrough(context.isStale, pattern: .solid, color: .red.opacity(0.6))
            Text(context.state.unit).foregroundStyle(.secondary).font(.subheadline).offset(x: -5, y: 5)
        }
    }

    private func bgAndTrend(context: ActivityViewContext<LiveActivityAttributes>, size: Size) -> (some View, Int) {
        var characters = 0

        let bgText = context.state.bg
        characters += bgText.count

        // narrow mode is for the minimal dynamic island view
        // there is not enough space to show all three arrow there
        // and everything has to be squeezed together to some degree
        // only display the first arrow character and make it red in case there were more characters
        var directionText: String?
        var warnColor: Color?
        if let direction = context.state.direction {
            if size == .compact {
                directionText = String(direction[direction.startIndex ... direction.startIndex])

                if direction.count > 1 {
                    warnColor = Color.red
                }
            } else {
                directionText = direction
            }

            characters += directionText!.count
        }

        let spacing: CGFloat
        switch size {
        case .minimal: spacing = -1
        case .compact: spacing = 0
        case .expanded: spacing = 3
        }

        let stack = HStack(spacing: spacing) {
            Text(bgText)
                .strikethrough(context.isStale, pattern: .solid, color: .red.opacity(0.6))
            if let direction = directionText {
                let text = Text(direction)
                switch size {
                case .minimal:
                    let scaledText = text.scaleEffect(x: 0.7, y: 0.7, anchor: .leading)
                    if let warnColor {
                        scaledText.foregroundStyle(warnColor)
                    } else {
                        scaledText
                    }
                case .compact:
                    text.scaleEffect(x: 0.8, y: 0.8, anchor: .leading).padding(.trailing, -3)

                case .expanded:
                    text.scaleEffect(x: 0.7, y: 0.7, anchor: .leading).padding(.trailing, -5)
                }
            }
        }
        .foregroundStyle(context.isStale ? Color.primary.opacity(0.5) : Color.primary)

        return (stack, characters)
    }

    @ViewBuilder func bobble(context: ActivityViewContext<LiveActivityAttributes>) -> some View {
        let gradient = LinearGradient(colors: [
            Color(red: 0.6235294118, green: 0.4235294118, blue: 0.9803921569),
            Color(red: 0.4862745098, green: 0.5450980392, blue: 0.9529411765),
            Color(red: 0.3411764706, green: 0.6666666667, blue: 0.9254901961),
            Color(red: 0.262745098, green: 0.7333333333, blue: 0.9137254902)
        ], startPoint: .leading, endPoint: .trailing)

        if !context.isStale {
            Image(systemName: "arrow.right")
                .font(.title)
                .rotationEffect(.degrees(context.state.rotationDegrees))
                .foregroundStyle(gradient)
        }
    }

    @ViewBuilder func chart(context: ActivityViewContext<LiveActivityAttributes>) -> some View {
        if context.isStale {
            Text("No data available")
        } else {
            // determine scale
            let min = (context.state.chart.min() ?? 40 * (context.state.unit == " mmol/L" ? 0.0555 : 1)) - 20 *
                (context.state.unit == " mmol/L" ? 0.0555 : 1)
            let max = (context.state.chart.max() ?? 270 * (context.state.unit == " mmol/L" ? 0.0555 : 1)) + 50 *
                (context.state.unit == " mmol/L" ? 0.0555 : 1)

            Chart {
                RuleMark(y: .value("high", context.state.highGlucose))
                    .lineStyle(.init(lineWidth: 0.5, dash: [5]))
                RuleMark(y: .value("low", context.state.lowGlucose))
                    .lineStyle(.init(lineWidth: 0.5, dash: [5]))
                ForEach(context.state.chart.indices, id: \.self) { index in
                    let currentValue = context.state.chart[index]
                    if currentValue > context.state.highGlucose {
                        PointMark(
                            x: .value("Time", context.state.chartDate[index] ?? Date()),
                            y: .value("Value", currentValue)
                        ).foregroundStyle(Color.orange.gradient).symbolSize(15)
                    } else if currentValue < context.state.lowGlucose {
                        PointMark(
                            x: .value("Time", context.state.chartDate[index] ?? Date()),
                            y: .value("Value", currentValue)
                        ).foregroundStyle(Color.red.gradient).symbolSize(15)
                    } else {
                        PointMark(
                            x: .value("Time", context.state.chartDate[index] ?? Date()),
                            y: .value("Value", currentValue)
                        ).foregroundStyle(Color.green.gradient).symbolSize(15)
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { _ in
                    AxisGridLine(stroke: .init(lineWidth: 0.2, dash: [2, 3])).foregroundStyle(Color.white)
                    AxisValueLabel().foregroundStyle(Color.secondary).font(.footnote)
                }
            }
            .chartYScale(domain: min ... max)
            .chartXAxis {
                AxisMarks(position: .automatic) { _ in
                    AxisGridLine(stroke: .init(lineWidth: 0.2, dash: [2, 3])).foregroundStyle(Color.white)
                }
            }
        }
    }

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveActivityAttributes.self) { context in
            // Lock screen/banner UI goes here
            if context.state.lockScreenView == "Simple" {
                HStack(spacing: 3) {
                    bgAndTrend(context: context, size: .expanded).0.font(.title)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 5) {
                        changeLabel(context: context).font(.title3)
                        updatedLabel(context: context).font(.caption).foregroundStyle(.primary.opacity(0.7))
                    }
                }
                .privacySensitive()
                .padding(.all, 15)
                // Semantic BackgroundStyle and Color values work here. They adapt to the given interface style (light mode, dark mode)
                // Semantic UIColors do NOT (as of iOS 17.1.1). Like UIColor.systemBackgroundColor (it does not adapt to changes of the interface style)
                // The colorScheme environment varaible that is usually used to detect dark mode does NOT work here (it reports false values)
                .foregroundStyle(Color.primary)
                .background(BackgroundStyle.background.opacity(0.4))
                .activityBackgroundTint(Color.clear)
            } else {
                HStack(spacing: 12) {
                    chart(context: context).frame(width: UIScreen.main.bounds.width / 1.8)
                    VStack(alignment: .leading) {
                        Spacer()
                        bgLabel(context: context)
                        HStack {
                            changeLabel(context: context)
                            bobble(context: context)
                        }
                        mealLabel(context: context).padding(.bottom, 8)
                        updatedLabel(context: context).padding(.bottom, 10)
                    }
                }
                .privacySensitive()
                .padding(.all, 14)
                .imageScale(.small)
                .foregroundColor(Color.white)
                .activityBackgroundTint(Color.black)
            }
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    bgAndTrend(context: context, size: .expanded).0.font(.title2).padding(.leading, 5)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    changeLabel(context: context).font(.title2).padding(.trailing, 5)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.lockScreenView == "Simple" {
                        Group {
                            updatedLabel(context: context).font(.caption).foregroundStyle(Color.secondary)
                        }
                        .frame(
                            maxHeight: .infinity,
                            alignment: .bottom
                        )
                    } else {
                        chart(context: context)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    if context.state.lockScreenView == "Detailed" {
                        updatedLabel(context: context).font(.caption).foregroundStyle(Color.secondary)
                    }
                }
            } compactLeading: {
                bgAndTrend(context: context, size: .compact).0.padding(.leading, 4)
            } compactTrailing: {
                changeLabel(context: context).padding(.trailing, 4)
            } minimal: {
                let (_label, characterCount) = bgAndTrend(context: context, size: .minimal)

                let label = _label.padding(.leading, 7).padding(.trailing, 3)

                if characterCount < 4 {
                    label
                } else if characterCount < 5 {
                    label.fontWidth(.condensed)
                } else {
                    label.fontWidth(.compressed)
                }
            }
            .widgetURL(URL(string: "freeaps-x://"))
            .keylineTint(Color.purple)
            .contentMargins(.horizontal, 0, for: .minimal)
            .contentMargins(.trailing, 0, for: .compactLeading)
            .contentMargins(.leading, 0, for: .compactTrailing)
        }
    }
}
