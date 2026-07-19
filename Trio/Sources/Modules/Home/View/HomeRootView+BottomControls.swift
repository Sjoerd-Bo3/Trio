import CoreData
import SwiftDate
import SwiftUI

// MARK: - Zone E: bottom controls (adjustment panel / bolus progress)

extension Home.RootView {
    var bolusProgressFormatter: NumberFormatter {
        let fractionDigits: Int = switch state.settingsManager.preferences.bolusIncrement {
        case 0.1: 1
        case 0.025: 3
        default: 2
        }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimum = 0
        formatter.maximumFractionDigits = fractionDigits
        formatter.minimumFractionDigits = fractionDigits
        formatter.allowsFloats = true
        formatter.roundingIncrement = Double(state.settingsManager.preferences.bolusIncrement) as NSNumber
        return formatter
    }

    private var fetchedTargetFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        if state.units == .mmolL {
            formatter.maximumFractionDigits = 1
        } else { formatter.maximumFractionDigits = 0 }
        return formatter
    }

    func remainingFraction(start: Date?, durationMinutes: Decimal?, indefinite: Bool) -> Double? {
        guard !indefinite, let start = start, let durationMinutes = durationMinutes, durationMinutes > 0 else {
            return nil
        }
        let total = Double(truncating: durationMinutes as NSNumber) * 60
        let elapsed = Date().timeIntervalSince(start)
        guard total > 0 else { return nil }
        return min(max(1 - elapsed / total, 0), 1)
    }

    var overrideRemainingFraction: Double? {
        guard let o = latestOverride.first else { return nil }
        return remainingFraction(start: o.date, durationMinutes: o.duration as Decimal?, indefinite: o.indefinite)
    }

    var tempTargetRemainingFraction: Double? {
        guard let t = latestTempTarget.first else { return nil }
        return remainingFraction(start: t.date, durationMinutes: t.duration as Decimal?, indefinite: false)
    }

    @ViewBuilder func adjustmentIcon(_ systemName: String, tint: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 30, height: 30)
            .background(Circle().fill(tint.opacity(0.18)))
    }


    var overrideString: String? {
        guard let latestOverride = latestOverride.first else {
            return nil
        }

        guard let settingsManager = state.settingsManager else {
            return nil
        }

        let percent = latestOverride.percentage
        let percentString = percent == 100 ? "" : "\(percent.formatted(.number)) %"

        let unit = state.units
        var target = (latestOverride.target ?? 0) as Decimal
        target = unit == .mmolL ? target.asMmolL : target

        var targetString = target == 0 ? "" : (fetchedTargetFormatter.string(from: target as NSNumber) ?? "") + " " + unit
            .rawValue
        if tempTargetString != nil {
            targetString = ""
        }

        let duration = latestOverride.duration ?? 0
        let addedMinutes = Int(truncating: duration)
        let date = latestOverride.date ?? Date()
        let newDuration = max(
            Decimal(Date().distance(to: date.addingTimeInterval(addedMinutes.minutes.timeInterval)).minutes),
            0
        )
        let indefinite = latestOverride.indefinite
        var durationString = ""

        if !indefinite {
            if newDuration >= 1 {
                durationString = formatHrMin(Int(newDuration))
            } else if newDuration > 0 {
                durationString = "\(Int(newDuration * 60)) s"

            } else {
                /// Do not show the Override anymore
                Task {
                    guard let objectID = self.latestOverride.first?.objectID else { return }
                    await state.cancelOverride(withID: objectID)
                }
            }
        }

        let smbScheduleString = latestOverride
            .smbIsScheduledOff && ((latestOverride.start?.stringValue ?? "") != (latestOverride.end?.stringValue ?? ""))
            ? " \(formatTimeRange(start: latestOverride.start?.stringValue, end: latestOverride.end?.stringValue))"
            : ""

        let smbToggleString = latestOverride.smbIsOff || latestOverride
            .smbIsScheduledOff ? String(localized: "SMBs Off\(smbScheduleString)") : ""

        var smbMinuteString: String = ""
        var uamMinuteString: String = ""

        if !latestOverride.smbIsOff, latestOverride.advancedSettings {
            if let smbMinutes = latestOverride.smbMinutes,
               smbMinutes.decimalValue != settingsManager.preferences.maxSMBBasalMinutes
            {
                smbMinuteString = "SMB\u{00A0}\(smbMinutes)\u{00A0}" +
                    String(localized: "m", comment: "Abbreviation for Minutes")
            }

            if let uamMinutes = latestOverride.uamMinutes,
               uamMinutes.decimalValue != settingsManager.preferences.maxUAMSMBBasalMinutes
            {
                uamMinuteString = "UAM\u{00A0}\(uamMinutes)\u{00A0}" +
                    String(localized: "m", comment: "Abbreviation for Minutes")
            }
        }

        let components = [durationString, percentString, targetString, smbToggleString, smbMinuteString, uamMinuteString]
            .filter { !$0.isEmpty }
        return components.isEmpty ? nil : components.joined(separator: ", ")
    }

    var tempTargetString: String? {
        guard let latestTempTarget = latestTempTarget.first else {
            return nil
        }
        let duration = latestTempTarget.duration
        let addedMinutes = Int(truncating: duration ?? 0)
        let date = latestTempTarget.date ?? Date()
        let newDuration = max(
            Decimal(Date().distance(to: date.addingTimeInterval(addedMinutes.minutes.timeInterval)).minutes),
            0
        )
        var durationString = ""
        var percentageString = ""
        var target = (latestTempTarget.target ?? 100) as Decimal
        // Use TempTargetCalculations to get effective HBT (handles both custom and auto-adjusted standard TT)
        let effectiveHBT = TempTargetCalculations.computeEffectiveHBT(
            tempTargetHalfBasalTarget: latestTempTarget.halfBasalTarget?.decimalValue,
            settingHalfBasalTarget: state.settingHalfBasalTarget,
            target: target,
            autosensMax: state.autosensMax
        ) ?? state.settingHalfBasalTarget
        var showPercentage = false
        if target > 100, state.isExerciseModeActive || state.highTTraisesSens { showPercentage = true }
        if target < 100, state.lowTTlowersSens, state.autosensMax > 1 { showPercentage = true }
        if showPercentage {
            percentageString =
                " \(Int(TempTargetCalculations.computeAdjustedPercentage(halfBasalTarget: effectiveHBT, target: target, autosensMax: state.autosensMax)))%"
        }
        target = state.units == .mmolL ? target.asMmolL : target
        let targetString = target == 0 ? "" : (fetchedTargetFormatter.string(from: target as NSNumber) ?? "") + " " +
            state.units.rawValue + percentageString

        if newDuration >= 1 {
            durationString =
                "\(newDuration.formatted(.number.grouping(.never).rounded().precision(.fractionLength(0)))) min"
        } else if newDuration > 0 {
            durationString =
                "\((newDuration * 60).formatted(.number.grouping(.never).rounded().precision(.fractionLength(0)))) s"
        } else {
            /// Do not show the Temp Target anymore
            Task {
                guard let objectID = self.latestTempTarget.first?.objectID else { return }
                await state.cancelTempTarget(withID: objectID)
            }
        }

        let components = [targetString, durationString].filter { !$0.isEmpty }
        return components.isEmpty ? nil : components.joined(separator: ", ")
    }

    @ViewBuilder func adjustmentsOverrideView(_ overrideString: String) -> some View {
        Group {
            adjustmentIcon("clock.arrow.2.circlepath", tint: Color.purple)
            VStack(alignment: .leading, spacing: 1) {
                Text(latestOverride.first?.name ?? String(localized: "Custom Override"))
                    .font(.subheadline).fontWeight(.semibold)
                    .frame(alignment: .leading)

                Text(overrideString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder func adjustmentsTempTargetView(_ tempTargetString: String) -> some View {
        Group {
            adjustmentIcon("target", tint: Color.loopGreen)
            VStack(alignment: .leading, spacing: 1) {
                Text(latestTempTarget.first?.name ?? String(localized: "Temp Target"))
                    .font(.subheadline).fontWeight(.semibold)
                Text(tempTargetString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }


    @ViewBuilder func adjustmentsCancelTempTargetView() -> some View {
        Image(systemName: "xmark.app")
            .font(.title)
            .confirmationDialog(
                "Stop the Temp Target \"\(latestTempTarget.first?.name ?? "")\"?",
                isPresented: $isConfirmStopTempTargetShown,
                titleVisibility: .visible
            ) {
                Button("Stop", role: .destructive) {
                    Task {
                        guard let objectID = latestTempTarget.first?.objectID else { return }
                        await state.cancelTempTarget(withID: objectID)
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .padding(.trailing, 8)
            .onTapGesture {
                if !latestTempTarget.isEmpty {
                    isConfirmStopTempTargetShown = true
                }
            }
    }

    @ViewBuilder func adjustmentsCancelOverrideView() -> some View {
        Image(systemName: "xmark.app")
            .font(.title)
            .confirmationDialog(
                "Stop the Override \"\(latestOverride.first?.name ?? "")\"?",
                isPresented: $isConfirmStopOverridePresented,
                titleVisibility: .visible
            ) {
                Button("Stop", role: .destructive) {
                    Task {
                        guard let objectID = latestOverride.first?.objectID else { return }
                        await state.cancelOverride(withID: objectID)
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .padding(.trailing, 8)
            .onTapGesture {
                if !latestOverride.isEmpty {
                    isConfirmStopOverridePresented = true
                }
            }
    }

    @ViewBuilder func noActiveAdjustmentsView() -> some View {
        adjustmentIcon("slider.horizontal.2.gobackward", tint: Color.secondary)

        VStack(alignment: .leading, spacing: 1) {
            Text("No Active Adjustment")
                .font(.subheadline).fontWeight(.medium)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Profile at 100 %")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        Spacer(minLength: 0)
    }

    /// Icon + name for the active profile preset (orange + warning icon when modified).
    @ViewBuilder func activeProfileContent(_ preset: ProfilePreset) -> some View {
        adjustmentIcon(
            state.isProfileDiverged ? "exclamationmark.triangle.fill" : preset.icon,
            tint: state.isProfileDiverged ? .orange : .accentColor
        )
        VStack(alignment: .leading, spacing: 1) {
            Text(preset.name)
                .font(.subheadline).fontWeight(.semibold)
                .foregroundStyle(state.isProfileDiverged ? Color.orange : Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(state.isProfileDiverged
                ? String(localized: "Profile · modified", comment: "Adjustment panel: active profile preset has been modified")
                : String(localized: "Active profile", comment: "Adjustment panel subtitle for the active profile preset"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// One adjustment rendered as its own bordered glass panel. `fraction` drives a reversed
    /// countdown border (1 = full, 0 = empty); pass nil for no border.
    @ViewBuilder func adjustmentPanel<Content: View>(
        tint: Color?,
        fraction: Double?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack {
            content()
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: HomeLayout.bottomPanelHeight)
        .glassPanel(tint: tint, tintOpacity: 0.12, strokeOpacity: tint == nil ? 0.08 : 0.30)
        .progressRoundedBorderIfPresent(
            progress: fraction,
            color: tint,
            cornerRadius: GlassChrome.panelCornerRadius,
            lineWidth: 3
        )
        .contentShape(Rectangle())
        .onTapGesture { selectedTab = 2 }
    }

    @ViewBuilder func adjustmentView() -> some View {
        // Each active adjustment is its own bordered panel, side by side. Override and temp
        // target show a reversed countdown border (full → empty as they run out); the profile
        // preset has no expiry, so its border stays full.
        HStack(spacing: 8) {
            if let overrideString = overrideString {
                adjustmentPanel(tint: .purple, fraction: overrideRemainingFraction ?? 1) {
                    adjustmentsOverrideView(overrideString)
                    Spacer(minLength: 0)
                    adjustmentsCancelOverrideView()
                }
            }
            if let tempTargetString = tempTargetString {
                adjustmentPanel(tint: .loopGreen, fraction: tempTargetRemainingFraction ?? 1) {
                    adjustmentsTempTargetView(tempTargetString)
                    Spacer(minLength: 0)
                    adjustmentsCancelTempTargetView()
                }
            }
            if let preset = state.activeProfilePreset {
                adjustmentPanel(tint: state.isProfileDiverged ? .orange : .accentColor, fraction: 1) {
                    activeProfileContent(preset)
                    Spacer(minLength: 0)
                }
            }
            if overrideString == nil, tempTargetString == nil, state.activeProfilePreset == nil {
                adjustmentPanel(tint: nil, fraction: nil) {
                    noActiveAdjustmentsView()
                }
            }
        }
        .padding(.horizontal, 10)
    }

    @ViewBuilder func bolusView(_ progress: Decimal) -> some View {
        /// ensure that state.lastPumpBolus has a value, i.e. there is a last bolus done by the pump and not an external bolus
        /// - TRUE:  show the pump bolus
        /// - FALSE:  do not show a progress bar at all
        if let bolusTotal = state.lastPumpBolus?.bolus?.amount {
            let bolusFraction = progress * (bolusTotal as Decimal)
            let progressValue = (progress as NSDecimalNumber).doubleValue
            let bolusString =
                (bolusProgressFormatter.string(from: bolusFraction as NSNumber) ?? "0")
                    + String(localized: " of ", comment: "Bolus string partial message: 'x U of y U' in home view") +
                    (Formatter.decimalFormatterWithThreeFractionDigits.string(from: bolusTotal as NSNumber) ?? "0")
                    + String(localized: " U", comment: "Insulin unit")
            let bolusLabel = state
                .bolusStatus == .inProgress ? String(localized: "Bolusing") : String(localized: "Initiating…")

            HStack {
                Image(systemName: "cross.vial.fill")
                    .font(.system(size: 25))

                Spacer()

                VStack {
                    Text(bolusLabel)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(bolusString)
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.padding(.leading, 5)

                Spacer()

                if state.bolusStatus == .inProgress {
                    Button {
                        state.showProgressView()
                        state.cancelBolus()
                    } label: {
                        Image(systemName: "xmark.app")
                            .font(.system(size: 25))
                    }
                } else if state.bolusStatus == .initiating {
                    ProgressView()
                }
            }
            .padding(.horizontal, 10)
            .padding(.trailing, 8)
            .frame(height: HomeLayout.bottomPanelHeight)
            .glassPanel(tint: .insulin, tintOpacity: 0.18, strokeOpacity: 0.30)
            // Animated progress border: a bright fill runs left→right along the top and
            // bottom edges as the bolus completes, matching the pump/loop pill border.
            .progressRoundedBorder(
                progress: progressValue,
                color: .insulin,
                cornerRadius: GlassChrome.panelCornerRadius,
                lineWidth: 3
            )
            .padding(.horizontal, 10)
        }
    }

    /// Mean glucose (mg/dL) of today's readings, nil without data.
    private var todayMeanGlucose: Double? {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let values = state.glucoseFromPersistence
            .filter { ($0.date ?? .distantPast) >= startOfDay }
            .map { Double($0.glucose) }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private var todayAverageString: String {
        guard let mean = todayMeanGlucose else { return "--" }
        if state.units == .mmolL {
            return Decimal(mean).asMmolL.formatted(.number.precision(.fractionLength(1))) + " " + GlucoseUnits.mmolL.rawValue
        }
        return "\(Int(mean.rounded())) " + GlucoseUnits.mgdL.rawValue
    }

    private var todayGMIString: String {
        guard let mean = todayMeanGlucose else { return "--" }
        let gmiPercentage = 3.31 + 0.02392 * mean
        // settingsManager is injected after first render; default until then
        if state.settingsManager?.settings.eA1cDisplayUnit == .mmolMol {
            let gmiMmolMol = (gmiPercentage - 2.152) * 10.929
            return "\(Int(gmiMmolMol.rounded())) mmol/mol"
        }
        return gmiPercentage.formatted(.number.precision(.fractionLength(1))) + " %"
    }

    @ViewBuilder func statsBanner() -> some View {
        let face = state.settingsManager?.settings.homeStatsPanelFace ?? .timeInRange
        let distribution = state.todayGlucoseDistribution
        let coveragePct = distribution.veryLowPct + distribution.lowPct + distribution.inRangePct + distribution
            .highPct + distribution.veryHighPct
        let hasData = coveragePct > 0
        let tirString = hasData
            ? distribution.inRangePct.formatted(.number.precision(.fractionLength(0 ... 1))) + " %"
            : "-- %"
        // Softer than the bolus/adjustment borders — this panel is informational, not an alert.
        let segments: [(color: Color, fraction: CGFloat)] = hasData ? [
            (.red.opacity(0.6), CGFloat(distribution.veryLowPct / 100)),
            (.orange.opacity(0.6), CGFloat(distribution.lowPct / 100)),
            (.loopGreen.opacity(0.6), CGFloat(distribution.inRangePct / 100)),
            (.purple.opacity(0.6), CGFloat((distribution.highPct + distribution.veryHighPct) / 100))
        ] : [(Color.secondary.opacity(0.25), 1)]

        Button {
            state.showModal(for: .statistics)
        } label: {
            ZStack {
                HStack(alignment: .center, spacing: 12) {
                    switch face {
                    case .timeInRange:
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .center, spacing: 6) {
                                Text(tirString)
                                    .font(.title2).fontWeight(.bold).fontDesign(.rounded)
                                    .foregroundStyle(.primary)
                                // chart shows 72h; make the daily scope explicit
                                (
                                    Text("Time in Range", comment: "Stats banner subtitle").fontWeight(.semibold)
                                        + Text(" ")
                                        + Text("today", comment: "Stats banner scope")
                                )
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            }
                        }
                    case .distributionBar:
                        VStack(alignment: .leading, spacing: 6) {
                            (
                                Text("Time in Range", comment: "Stats banner subtitle").fontWeight(.semibold)
                                    + Text(" ")
                                    + Text("today", comment: "Stats banner scope")
                            )
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        }
                    case .averages:
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\u{2300} \(todayAverageString) \u{00B7} GMI \(todayGMIString)")
                                .font(.subheadline).fontWeight(.semibold)
                                .foregroundStyle(.primary)
                            Text("Today's average", comment: "Stats banner subtitle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
            }
            .frame(height: HomeLayout.statsBannerHeight)
            .glassPanel()
            // Time-in-range distribution as the panel border (same edge treatment as the
            // bolus progress border): red / orange / green / purple laid out left → right.
            .segmentedRoundedBorder(segments: segments, cornerRadius: GlassChrome.panelCornerRadius, lineWidth: 2)
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    var multiUsePanelState: MultiUsePanelState {
        MultiUsePanelState.resolve(
            notificationsDisabled: notificationsDisabled,
            pumpTimeMismatch: state.pumpStatusBadgeImage != nil,
            lastGlucoseDate: state.glucoseFromPersistence.last?.date,
            maxIOB: state.maxIOB,
            now: state.timerDate
        )
    }

    /// Shared chrome for the non-stats panel states.
    @ViewBuilder func panelBanner(
        systemImage: String,
        title: String,
        subtitle: String,
        tint: Color,
        isCritical: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                HStack(spacing: 12) {
                    adjustmentIcon(systemImage, tint: tint)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundStyle(.primary)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
            }
            .frame(height: HomeLayout.statsBannerHeight)
            .glassPanel(
                tint: tint,
                tintOpacity: isCritical ? 0.30 : 0.12,
                strokeOpacity: isCritical ? 0.8 : 0.35,
                strokeWidth: isCritical ? 1.5 : 1
            )
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// One slot, highest-priority state wins; stats is the default face.
    @ViewBuilder func multiUsePanel() -> some View {
        switch multiUsePanelState {
        case .notificationsDisabled:
            panelBanner(
                systemImage: "bell.slash.fill",
                title: String(localized: "Notifications Disabled"),
                subtitle: String(localized: "Alarms cannot alert you. Tap to fix."),
                tint: .red,
                isCritical: true
            ) {
                UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
            }
        case .pumpTimeMismatch:
            panelBanner(
                systemImage: "clock.badge.exclamationmark.fill",
                title: String(localized: "Time Change Detected"),
                subtitle: String(localized: "Pump clock differs from phone. Tap to review."),
                tint: .orange
            ) {
                if state.pumpDisplayState != nil {
                    state.shouldDisplayPumpSetupSheet.toggle()
                }
            }
        case .cgmStale:
            panelBanner(
                systemImage: "drop.fill",
                title: String(localized: "No Recent Glucose"),
                subtitle: String(localized: "Tap to add a fingerstick reading."),
                tint: .orange
            ) {
                showManualGlucose = true
            }
        case .maxIOBZero:
            panelBanner(
                systemImage: "exclamationmark.triangle.fill",
                title: String(localized: "Max IOB is 0 U"),
                subtitle: String(localized: "Automated dosing is limited. Tap to review."),
                tint: .orange
            ) {
                openMaxIOBSetting()
            }
        case .stats:
            statsBanner()
        }
    }

    func openMaxIOBSetting() {
        // same target search results push, so scroll + highlight wiggle match
        selectedTab = 3
        settingsPath.append(SearchResultTarget(
            screen: .unitsAndLimits,
            scrollLabel: "Maximum Insulin on Board (IOB)".localized
        ))
    }

    /// Bottom-anchored fixed zone: adjustment/bolus panel above the stats banner.
    @ViewBuilder func bottomControls() -> some View {
        VStack(spacing: HomeLayout.bottomZonePadding) {
            Group {
                if let progress = state.bolusProgress {
                    bolusView(progress)
                } else {
                    adjustmentView()
                }
            }
            .frame(height: HomeLayout.bottomPanelHeight)
            .animation(.easeInOut(duration: 0.2), value: state.bolusProgress != nil)

            multiUsePanel()
                .frame(height: HomeLayout.statsBannerHeight)
        }
        .padding(.vertical, HomeLayout.bottomZonePadding)
    }
}
