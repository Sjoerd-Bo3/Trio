import Foundation
import SwiftUI

// MARK: - Zone C: meal panel (IOB / COB / delivery rate)

extension Home.RootView {
    /// Two states: the live IOB / COB / alarms row, and — while the chart is scrubbed — the
    /// readout for the selected point, which wins because it answers the same questions for a
    /// different instant without covering the data the finger is on. It renders from
    /// `chartReadoutDate`, not `chartSelection`, so a hole can't flicker the slot
    /// (see `updateChartReadout`).
    ///
    /// Both halves stay mounted and cross-fade on `opacity`. Swapping them with `if`/`else`
    /// left the exit to a removal transition, which never played: the row's root is a
    /// `ViewThatFits` and its background is a glass/material effect, and neither survives one
    /// — the readout blinked out while the arrival faded in normally. Opacity is a plain
    /// animatable value, so both directions animate.
    @ViewBuilder func mealPanel() -> some View {
        ZStack {
            liveMealPanel
                .opacity(isChartReadoutVisible ? 0 : 1)

            // Renders from the last resolved selection, which is deliberately not cleared on
            // decay: the row has to keep its values to fade out with, and it is invisible
            // (and untouchable) for as long as no readout is showing.
            if let readoutDate = chartReadoutDate,
               let selectedGlucose = ChartSelectionLookup.glucose(at: readoutDate, in: state.glucoseFromPersistence)
            {
                ChartSelectionRow(
                    selectedGlucose: selectedGlucose,
                    determination: chartReadoutDeterminationDate.flatMap {
                        ChartSelectionLookup.determination(at: $0, in: state.enactedAndNonEnactedDeterminations)
                    },
                    units: state.units,
                    highGlucose: state.highGlucose,
                    lowGlucose: state.lowGlucose,
                    currentGlucoseTarget: state.currentGlucoseTarget,
                    glucoseColorScheme: state.glucoseColorScheme,
                    isSmoothingEnabled: state.settingsManager.settings.smoothGlucose
                )
                .padding(.horizontal)
                .opacity(isChartReadoutVisible ? 1 : 0)
                .allowsHitTesting(isChartReadoutVisible)
            }
        }
    }

    /// Decays the readout instead of dropping it: readings and determinations have holes, and
    /// not the same ones, so each half remembers the last selection that resolved it and the
    /// slot only lets go once nothing has resolved for `ChartSelectionLookup.decay`. Run as
    /// `.task(id: chartSelection)`, so the next scrub step cancels a pending decay and
    /// crossing a hole never reaches the timeout.
    ///
    /// Only `isChartReadoutVisible` is cleared when it does let go; the dates it renders from
    /// stay, so the row keeps its values while fading out.
    ///
    /// `@MainActor` because the continuation after the decay sleep would otherwise resume off
    /// the main actor, writing view state from the wrong one.
    @MainActor func updateChartReadout() async {
        if let selection = chartSelection {
            var resolvedAnything = false

            if ChartSelectionLookup.glucose(at: selection, in: state.glucoseFromPersistence) != nil {
                chartReadoutDate = selection
                resolvedAnything = true
            }

            if ChartSelectionLookup.determination(
                at: selection,
                in: state.enactedAndNonEnactedDeterminations
            ) != nil {
                chartReadoutDeterminationDate = selection
                resolvedAnything = true
            } else if let held = chartReadoutDeterminationDate,
                      abs(held.timeIntervalSince(selection)) > ChartSelectionLookup.determinationHold
            {
                // a hop to a different part of the chart, not a hole: don't carry the values over
                chartReadoutDeterminationDate = nil
            }

            if resolvedAnything {
                isChartReadoutVisible = true
                return
            }
        }

        guard isChartReadoutVisible else { return }
        try? await Task.sleep(for: .seconds(ChartSelectionLookup.decay))
        guard !Task.isCancelled else { return }
        isChartReadoutVisible = false
    }

    @ViewBuilder private var liveMealPanel: some View {
        ZStack {
            // the carb value itself sits on the panel's midline; the icon hangs off it
            Text(
                (
                    Formatter.decimalFormatterWithTwoFractionDigits.string(
                        from: NSNumber(value: state.enactedAndNonEnactedDeterminations.first?.cob ?? 0)
                    ) ?? "0"
                ) +
                    String(localized: " g", comment: "gram of carbs")
            )
            .font(.callout).fontWeight(.bold).fontDesign(.rounded)
            .overlay(alignment: .leading) {
                Image(systemName: "fork.knife")
                    .font(.callout)
                    .foregroundColor(.loopYellow)
                    .alignmentGuide(.leading) { $0.width + 5 }
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Carbs on board"))
            .accessibilityValue(Text(
                (Formatter.decimalFormatterWithTwoFractionDigits.string(
                    from: NSNumber(value: state.enactedAndNonEnactedDeterminations.first?.cob ?? 0)
                ) ?? "0") + String(localized: " g", comment: "gram of carbs")
            ))

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
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Insulin on board"))
                .accessibilityValue(Text(
                    (
                        Formatter.decimalFormatterWithTwoFractionDigits
                            .string(from: state.currentIOB as NSNumber) ?? "0"
                    )
                        + String(localized: " U", comment: "Insulin unit")
                ))

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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Alarms"))
        .accessibilityValue(Text(
            isSnoozed
                ? String(
                    format: String(localized: "snoozed, %d minutes remaining", comment: "Accessibility: alarm snooze"),
                    remainingMinutes
                )
                : String(localized: "active", comment: "Accessibility: alarms active")
        ))
        .accessibilityHint(Text(String(localized: "Opens snooze options", comment: "Accessibility hint")))
        .accessibilityAddTraits(.isButton)
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
