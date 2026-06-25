import Foundation

/// Compact, on-disk archive of daily Total Daily Dose (TDD) values, keyed by local calendar day.
///
/// Two jobs:
/// 1. **Performance** – lets the 1-year insulin stats view avoid re-grouping a year of per-loop
///    `TDDStored` rows on every open. The most recent days are refreshed from Core Data; older days
///    are read straight from this file.
/// 2. **Backfill target** – the optional one-time Nightscout import (see
///    `NightscoutManager.backfillTDDFromNightscout`) writes recovered daily totals here, so history
///    can predate this install or survive a reinstall (which wipes Core Data).
///
/// Persisted as JSON in the app's documents directory via `FileStorage`.
struct TDDArchive: JSON, Equatable {
    /// Daily totals keyed by `"yyyy-MM-dd"` (local start-of-day). Value is insulin units.
    var days: [String: Double]

    init(days: [String: Double] = [:]) {
        self.days = days
    }
}

/// File name + key helpers for the daily-TDD archive. Pure, side-effect free so both the stats
/// module and the Nightscout manager can share the exact same day-keying.
enum TDDArchiveStore {
    /// Documents-relative file name for the archive.
    static let fileName = "trio.monitor.dailyTDD.json"

    /// How many days of history to retain in the archive (a little past the 1-year view for the
    /// rolling-average headroom). Older entries are pruned on save so the file stays bounded.
    static let retentionDays = 400

    /// Stable `"yyyy-MM-dd"` key for a date, using the day boundaries of `calendar`. Built from
    /// numeric components (not a locale-sensitive `DateFormatter`) so keys are deterministic and
    /// line up with how the charts group days via `Calendar.startOfDay`.
    static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
    }

    /// Parses a `"yyyy-MM-dd"` key back into the local start-of-day `Date`, or `nil` if malformed.
    static func date(fromKey key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var comps = DateComponents()
        comps.year = parts[0]
        comps.month = parts[1]
        comps.day = parts[2]
        return calendar.date(from: comps).map { calendar.startOfDay(for: $0) }
    }

    /// Drops entries older than `retentionDays` from a days dictionary.
    static func pruned(_ days: [String: Double], now: Date = Date(), calendar: Calendar = .current) -> [String: Double] {
        guard let cutoff = calendar.date(byAdding: .day, value: -retentionDays, to: calendar.startOfDay(for: now)) else {
            return days
        }
        return days.filter { key, _ in
            guard let date = date(fromKey: key, calendar: calendar) else { return false }
            return date >= cutoff
        }
    }
}
