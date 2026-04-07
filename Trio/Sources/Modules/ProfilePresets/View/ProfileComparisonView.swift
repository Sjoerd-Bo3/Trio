import SwiftUI

extension ProfilePresets {
    struct ComparisonView: View {
        let presetA: ProfilePreset
        let presetB: ProfilePreset
        let units: GlucoseUnits
        @State private var showDifferencesOnly: Bool = true

        var body: some View {
            List {
                Section {
                    Toggle(isOn: $showDifferencesOnly) {
                        Label {
                            Text(
                                "Differences Only",
                                comment: "ProfileComparison: toggle to show only differences"
                            )
                        } icon: {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .foregroundColor(.accentColor)
                        }
                    }
                }

                overviewSection
                basalComparisonSection
                isfComparisonSection
                crComparisonSection
                targetsComparisonSection

                if presetA.smbSettings != nil || presetB.smbSettings != nil {
                    smbComparisonSection
                }

                if presetA.dynamicSettings != nil || presetB.dynamicSettings != nil {
                    dynamicComparisonSection
                }
            }
            .navigationTitle(Text("Compare Profiles", comment: "ProfileComparison: navigation title"))
            .navigationBarTitleDisplayMode(.inline)
        }

        // MARK: - Overview

        private var overviewSection: some View {
            Section {
                comparisonHeader

                if !showDifferencesOnly || presetA.totalDailyBasal != presetB.totalDailyBasal {
                    HStack {
                        Text("Total Daily Basal", comment: "ProfileComparison: total daily basal label")
                            .font(.subheadline)
                        Spacer()
                        valueColumns(
                            leftValue: presetA.totalDailyBasal,
                            rightValue: presetB.totalDailyBasal,
                            leftText: "\(formattedBasalTotal(presetA)) U",
                            rightText: "\(formattedBasalTotal(presetB)) U"
                        )
                    }
                }

                if !showDifferencesOnly
                    || presetA.insulinSensitivities.sensitivities.count
                        != presetB.insulinSensitivities.sensitivities.count
                {
                    HStack {
                        Text("ISF Entries", comment: "ProfileComparison: ISF entries count label")
                            .font(.subheadline)
                        Spacer()
                        let countA = presetA.insulinSensitivities.sensitivities.count
                        let countB = presetB.insulinSensitivities.sensitivities.count
                        valueColumns(
                            leftValue: Decimal(countA),
                            rightValue: Decimal(countB),
                            leftText: "\(countA)",
                            rightText: "\(countB)"
                        )
                    }
                }

                if !showDifferencesOnly || presetA.carbRatios.schedule.count != presetB.carbRatios.schedule.count {
                    HStack {
                        Text("CR Entries", comment: "ProfileComparison: CR entries count label")
                            .font(.subheadline)
                        Spacer()
                        let countA = presetA.carbRatios.schedule.count
                        let countB = presetB.carbRatios.schedule.count
                        valueColumns(
                            leftValue: Decimal(countA),
                            rightValue: Decimal(countB),
                            leftText: "\(countA)",
                            rightText: "\(countB)"
                        )
                    }
                }
            }
        }

        // MARK: - Basal Comparison

        private var basalComparisonSection: some View {
            let maxEntries = max(presetA.basalProfile.count, presetB.basalProfile.count)
            let hasDifferences = (0 ..< maxEntries).contains { index in
                let entryA = index < presetA.basalProfile.count ? presetA.basalProfile[index] : nil
                let entryB = index < presetB.basalProfile.count ? presetB.basalProfile[index] : nil
                return entryA?.rate != entryB?.rate || entryA?.start != entryB?.start
            }

            return Group {
                if !showDifferencesOnly || hasDifferences {
                    Section(
                        header: Text("Basal Rates", comment: "ProfileComparison: section header for basal rates")
                    ) {
                        comparisonHeader

                        ForEach(0 ..< maxEntries, id: \.self) { index in
                            let entryA = index < presetA.basalProfile.count ? presetA.basalProfile[index] : nil
                            let entryB = index < presetB.basalProfile.count ? presetB.basalProfile[index] : nil
                            let isDifferent = entryA?.rate != entryB?.rate || entryA?.start != entryB?.start

                            if !showDifferencesOnly || isDifferent {
                                let time = entryA?.start ?? entryB?.start ?? ""
                                HStack {
                                    Text(time)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .frame(width: 55, alignment: .leading)
                                    Spacer()
                                    valueColumns(
                                        leftValue: entryA?.rate,
                                        rightValue: entryB?.rate,
                                        leftText: entryA.map { formatRate($0.rate) } ?? "—",
                                        rightText: entryB.map { formatRate($0.rate) } ?? "—"
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }

        // MARK: - ISF Comparison

        private var isfComparisonSection: some View {
            let sensA = presetA.insulinSensitivities.sensitivities
            let sensB = presetB.insulinSensitivities.sensitivities
            let maxEntries = max(sensA.count, sensB.count)
            let hasDifferences = (0 ..< maxEntries).contains { index in
                let entryA = index < sensA.count ? sensA[index] : nil
                let entryB = index < sensB.count ? sensB[index] : nil
                return entryA?.sensitivity != entryB?.sensitivity || entryA?.start != entryB?.start
            }

            return Group {
                if !showDifferencesOnly || hasDifferences {
                    Section(
                        header: Text(
                            "Insulin Sensitivities (ISF)",
                            comment: "ProfileComparison: section header for ISF"
                        )
                    ) {
                        comparisonHeader

                        ForEach(0 ..< maxEntries, id: \.self) { index in
                            let entryA = index < sensA.count ? sensA[index] : nil
                            let entryB = index < sensB.count ? sensB[index] : nil
                            let isDifferent = entryA?.sensitivity != entryB?.sensitivity || entryA?.start != entryB?.start

                            if !showDifferencesOnly || isDifferent {
                                let time = entryA?.start ?? entryB?.start ?? ""
                                HStack {
                                    Text(time)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .frame(width: 55, alignment: .leading)
                                    Spacer()
                                    valueColumns(
                                        leftValue: entryA?.sensitivity,
                                        rightValue: entryB?.sensitivity,
                                        leftText: entryA.map { formatGlucose($0.sensitivity) } ?? "—",
                                        rightText: entryB.map { formatGlucose($0.sensitivity) } ?? "—"
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }

        // MARK: - CR Comparison

        private var crComparisonSection: some View {
            let schedA = presetA.carbRatios.schedule
            let schedB = presetB.carbRatios.schedule
            let maxEntries = max(schedA.count, schedB.count)
            let hasDifferences = (0 ..< maxEntries).contains { index in
                let entryA = index < schedA.count ? schedA[index] : nil
                let entryB = index < schedB.count ? schedB[index] : nil
                return entryA?.ratio != entryB?.ratio || entryA?.start != entryB?.start
            }

            return Group {
                if !showDifferencesOnly || hasDifferences {
                    Section(
                        header: Text("Carb Ratios (CR)", comment: "ProfileComparison: section header for CR")
                    ) {
                        comparisonHeader

                        ForEach(0 ..< maxEntries, id: \.self) { index in
                            let entryA = index < schedA.count ? schedA[index] : nil
                            let entryB = index < schedB.count ? schedB[index] : nil
                            let isDifferent = entryA?.ratio != entryB?.ratio || entryA?.start != entryB?.start

                            if !showDifferencesOnly || isDifferent {
                                let time = entryA?.start ?? entryB?.start ?? ""
                                HStack {
                                    Text(time)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .frame(width: 55, alignment: .leading)
                                    Spacer()
                                    valueColumns(
                                        leftValue: entryA?.ratio,
                                        rightValue: entryB?.ratio,
                                        leftText: entryA.map { formatDecimal($0.ratio) } ?? "—",
                                        rightText: entryB.map { formatDecimal($0.ratio) } ?? "—"
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }

        // MARK: - Targets Comparison

        private var targetsComparisonSection: some View {
            let targetsA = presetA.bgTargets.targets
            let targetsB = presetB.bgTargets.targets
            let maxEntries = max(targetsA.count, targetsB.count)
            let hasDifferences = (0 ..< maxEntries).contains { index in
                let entryA = index < targetsA.count ? targetsA[index] : nil
                let entryB = index < targetsB.count ? targetsB[index] : nil
                return entryA?.low != entryB?.low || entryA?.high != entryB?.high || entryA?.start != entryB?.start
            }

            return Group {
                if !showDifferencesOnly || hasDifferences {
                    Section(
                        header: Text("Glucose Targets", comment: "ProfileComparison: section header for glucose targets")
                    ) {
                        comparisonHeader

                        ForEach(0 ..< maxEntries, id: \.self) { index in
                            let entryA = index < targetsA.count ? targetsA[index] : nil
                            let entryB = index < targetsB.count ? targetsB[index] : nil
                            let isDifferent = entryA?.low != entryB?.low
                                || entryA?.high != entryB?.high
                                || entryA?.start != entryB?.start

                            if !showDifferencesOnly || isDifferent {
                                let time = entryA?.start ?? entryB?.start ?? ""
                                HStack {
                                    Text(time)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .frame(width: 55, alignment: .leading)
                                    Spacer()
                                    let leftText = entryA
                                        .map { "\(formatGlucose($0.low))–\(formatGlucose($0.high))" } ?? "—"
                                    let rightText = entryB
                                        .map { "\(formatGlucose($0.low))–\(formatGlucose($0.high))" } ?? "—"
                                    Text(leftText)
                                        .font(.subheadline.monospacedDigit())
                                        .foregroundColor(isDifferent ? .accentColor : .primary)
                                        .frame(width: 80, alignment: .trailing)
                                    if isDifferent {
                                        Image(systemName: "arrowshape.right.fill")
                                            .font(.system(size: 8))
                                            .foregroundColor(.orange)
                                    }
                                    Text(rightText)
                                        .font(.subheadline.monospacedDigit())
                                        .foregroundColor(isDifferent ? .purple : .primary)
                                        .frame(width: 80, alignment: .trailing)
                                }
                            }
                        }
                    }
                }
            }
        }

        // MARK: - SMB Comparison

        private var smbComparisonSection: some View {
            let smbA = presetA.smbSettings
            let smbB = presetB.smbSettings
            let hasDifferences = smbA?.enableSMBAlways != smbB?.enableSMBAlways
                || smbA?.enableSMBWithCOB != smbB?.enableSMBWithCOB
                || smbA?.enableSMBWithTemptarget != smbB?.enableSMBWithTemptarget
                || smbA?.enableSMBAfterCarbs != smbB?.enableSMBAfterCarbs
                || smbA?.enableUAM != smbB?.enableUAM
                || smbA?.enableSMBHighBG != smbB?.enableSMBHighBG
                || smbA?.maxSMBBasalMinutes != smbB?.maxSMBBasalMinutes
                || smbA?.maxUAMSMBBasalMinutes != smbB?.maxUAMSMBBasalMinutes

            return Group {
                if !showDifferencesOnly || hasDifferences {
                    Section(
                        header: Text("SMB Settings", comment: "ProfileComparison: section header for SMB settings")
                    ) {
                        comparisonHeader

                        boolComparisonRow(
                            label: String(localized: "SMB Always", comment: "ProfileComparison: SMB setting"),
                            valueA: smbA?.enableSMBAlways,
                            valueB: smbB?.enableSMBAlways
                        )
                        boolComparisonRow(
                            label: String(localized: "SMB with COB", comment: "ProfileComparison: SMB setting"),
                            valueA: smbA?.enableSMBWithCOB,
                            valueB: smbB?.enableSMBWithCOB
                        )
                        boolComparisonRow(
                            label: String(localized: "SMB with Temp Target", comment: "ProfileComparison: SMB setting"),
                            valueA: smbA?.enableSMBWithTemptarget,
                            valueB: smbB?.enableSMBWithTemptarget
                        )
                        boolComparisonRow(
                            label: String(localized: "SMB After Carbs", comment: "ProfileComparison: SMB setting"),
                            valueA: smbA?.enableSMBAfterCarbs,
                            valueB: smbB?.enableSMBAfterCarbs
                        )
                        boolComparisonRow(
                            label: String(localized: "UAM", comment: "ProfileComparison: SMB setting"),
                            valueA: smbA?.enableUAM,
                            valueB: smbB?.enableUAM
                        )
                        boolComparisonRow(
                            label: String(localized: "SMB High BG", comment: "ProfileComparison: SMB setting"),
                            valueA: smbA?.enableSMBHighBG,
                            valueB: smbB?.enableSMBHighBG
                        )
                        decimalComparisonRow(
                            label: String(localized: "Max SMB Minutes", comment: "ProfileComparison: SMB setting"),
                            valueA: smbA?.maxSMBBasalMinutes,
                            valueB: smbB?.maxSMBBasalMinutes,
                            decimals: 0,
                            suffix: " min"
                        )
                        decimalComparisonRow(
                            label: String(localized: "Max UAM Minutes", comment: "ProfileComparison: SMB setting"),
                            valueA: smbA?.maxUAMSMBBasalMinutes,
                            valueB: smbB?.maxUAMSMBBasalMinutes,
                            decimals: 0,
                            suffix: " min"
                        )
                    }
                }
            }
        }

        // MARK: - Dynamic ISF Comparison

        private var dynamicComparisonSection: some View {
            let dynA = presetA.dynamicSettings
            let dynB = presetB.dynamicSettings
            let typeA = dynA.map { dynamicISFType(for: $0) } ?? "—"
            let typeB = dynB.map { dynamicISFType(for: $0) } ?? "—"
            let hasDifferences = typeA != typeB
                || dynA?.adjustmentFactor != dynB?.adjustmentFactor
                || dynA?.adjustmentFactorSigmoid != dynB?.adjustmentFactorSigmoid
                || dynA?.weightPercentage != dynB?.weightPercentage
                || dynA?.tddAdjBasal != dynB?.tddAdjBasal

            return Group {
                if !showDifferencesOnly || hasDifferences {
                    Section(
                        header: Text(
                            "dynISF Settings",
                            comment: "ProfileComparison: section header for Dynamic ISF settings"
                        )
                    ) {
                        comparisonHeader

                        if !showDifferencesOnly || typeA != typeB {
                            HStack {
                                Text("Type", comment: "ProfileComparison: Dynamic ISF type label")
                                    .font(.subheadline)
                                Spacer()
                                let isDifferent = typeA != typeB
                                Text(typeA)
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundColor(isDifferent ? .accentColor : .primary)
                                    .frame(width: 80, alignment: .trailing)
                                if isDifferent {
                                    Image(systemName: "arrowshape.right.fill")
                                        .font(.system(size: 8))
                                        .foregroundColor(.orange)
                                }
                                Text(typeB)
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundColor(isDifferent ? .purple : .primary)
                                    .frame(width: 80, alignment: .trailing)
                            }
                        }

                        decimalComparisonRow(
                            label: String(
                                localized: "Adjustment Factor",
                                comment: "ProfileComparison: Dynamic ISF setting"
                            ),
                            valueA: dynA?.adjustmentFactor,
                            valueB: dynB?.adjustmentFactor,
                            decimals: 2
                        )
                        decimalComparisonRow(
                            label: String(
                                localized: "Sigmoid Factor",
                                comment: "ProfileComparison: Dynamic ISF setting"
                            ),
                            valueA: dynA?.adjustmentFactorSigmoid,
                            valueB: dynB?.adjustmentFactorSigmoid,
                            decimals: 2
                        )
                        decimalComparisonRow(
                            label: String(localized: "Weight %", comment: "ProfileComparison: Dynamic ISF setting"),
                            valueA: dynA?.weightPercentage,
                            valueB: dynB?.weightPercentage,
                            decimals: 2
                        )
                        boolComparisonRow(
                            label: String(
                                localized: "TDD Adj Basal",
                                comment: "ProfileComparison: Dynamic ISF setting"
                            ),
                            valueA: dynA?.tddAdjBasal,
                            valueB: dynB?.tddAdjBasal
                        )
                    }
                }
            }
        }

        // MARK: - Shared Components

        private var comparisonHeader: some View {
            HStack {
                Spacer()
                Text(presetA.name)
                    .font(.caption.bold())
                    .foregroundColor(.accentColor)
                    .frame(width: 80, alignment: .trailing)
                    .lineLimit(1)
                Text(presetB.name)
                    .font(.caption.bold())
                    .foregroundColor(.purple)
                    .frame(width: 80, alignment: .trailing)
                    .lineLimit(1)
            }
        }

        /// Value columns with arrow indicator when values differ.
        /// Uses numeric comparison to show directional arrows.
        @ViewBuilder private func valueColumns(
            leftValue: Decimal?,
            rightValue: Decimal?,
            leftText: String,
            rightText: String
        ) -> some View {
            let isDifferent = leftValue != rightValue
            Text(leftText)
                .font(.subheadline.monospacedDigit())
                .foregroundColor(isDifferent ? .accentColor : .primary)
                .frame(width: 80, alignment: .trailing)
            if isDifferent, let lv = leftValue, let rv = rightValue {
                Image(systemName: lv < rv ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 8))
                    .foregroundColor(lv < rv ? .loopGreen : .orange)
            } else if isDifferent {
                Image(systemName: "arrowshape.right.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.orange)
            }
            Text(rightText)
                .font(.subheadline.monospacedDigit())
                .foregroundColor(isDifferent ? .purple : .primary)
                .frame(width: 80, alignment: .trailing)
        }

        @ViewBuilder private func boolComparisonRow(label: String, valueA: Bool?, valueB: Bool?) -> some View {
            let isDifferent = valueA != valueB
            if !showDifferencesOnly || isDifferent {
                HStack {
                    Text(label)
                        .font(.subheadline)
                    Spacer()
                    let leftText = valueA.map { $0 ? "✓" : "✗" } ?? "—"
                    let rightText = valueB.map { $0 ? "✓" : "✗" } ?? "—"
                    Text(leftText)
                        .font(.subheadline.monospacedDigit())
                        .foregroundColor(isDifferent ? .accentColor : .primary)
                        .frame(width: 80, alignment: .trailing)
                    if isDifferent {
                        Image(systemName: "arrowshape.right.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.orange)
                    }
                    Text(rightText)
                        .font(.subheadline.monospacedDigit())
                        .foregroundColor(isDifferent ? .purple : .primary)
                        .frame(width: 80, alignment: .trailing)
                }
            }
        }

        @ViewBuilder private func decimalComparisonRow(
            label: String,
            valueA: Decimal?,
            valueB: Decimal?,
            decimals: Int = 1,
            suffix: String = ""
        ) -> some View {
            if !showDifferencesOnly || valueA != valueB {
                HStack {
                    Text(label)
                        .font(.subheadline)
                    Spacer()
                    valueColumns(
                        leftValue: valueA,
                        rightValue: valueB,
                        leftText: valueA.map { formatDecimal($0, decimals: decimals) + suffix } ?? "—",
                        rightText: valueB.map { formatDecimal($0, decimals: decimals) + suffix } ?? "—"
                    )
                }
            }
        }

        // MARK: - Formatting Helpers

        private func formattedBasalTotal(_ preset: ProfilePreset) -> String {
            String(format: "%.2f", NSDecimalNumber(decimal: preset.totalDailyBasal).doubleValue)
        }

        private func formatRate(_ value: Decimal) -> String {
            String(format: "%.2f", NSDecimalNumber(decimal: value).doubleValue)
        }

        private func formatDecimal(_ value: Decimal, decimals: Int = 1) -> String {
            String(format: "%.\(decimals)f", NSDecimalNumber(decimal: value).doubleValue)
        }

        private func formatGlucose(_ value: Decimal) -> String {
            let displayValue = units == .mmolL ? value.asMmolL : value
            return units == .mmolL
                ? formatDecimal(displayValue, decimals: 1)
                : formatDecimal(displayValue, decimals: 0)
        }

        private func dynamicISFType(for settings: DynamicPresetSettings) -> String {
            if settings.useNewFormula {
                return settings.sigmoid
                    ? String(localized: "Sigmoid", comment: "ProfileComparison: sigmoid type")
                    : String(localized: "Logarithmic", comment: "ProfileComparison: logarithmic type")
            }
            return String(localized: "Disabled", comment: "ProfileComparison: disabled type")
        }
    }
}
