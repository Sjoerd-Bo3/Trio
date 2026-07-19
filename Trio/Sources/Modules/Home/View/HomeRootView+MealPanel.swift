import Foundation
import SwiftUI

// MARK: - Zone C: meal panel (IOB / COB / delivery rate)

extension Home.RootView {
    @ViewBuilder func mealPanel() -> some View {
        HStack {
            HStack {
                Image(systemName: "syringe.fill")
                    .font(.callout)
                    .foregroundColor(Color.insulin)
                Text(
                    (
                        Formatter.decimalFormatterWithTwoFractionDigits
                            .string(from: state.currentIOB as NSNumber) ?? "0"
                    ) +
                        String(localized: " U", comment: "Insulin unit")
                )
                .font(.callout).fontWeight(.bold).fontDesign(.rounded)
            }

            Spacer()

            HStack {
                Image(systemName: "fork.knife")
                    .font(.callout)
                    .foregroundColor(.loopYellow)
                Text(
                    (
                        Formatter.decimalFormatterWithTwoFractionDigits.string(
                            from: NSNumber(value: state.enactedAndNonEnactedDeterminations.first?.cob ?? 0)
                        ) ?? "0"
                    ) +
                        String(localized: " g", comment: "gram of carbs")
                )
                .font(.callout).fontWeight(.bold).fontDesign(.rounded)
            }

            Spacer()

            alarmsPill
        }.padding(.horizontal)
    }

    func refreshAlarmsSnooze() {
        alarmsSnoozeUntil = UserDefaults.standard
            .object(forKey: "UserNotificationsManager.snoozeUntilDate") as? Date ?? .distantPast
        alarmsSnoozeFrom = UserDefaults.standard
            .object(forKey: "UserNotificationsManager.snoozeFromDate") as? Date ?? .distantPast
    }

    /// Bell pill matching the header pills; countdown replaces the label while snoozed, and the
    /// border reflects the alarm state (reversed countdown while snoozed, spinning while alarming).
    @ViewBuilder var alarmsPill: some View {
        // timerDate keeps the countdown ticking
        let isSnoozed = alarmsSnoozeUntil > state.timerDate
        let remainingMinutes = max(Int(ceil(alarmsSnoozeUntil.timeIntervalSince(state.timerDate) / 60)), 0)
        let hasActiveAlarm = state.alarm != nil
        // Fraction of the snooze window still left (1 → 0), if we know when it started.
        let snoozeFraction: Double? = {
            guard isSnoozed, alarmsSnoozeFrom > .distantPast else { return nil }
            let total = alarmsSnoozeUntil.timeIntervalSince(alarmsSnoozeFrom)
            guard total > 0 else { return nil }
            return min(max(alarmsSnoozeUntil.timeIntervalSince(state.timerDate) / total, 0), 1)
        }()

        Button {
            showSnoozeSheet = true
        } label: {
            alarmsPillBorder(
                HStack(spacing: 5) {
                    Image(systemName: isSnoozed ? "bell.slash.fill" : "bell.fill")
                        .font(.callout)
                    Text(isSnoozed ? "\(remainingMinutes) m" : String(localized: "Alarms", comment: "Alarms header item"))
                        .font(.callout).fontWeight(.bold).fontDesign(.rounded)
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 10)
                .foregroundStyle(isSnoozed ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary)),
                isSnoozed: isSnoozed,
                hasActiveAlarm: hasActiveAlarm,
                snoozeFraction: snoozeFraction
            )
        }
        .buttonStyle(.plain)
    }

    /// Reversed countdown border while snoozed (empties as the snooze runs out), a spinning red
    /// ring during an active alarm, otherwise the neutral outline.
    @ViewBuilder func alarmsPillBorder(
        _ content: some View,
        isSnoozed: Bool,
        hasActiveAlarm: Bool,
        snoozeFraction: Double?
    ) -> some View {
        if isSnoozed {
            content.progressCapsuleBorder(progress: snoozeFraction ?? 1, color: .orange, lineWidth: 2)
        } else if hasActiveAlarm {
            content.spinningCapsuleBorder(isActive: true, color: .red, lineWidth: 2)
        } else {
            content.overlay(Capsule().stroke(Color.primary.opacity(0.4), lineWidth: 2))
        }
    }
}
