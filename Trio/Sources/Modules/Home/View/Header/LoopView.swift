import CoreData
import SwiftDate
import SwiftUI
import UIKit

struct LoopView: View {
    @Environment(\.colorScheme) var colorScheme

    fileprivate enum Config {
        static let lag: TimeInterval = 30
        /// How long the sweep stays on after a cycle ends, so a loop that
        /// finishes in a blink still reads as motion.
        static let sweepLinger: TimeInterval = 2
    }

    let dosingMode: DosingMode
    let timerDate: Date
    let isLooping: Bool
    let lastLoopDate: Date
    let manualTempBasal: Bool
    let lastGlucoseDate: Date?
    let lastPumpCommsDate: Date?
    let hasDeviceIssue: Bool

    let determination: [OrefDetermination]

    /// Fraction of the ring removed at *each* of the two horizontal gaps (3 and 9 o'clock),
    /// leaving a top and a bottom arc. Anything short of full automation reads as an open ring;
    /// the centre symbol says why.
    static let openRingGap: CGFloat = 0.12

    static func ringGap(automation: AutomationLevel, manualTempBasal: Bool) -> CGFloat {
        guard !manualTempBasal else { return openRingGap }
        return automation == .full ? 0 : openRingGap
    }

    /// Symbol inside the ring for the modes that still dose, but only under a constraint.
    static func centerSymbol(automation: AutomationLevel) -> String? {
        switch automation {
        case .reductionsOnly:
            return "hand.raised.fill"
        case .hypoSuspendOnly:
            return "waveform"
        case .full,
             .off:
            return nil
        }
    }

    /// Ring colour. Closed-loop freshness is meaningless when nothing is enacted, so open loop
    /// reports device health instead: green while the devices talk to Trio, red when they do not.
    static func ringColor(
        automation: AutomationLevel,
        manualTempBasal: Bool,
        hasDeviceIssue: Bool,
        hasEnactedDetermination: Bool,
        secondsSinceLastLoop: TimeInterval
    ) -> Color {
        guard !manualTempBasal else { return .loopManualTemp }
        guard automation != .off else { return hasDeviceIssue ? .loopRed : .loopGreen }
        // .timestamp only updates when reportEnacted runs
        guard hasEnactedDetermination else { return .secondary }

        let delta = secondsSinceLastLoop - Config.lag
        if delta <= 5.minutes.timeInterval {
            return .loopGreen
        } else if delta <= 10.minutes.timeInterval {
            return .loopYellow
        } else {
            return .loopRed
        }
    }

    private var ringGap: CGFloat {
        Self.ringGap(automation: dosingMode.automation, manualTempBasal: manualTempBasal)
    }

    private var centerSymbol: String? {
        manualTempBasal ? nil : Self.centerSymbol(automation: dosingMode.automation)
    }

    /// Newest sign of life from either device, which is what freshness means when nothing is enacted.
    private var lastDeviceDate: Date? {
        [lastGlucoseDate, lastPumpCommsDate].compactMap { $0 }.max()
    }

    /// Only full automation carries a "last loop" caption. The constrained modes drop it and show
    /// the bare ring; their freshness still comes through in the ring colour.
    static func showsCaption(automation: AutomationLevel) -> Bool { automation == .full }

    private var showsCaption: Bool { Self.showsCaption(automation: dosingMode.automation) }

    @ViewBuilder var body: some View {
        if showsCaption {
            loopStatus
                .padding(.vertical, 5)
                .padding(.horizontal, 10)
                .overlay(
                    Capsule()
                        .stroke(color.opacity(0.4), lineWidth: 2)
                )
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(loopAccessibilityLabel))
        } else {
            // open loop, LGS and basal testing carry no caption; no capsule
            loopStatus
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(loopAccessibilityLabel))
        }
    }

    /// Spoken description of loop state — mirrors the color/text logic so the
    /// color-coded health (green/yellow/red) is conveyed in words, not just hue.
    private var loopAccessibilityLabel: String {
        let status: String
        if manualTempBasal {
            status = String(localized: "manual temporary basal running", comment: "Accessibility: loop status")
        } else if dosingMode.automation == .off {
            // checked before the determination, which never carries a timestamp in open loop
            status = String(localized: "not dosing", comment: "Accessibility: loop status")
        } else if determination.first?.timestamp == nil {
            status = String(localized: "not looping", comment: "Accessibility: loop status")
        } else {
            let delta = timerDate.timeIntervalSince(lastLoopDate) - Config.lag
            if delta <= 5.minutes.timeInterval {
                status = String(localized: "looping normally", comment: "Accessibility: loop status")
            } else if delta <= 10.minutes.timeInterval {
                status = String(localized: "last loop delayed", comment: "Accessibility: loop status")
            } else {
                status = String(localized: "loop overdue", comment: "Accessibility: loop status")
            }
        }

        let age: String
        if isLooping {
            age = String(localized: "in progress", comment: "Accessibility: loop currently running")
        } else if dosingMode.automation == .off {
            // loop age says nothing when nothing is enacted; report device contact instead
            age = lastDeviceDate.map {
                String(
                    format: String(localized: "last device communication %@", comment: "Accessibility: device age"),
                    TimeAgoFormatter.minutesAgoAccessible(from: $0)
                )
            } ?? ""
        } else if determination.first?.deliverAt != nil, timeString != "--" {
            age = String(
                format: String(localized: "last loop %@", comment: "Accessibility: loop age"),
                TimeAgoFormatter.minutesAgoAccessible(from: lastLoopDate)
            )
        } else {
            age = ""
        }

        return [dosingMode.displayName, status, age]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    /// `isLooping` with a short linger, so the sweep outlives the cycle itself.
    @State private var showSweep = false

    @ScaledMetric(relativeTo: .callout) private var compactRingDiameter: CGFloat = 18
    @ScaledMetric(relativeTo: .callout) private var expandedRingDiameter: CGFloat = 26

    private var ringDiameter: CGFloat { showsCaption ? compactRingDiameter : expandedRingDiameter }
    private var ringLineWidth: CGFloat { max(2, ringDiameter * 0.08) }

    private var loopStatus: some View {
        HStack(alignment: .center) {
            ZStack {
                if dosingMode == .closed, !manualTempBasal {
                    Image(systemName: "circle")
                } else {
                    Circle()
                        .trim(from: ringGap / 2, to: 0.5 - ringGap / 2)
                        .stroke(style: StrokeStyle(lineWidth: ringLineWidth, lineCap: .round))
                    Circle()
                        .trim(from: 0.5 + ringGap / 2, to: 1 - ringGap / 2)
                        .stroke(style: StrokeStyle(lineWidth: ringLineWidth, lineCap: .round))
                }
                if showSweep {
                    // A cycle is running: sweep a bright arc around the ring itself
                    // instead of a plain centre spinner, so the motion reads as "the
                    // loop is turning". The base ring (with its mode gaps) stays put.
                    LoopRingSweep(lineWidth: ringLineWidth, color: color)
                } else if let centerSymbol {
                    Image(systemName: centerSymbol)
                        .font(.system(size: ringDiameter * 0.6, weight: .bold))
                }
            }
            .frame(width: ringDiameter, height: ringDiameter)
            // A loop cycle is over in a blink, which is too brief to register as
            // motion. Hold the sweep on for a moment after it finishes so the
            // ring visibly acknowledges that a loop ran.
            .task(id: isLooping) {
                if isLooping {
                    showSweep = true
                } else {
                    try? await Task.sleep(for: .seconds(Config.sweepLinger))
                    if !Task.isCancelled { showSweep = false }
                }
            }
            // A caption would imply an action that did not happen in open loop, LGS, or basal testing.
            // Show timestamp only in closed loop, when determination is enacted.
            if showsCaption {
                if isLooping {
                    Text("looping")
                } else if manualTempBasal {
                    Text("Manual")
                } else if determination.first?.deliverAt != nil {
                    Text(timeString)
                } else {
                    Text("--")
                }
            }
        }
        .font(.callout).fontWeight(.bold).fontDesign(.rounded)
        .foregroundColor(color)
    }

    private var timeString: String {
        let minutesAgo = TimeAgoFormatter.minutesAgoValue(from: lastLoopDate)
        if minutesAgo > 1440 {
            return "--"
        } else {
            return TimeAgoFormatter.minutesAgo(from: lastLoopDate)
        }
    }

    private var color: Color {
        Self.ringColor(
            automation: dosingMode.automation,
            manualTempBasal: manualTempBasal,
            hasDeviceIssue: hasDeviceIssue,
            hasEnactedDetermination: determination.first?.timestamp != nil,
            secondsSinceLastLoop: timerDate.timeIntervalSince(lastLoopDate)
        )
    }
}

/// A short, bright arc that continuously rotates around the loop ring while a loop
/// cycle is in progress. Encapsulating the animation in its own view (with its own
/// state) means it restarts cleanly every time it re-appears, i.e. each time
/// `isLooping` flips back to true.
private struct LoopRingSweep: View {
    let lineWidth: CGFloat
    let color: Color

    @State private var angle: Double = 0

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.16)
            .stroke(
                AngularGradient(
                    gradient: Gradient(colors: [color.opacity(0), color, Color.white.opacity(0.9)]),
                    center: .center
                ),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .rotationEffect(.degrees(angle))
            .onAppear {
                withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                    angle = 360
                }
            }
            .accessibilityHidden(true)
    }
}

extension View {
    func animateForever(
        using animation: Animation = Animation.easeInOut(duration: 1),
        autoreverses: Bool = false,
        _ action: @escaping () -> Void
    ) -> some View {
        let repeated = animation.repeatForever(autoreverses: autoreverses)

        return onAppear {
            withAnimation(repeated) {
                action()
            }
        }
    }
}
