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

    /// Computes a centered, time-windowed rolling average over a series of dated values.
    ///
    /// Unlike a naive index-based moving average, the window is defined in **calendar time**
    /// (± half the window's worth of `unit` seconds around each point), so gaps in the data
    /// (e.g. days with no bolus or no logged meal) do not distort the result. A centered
    /// window keeps the trend line aligned with the bars it overlays, and each point's date
    /// is offset by half a bar width so the line sits over the bar centers.
    ///
    /// - Parameters:
    ///   - items: The source data. Need not be pre-sorted.
    ///   - date: Closure returning the date (bin start) for an item.
    ///   - value: Closure returning the value to be averaged for an item.
    ///   - window: The window size in number of bars. A window < 2 disables smoothing.
    ///   - unit: Seconds per bar (e.g. 3600 for hourly, 86400 for daily). Defines the window width.
    ///   - useMedian: When `true`, uses the median of the window (robust to outliers) instead of the mean.
    ///   - zeroFillEmptySlots: When `true`, calendar slots inside the window that have no data are
    ///     counted as `0` (a true per-day average); when `false`, only days with data are averaged.
    ///   - carryOverValue: Optional carry-over level (a summary of history just before the oldest
    ///     retained data) used only to pad the average at the oldest edge so it is not one-sided.
    ///     Synthesized into lead-in points before the first real point; never drawn as bars.
    ///   - centerOffset: Seconds added to each date so points align with bar centers.
    /// - Returns: An array of `RollingAveragePoint` aligned to the input dates.
    static func rollingAverage<T>(
        for items: [T],
        date: (T) -> Date,
        value: (T) -> Double,
        window: Int,
        unit: TimeInterval,
        useMedian: Bool,
        zeroFillEmptySlots: Bool,
        carryOverValue: Double? = nil,
        centerOffset: TimeInterval
    ) -> [RollingAveragePoint] {
        guard !items.isEmpty else { return [] }

        let points = items.map { (date: date($0), value: value($0)) }.sorted { $0.date < $1.date }
        guard points.count > 1 else {
            return points.map { RollingAveragePoint(date: $0.date.addingTimeInterval(centerOffset), value: $0.value) }
        }

        let halfWindow = max(0, window / 2)
        let halfWidth = Double(halfWindow) * unit
        let epsilon = unit / 2 // tolerance so slot boundaries are included

        // Synthesize lead-in points from the carry-over level so the oldest real points have a
        // full (rather than one-sided) window. These pad the leading edge only and are never drawn.
        var leadIn: [(date: Date, value: Double)] = []
        if let carryOverValue, halfWindow > 0, let oldest = points.first?.date {
            for step in 1 ... halfWindow {
                leadIn.append((date: oldest.addingTimeInterval(-Double(step) * unit), value: carryOverValue))
            }
        }

        // Neighbor candidates: synthetic lead-in points sort before the real data.
        let neighbors = (leadIn + points).sorted { $0.date < $1.date }
        // Bound zero-fill to the real data span (extended backwards by any lead-in) so we never
        // invent slots in the future or before recorded history.
        let fillStart = neighbors.first!.date
        let fillEnd = points.last!.date

        return points.map { point in
            let lower = point.date.addingTimeInterval(-halfWidth)
            let upper = point.date.addingTimeInterval(halfWidth)
            var values = neighbors
                .filter { $0.date >= lower - epsilon && $0.date <= upper + epsilon }
                .map { $0.value }

            if zeroFillEmptySlots {
                let effectiveLower = max(lower, fillStart)
                let effectiveUpper = min(upper, fillEnd)
                let span = effectiveUpper.timeIntervalSince(effectiveLower)
                let expectedSlots = span > 0 ? Int((span / unit).rounded()) + 1 : 1
                let missing = max(0, expectedSlots - values.count)
                if missing > 0 { values.append(contentsOf: repeatElement(0.0, count: missing)) }
            }

            let average: Double
            if values.isEmpty {
                average = point.value
            } else if useMedian {
                average = medianCalculationDouble(array: values)
            } else {
                average = values.reduce(0, +) / Double(values.count)
            }
            return RollingAveragePoint(date: point.date.addingTimeInterval(centerOffset), value: average)
        }
    }

    /// Returns the number of seconds represented by one bar for the given interval.
    ///
    /// Used as the time-window unit for `rollingAverage(...)`: hourly bars in the day view,
    /// daily bars otherwise.
    static func unitSeconds(for selectedInterval: Stat.StateModel.StatsTimeInterval) -> TimeInterval {
        selectedInterval == .day ? 3600 : 86400
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

    /// `UserDefaults`/`@AppStorage` key for the debug rolling-average window override.
    ///
    /// A value of `0` means "use the automatic per-interval default"; any positive value
    /// forces that fixed window across all intervals. Exposed via a debug slider on the
    /// Statistics screen so the smoothing can be tuned on TestFlight builds.
    static let rollingAverageWindowOverrideKey = "debugStatsRollingAverageWindow"

    /// `@AppStorage` key: when `true`, the trend line uses a rolling **median** (robust to outliers)
    /// instead of the mean.
    static let rollingAverageUseMedianKey = "debugStatsRollingAverageUseMedian"

    /// `@AppStorage` key: when `true`, calendar days inside the window with no data count as `0`
    /// (a true per-day average) instead of being skipped.
    static let rollingAverageZeroFillKey = "debugStatsRollingAverageZeroFill"

    /// `@AppStorage` key: when `true`, a carry-over summary of purged history seeds the oldest edge
    /// of the trend line.
    static let rollingAverageLeadInKey = "debugStatsRollingAverageLeadIn"

    /// Returns the effective rolling-average window, honoring a debug override when set.
    ///
    /// - Parameters:
    ///   - selectedInterval: The selected time interval, used for the automatic default.
    ///   - override: The debug override value. `0` (or negative) uses the automatic default;
    ///     any positive value is used directly (1 disables smoothing by averaging a single bar).
    /// - Returns: The window size to pass to `rollingAverage(...)`.
    static func rollingAverageWindow(
        for selectedInterval: Stat.StateModel.StatsTimeInterval,
        override: Int
    ) -> Int {
        override > 0 ? override : rollingAverageWindow(for: selectedInterval)
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
