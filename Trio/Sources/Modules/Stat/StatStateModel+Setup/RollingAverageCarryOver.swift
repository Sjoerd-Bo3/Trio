import Foundation

/// Carry-over support for the Statistics rolling-average trend line.
///
/// Trio purges raw statistics data after 90 days, so the daily charts have no history before the
/// oldest retained day and the centered moving average would be one-sided at that edge. To avoid a
/// "cold start", we persist a small carry-over value per metric — the typical daily level of the
/// oldest retained days — and refresh it whenever the stats are (re)computed. Because the value is
/// persisted, it keeps reflecting days that may since have been purged, and it is used only to pad
/// the leading edge of the trend line (never drawn as a bar).
extension Stat.StateModel {
    /// Number of oldest retained days summarized into the carry-over value.
    private var carryOverSampleDays: Int { 7 }

    private enum CarryOverKey {
        static let tdd = "statCarryOverTDD"
        static let bolus = "statCarryOverBolusTotal"
        static let mealCarbs = "statCarryOverMealCarbs"
        static let mealFat = "statCarryOverMealFat"
        static let mealProtein = "statCarryOverMealProtein"
    }

    private func persistedCarryOver(_ key: String) -> Double? {
        UserDefaults.standard.object(forKey: key) as? Double
    }

    private func setPersistedCarryOver(_ key: String, _ value: Double?) {
        guard let value else { return }
        UserDefaults.standard.set(value, forKey: key)
    }

    private func carryOverMean(of values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    // MARK: - Refresh (called after the daily stats are (re)computed)

    /// Updates the persisted TDD carry-over from the oldest retained daily doses.
    func updateTDDCarryOver() {
        let oldest = dailyTDDStats.sorted { $0.date < $1.date }.prefix(carryOverSampleDays)
        setPersistedCarryOver(CarryOverKey.tdd, carryOverMean(of: oldest.map(\.amount)))
    }

    /// Updates the persisted bolus carry-over (total bolus) from the oldest retained days.
    func updateBolusCarryOver() {
        let oldest = dailyBolusStats.sorted { $0.date < $1.date }.prefix(carryOverSampleDays)
        setPersistedCarryOver(CarryOverKey.bolus, carryOverMean(of: oldest.map { $0.manualBolus + $0.smb + $0.external }))
    }

    /// Updates the persisted meal carry-over (per macro) from the oldest retained days.
    func updateMealCarryOver() {
        let oldest = dailyMealStats.sorted { $0.date < $1.date }.prefix(carryOverSampleDays)
        setPersistedCarryOver(CarryOverKey.mealCarbs, carryOverMean(of: oldest.map(\.carbs)))
        setPersistedCarryOver(CarryOverKey.mealFat, carryOverMean(of: oldest.map(\.fat)))
        setPersistedCarryOver(CarryOverKey.mealProtein, carryOverMean(of: oldest.map(\.protein)))
    }

    // MARK: - Lead-in values (consumed by the chart views)

    /// The TDD carry-over level for the leading edge, or `nil` for the day view (where it doesn't apply).
    func tddCarryOverValue(for interval: StatsTimeInterval) -> Double? {
        interval == .day ? nil : persistedCarryOver(CarryOverKey.tdd)
    }

    /// The total-bolus carry-over level for the leading edge, or `nil` for the day view.
    func bolusCarryOverValue(for interval: StatsTimeInterval) -> Double? {
        interval == .day ? nil : persistedCarryOver(CarryOverKey.bolus)
    }

    /// The meal carry-over level (matching the displayed total) for the leading edge, or `nil` for the day view.
    func mealCarryOverValue(for interval: StatsTimeInterval) -> Double? {
        guard interval != .day, let carbs = persistedCarryOver(CarryOverKey.mealCarbs) else { return nil }
        guard useFPUconversion else { return carbs }
        let fat = persistedCarryOver(CarryOverKey.mealFat) ?? 0
        let protein = persistedCarryOver(CarryOverKey.mealProtein) ?? 0
        return carbs + fat + protein
    }
}
