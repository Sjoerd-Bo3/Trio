import Charts
import Foundation
import SwiftUI

struct StatChartUtils {
    /// Returns the time interval length for the visible domain based on the selected duration.
    /// - Parameter selectedInterval: The selected time interval for statistics.
    /// - Returns: The time interval in seconds.
    static func visibleDomainLength(for selectedInterval: Stat.StateModel.StatsTimeInterval) -> TimeInterval {
        switch selectedInterval {
        case .day: return 24 * 3600
        case .week: return 7 * 24 * 3600
        case .month: return 30 * 24 * 3600
        case .total: return 90 * 24 * 3600
        }
    }

    /// Computes the visible date range based on the scroll position and selected duration.
    /// - Parameters:
    ///   - scrollPosition: The current scroll position in the chart.
    ///   - selectedInterval: The selected time interval for statistics.
    /// - Returns: A tuple containing the start and end dates of the visible range.
    static func visibleDateRange(
        from scrollPosition: Date,
        for selectedInterval: Stat.StateModel.StatsTimeInterval
    ) -> (start: Date, end: Date) {
        let calendar = Calendar.current

        if selectedInterval == .day {
            // For day view, don't modify the scroll position
            let end = scrollPosition.addingTimeInterval(visibleDomainLength(for: selectedInterval) - 1)
            return (scrollPosition, end)
        } else {
            // For week and longer intervals, we need smart alignment
            // Find the nearest day boundary
            let startOfDay = calendar.startOfDay(for: scrollPosition)
            let components = calendar.dateComponents([.hour, .minute, .second], from: scrollPosition)
            let totalSeconds = Double(components.hour ?? 0) * 3600 + Double(components.minute ?? 0) * 60 +
                Double(components.second ?? 0)

            // Align start end to midnight
            let alignedStart = totalSeconds > 12 * 3600 ?
                calendar.date(byAdding: .day, value: 1, to: startOfDay)! : startOfDay
            let intervalLength = visibleDomainLength(for: selectedInterval)
            let end = alignedStart.addingTimeInterval(intervalLength + (2 * 3600))
            let alignedEnd = calendar.startOfDay(for: end).addingTimeInterval(-1)

            return (alignedStart, alignedEnd)
        }
    }

    /// Returns the appropriate date format style based on the selected time interval.
    /// - Parameter selectedInterval: The selected time interval for statistics.
    /// - Returns: A Date.FormatStyle configured for the current time interval.
    static func dateFormat(for selectedInterval: Stat.StateModel.StatsTimeInterval) -> Date.FormatStyle {
        switch selectedInterval {
        case .day: return .dateTime.hour()
        case .week: return .dateTime.weekday(.abbreviated)
        case .month: return .dateTime.day()
        case .total: return .dateTime.month(.abbreviated)
        }
    }

    /// Returns DateComponents for aligning dates based on the selected duration.
    /// - Parameter selectedInterval: The selected time interval for statistics.
    /// - Returns: DateComponents configured for the appropriate alignment.
    static func alignmentComponents(for selectedInterval: Stat.StateModel.StatsTimeInterval) -> DateComponents {
        switch selectedInterval {
        case .day: return DateComponents(hour: 0)
        case .week:
            let calendar = Calendar.current
            return DateComponents(weekday: calendar.firstWeekday)
        case .month,
             .total: return DateComponents(day: 1)
        }
    }

    /// Returns the initial scroll position date based on the selected duration.
    /// - Parameter selectedInterval: The selected time interval for statistics.
    /// - Returns: A Date representing the initial scroll position.
    static func getInitialScrollPosition(for selectedInterval: Stat.StateModel.StatsTimeInterval) -> Date {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)

        let baseDate: Date
        switch selectedInterval {
        case .day:
            baseDate = today
        case .week:
            baseDate = calendar.date(byAdding: .day, value: -6, to: today)!
        case .month:
            baseDate = calendar.date(byAdding: .day, value: -29, to: today)!
        case .total:
            baseDate = calendar.date(byAdding: .day, value: -89, to: today)!
        }

        return calendar.date(byAdding: .second, value: 1, to: baseDate)!
    }

    /// Checks if two dates belong to the same time unit based on the selected duration.
    /// - Parameters:
    ///   - date1: The first date.
    ///   - date2: The second date.
    ///   - selectedInterval: The selected time interval for statistics.
    /// - Returns: A Boolean indicating whether the two dates are in the same time unit.
    static func isSameTimeUnit(
        _ date1: Date,
        _ date2: Date,
        for selectedInterval: Stat.StateModel.StatsTimeInterval
    ) -> Bool {
        let calendar = Calendar.current
        switch selectedInterval {
        case .day:
            return calendar.isDate(date1, equalTo: date2, toGranularity: .hour)
        default:
            return calendar.isDate(date1, inSameDayAs: date2)
        }
    }

    /// Formats the visible date range into a human-readable string.
    /// - Parameters:
    ///   - start: The start date of the range.
    ///   - end: The end date of the range.
    ///   - selectedInterval: The selected time interval for statistics.
    /// - Returns: A formatted string representing the visible date range.
    static func formatVisibleDateRange(
        from start: Date,
        to end: Date,
        for selectedInterval: Stat.StateModel.StatsTimeInterval
    ) -> String {
        let calendar = Calendar.current

        // If not .day, we just return "startText - endText", e.g. "Jan 1 - Jan 8"
        guard selectedInterval == .day else {
            let formatDate: (Date) -> String = { date in
                date.formatted(.dateTime.day().month())
            }
            let startText = formatDate(start)
            let endText = formatDate(end)
            return "\(startText) - \(endText)"
        }

        // For .day mode, we figure out if we are near the boundaries for a "full day" (00:00 - 23:59)
        let dayStart = calendar.startOfDay(for: start)
        let nextDayStart = calendar.date(byAdding: .day, value: 1, to: dayStart)!

        // Allow +/- 15 minutes from midnight as buffer, so slow scrolling doesn't break the "full day"
        let tolerance: TimeInterval = 60 * 15

        let isStartNearMidnight = abs(start.timeIntervalSince(dayStart)) < tolerance
        let isEndNearNextMidnight = abs(end.timeIntervalSince(nextDayStart)) < tolerance

        let formatDay: (Date) -> String = { date in
            date.formatted(.dateTime.day().month(.abbreviated))
        }

        if isStartNearMidnight, isEndNearNextMidnight {
            // Full day: show just start as "Mon, Jan 1"
            return dayStart.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        } else {
            // Partial day: show start and end
            let startText = formatDay(start)
            let endText = formatDay(end)
            return "\(startText) - \(endText)"
        }
    }

    /// A helper function to create a `VStack` for each statistic.
    ///
    /// - Parameters:
    ///   - title: The title of the statistic.
    ///   - value: The formatted value to display.
    /// - Returns: A `VStack` with the title and value.
    static func statView(title: String, value: String) -> some View {
        VStack(spacing: 5) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Color.secondary)
            Text(value)
        }
    }

    /// Computes the median value of an array of integers.
    ///
    /// - Parameter array: An array of integers.
    /// - Returns: The median value as a `Double`. Returns `0` if the array is empty.
    static func medianCalculation(array: [Int]) -> Double {
        guard !array.isEmpty else { return 0 }
        let sorted = array.sorted()
        let length = array.count

        if length % 2 == 0 {
            return Double((sorted[length / 2 - 1] + sorted[length / 2]) / 2)
        }
        return Double(sorted[length / 2])
    }

    /// Computes the median value of an array of doubles.
    ///
    /// - Parameter array: An array of `Double` values.
    /// - Returns: The median value. Returns `0` if the array is empty.
    static func medianCalculationDouble(array: [Double]) -> Double {
        guard !array.isEmpty else { return 0 }
        let sorted = array.sorted()
        let length = array.count

        if length % 2 == 0 {
            return (sorted[length / 2 - 1] + sorted[length / 2]) / 2
        }
        return sorted[length / 2]
    }

    /// Creates a legend item view for use in a chart legend.
    ///
    /// - Parameters:
    ///   - label: The text label for the legend item.
    ///   - color: The color associated with the legend item.
    /// - Returns: A SwiftUI view displaying a colored symbol and a label.
    @ViewBuilder static func legendItem(label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "circle.fill").foregroundStyle(color)
            Text(label).foregroundStyle(Color.secondary)
        }.font(.caption)
    }

    // MARK: - Rolling Average Trend Line

    /// The stroke style used for overlaid rolling-average trend lines.
    static let rollingAverageStrokeStyle = StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 4])

    /// A single point on a rolling-average trend line.
    struct RollingAveragePoint: Identifiable {
        let id = UUID()
        /// The date of the point, offset to align with the center of its corresponding bar.
        let date: Date
        /// The averaged value at this point.
        let value: Double
    }

    /// Computes a centered rolling (moving) average over a series of dated values.
    ///
    /// A centered window is used so the trend line is not shifted relative to the bars it
    /// overlays. Points near the edges use a partial (clamped) window so the line spans the
    /// full data range. Each point's date is offset by half a bar width so the line aligns
    /// with the center of the bars rather than their leading edge.
    ///
    /// - Parameters:
    ///   - items: The source data, assumed sorted ascending by date.
    ///   - date: Closure returning the date (bin start) for an item.
    ///   - value: Closure returning the value to be averaged for an item.
    ///   - window: The number of points to include in the averaging window. A window < 2
    ///     disables smoothing and plots the raw values.
    ///   - centerOffset: Seconds added to each date so points align with bar centers.
    /// - Returns: An array of `RollingAveragePoint` aligned to the input dates.
    static func rollingAverage<T>(
        for items: [T],
        date: (T) -> Date,
        value: (T) -> Double,
        window: Int,
        centerOffset: TimeInterval
    ) -> [RollingAveragePoint] {
        guard items.count > 1 else { return [] }

        let values = items.map(value)
        let dates = items.map(date)
        let halfWindow = max(0, window / 2)

        return items.indices.map { index in
            let lower = max(0, index - halfWindow)
            let upper = min(items.count - 1, index + halfWindow)
            let sum = values[lower ... upper].reduce(0, +)
            let average = sum / Double(upper - lower + 1)
            return RollingAveragePoint(date: dates[index].addingTimeInterval(centerOffset), value: average)
        }
    }

    /// Returns the rolling-average window size (in number of bars) for the given interval.
    ///
    /// Windows are chosen to smooth out hour-to-hour or day-to-day noise while still
    /// following the longer trend across the visible range.
    static func rollingAverageWindow(for selectedInterval: Stat.StateModel.StatsTimeInterval) -> Int {
        switch selectedInterval {
        case .day: return 3 // 3 hours
        case .week: return 3 // 3 days
        case .month: return 7 // 7 days
        case .total: return 7 // 7 days
        }
    }

    /// Returns the offset, in seconds, from a bar's bin start to its center for the given interval.
    ///
    /// Bars are binned to the start of an hour (day view) or the start of a day (all other
    /// views); this offset re-centers an overlaid trend line on top of the bars.
    static func barCenterOffset(for selectedInterval: Stat.StateModel.StatsTimeInterval) -> TimeInterval {
        selectedInterval == .day ? 1800 : 43200 // half hour : half day
    }

    /// Creates a legend item that renders a short dashed line, matching overlaid trend lines.
    ///
    /// - Parameters:
    ///   - label: The text label for the legend item.
    ///   - color: The color of the dashed line symbol.
    /// - Returns: A SwiftUI view displaying a dashed line symbol and a label.
    @ViewBuilder static func dashedLegendItem(label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            HorizontalLine()
                .stroke(color, style: StrokeStyle(lineWidth: 2, dash: [3, 2]))
                .frame(width: 18, height: 4)
            Text(label).foregroundStyle(Color.secondary)
        }.font(.caption)
    }
}

/// A simple horizontal line shape used to render dashed legend symbols.
private struct HorizontalLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
