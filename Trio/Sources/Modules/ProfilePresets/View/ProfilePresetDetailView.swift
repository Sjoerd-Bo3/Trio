import SwiftUI

extension ProfilePresets {
    struct PresetDetailView: View {
        let preset: ProfilePreset
        let units: GlucoseUnits
        let formattedBasalTotal: String

        private enum DetailTab: String, CaseIterable {
            case basal
            case isf
            case cr
            case targets
            case smbDyn

            var label: String {
                switch self {
                case .basal: String(localized: "Basal", comment: "ProfilePresetDetail: tab label for basal rates")
                case .isf: String(localized: "ISF", comment: "ProfilePresetDetail: tab label for ISF")
                case .cr: String(localized: "CR", comment: "ProfilePresetDetail: tab label for carb ratios")
                case .targets: String(localized: "Targets", comment: "ProfilePresetDetail: tab label for glucose targets")
                case .smbDyn: String(localized: "SMB / dynISF", comment: "ProfilePresetDetail: tab label for SMB and dynamic ISF")
                }
            }
        }

        @State private var selectedTab: DetailTab = .basal

        private var hasSMBOrDynamic: Bool {
            preset.smbSettings != nil || preset.dynamicSettings != nil
        }

        private var availableTabs: [DetailTab] {
            var tabs: [DetailTab] = [.basal, .isf, .cr, .targets]
            if hasSMBOrDynamic {
                tabs.append(.smbDyn)
            }
            return tabs
        }

        var body: some View {
            VStack(spacing: 0) {
                // Standard segmented picker tab bar
                Picker(
                    String(localized: "Detail Tab", comment: "ProfilePresetDetail: tab picker accessibility label"),
                    selection: $selectedTab
                ) {
                    ForEach(availableTabs, id: \.self) { tab in
                        Text(tab.label).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                // Tab content
                switch selectedTab {
                case .basal:
                    basalTab
                case .isf:
                    isfTab
                case .cr:
                    crTab
                case .targets:
                    targetsTab
                case .smbDyn:
                    smbDynTab
                }
            }
            .navigationTitle(Text(preset.name))
            .navigationBarTitleDisplayMode(.inline)
        }

        // MARK: - Basal Tab

        private var basalTab: some View {
            List {
                Section(
                    header: Text("Basal Rates", comment: "ProfilePresetDetail: section header for basal rates")
                ) {
                    BasalChartView(basalProfile: preset.basalProfile)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))

                    HStack {
                        Text("Total Daily Basal", comment: "ProfilePresetDetail: total daily basal label")
                            .font(.subheadline.bold())
                        Spacer()
                        Text("\(formattedBasalTotal) U/day")
                            .font(.subheadline.bold())
                            .foregroundColor(.insulin)
                    }

                    ForEach(Array(preset.basalProfile.enumerated()), id: \.offset) { _, entry in
                        HStack {
                            Text(entry.start)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(formatRate(entry.rate)) U/hr")
                                .font(.subheadline.monospacedDigit())
                        }
                    }
                }
            }
        }

        // MARK: - ISF Tab

        private var isfTab: some View {
            List {
                Section(
                    header: Text(
                        "Insulin Sensitivities (ISF)",
                        comment: "ProfilePresetDetail: section header for ISF"
                    )
                ) {
                    ISFChartView(sensitivities: preset.insulinSensitivities.sensitivities, units: units)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))

                    ForEach(Array(preset.insulinSensitivities.sensitivities.enumerated()), id: \.offset) { _, entry in
                        HStack {
                            Text(entry.start)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(formatGlucose(entry.sensitivity)) \(units.rawValue)")
                                .font(.subheadline.monospacedDigit())
                        }
                    }
                }
            }
        }

        // MARK: - CR Tab

        private var crTab: some View {
            List {
                Section(
                    header: Text("Carb Ratios (CR)", comment: "ProfilePresetDetail: section header for CR")
                ) {
                    CRChartView(schedule: preset.carbRatios.schedule)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))

                    ForEach(Array(preset.carbRatios.schedule.enumerated()), id: \.offset) { _, entry in
                        HStack {
                            Text(entry.start)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(
                                "\(formatDecimal(entry.ratio)) g/U",
                                comment: "ProfilePresetDetail: carb ratio value in grams per unit"
                            )
                            .font(.subheadline.monospacedDigit())
                        }
                    }
                }
            }
        }

        // MARK: - Targets Tab

        private var targetsTab: some View {
            List {
                Section(
                    header: Text("Glucose Targets", comment: "ProfilePresetDetail: section header for glucose targets")
                ) {
                    TargetsChartView(targets: preset.bgTargets.targets, units: units)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))

                    ForEach(Array(preset.bgTargets.targets.enumerated()), id: \.offset) { _, entry in
                        HStack {
                            Text(entry.start)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(formatGlucose(entry.low)) – \(formatGlucose(entry.high)) \(units.rawValue)")
                                .font(.subheadline.monospacedDigit())
                        }
                    }
                }
            }
        }

        // MARK: - SMB / dynISF Tab

        private var smbDynTab: some View {
            List {
                if let smb = preset.smbSettings {
                    smbSection(smb)
                }

                if let dynamic = preset.dynamicSettings {
                    dynamicSection(dynamic)
                }
            }
        }

        // MARK: - SMB Section

        private func smbSection(_ smb: SMBPresetSettings) -> some View {
            Section(
                header: Text("SMB Settings", comment: "ProfilePresetDetail: section header for SMB settings")
            ) {
                settingRow(
                    label: String(localized: "Enable SMB Always", comment: "ProfilePresetDetail: SMB setting"),
                    value: smb.enableSMBAlways ? "✓" : "✗"
                )
                settingRow(
                    label: String(localized: "Enable SMB with COB", comment: "ProfilePresetDetail: SMB setting"),
                    value: smb.enableSMBWithCOB ? "✓" : "✗"
                )
                settingRow(
                    label: String(localized: "Enable SMB with Temp Target", comment: "ProfilePresetDetail: SMB setting"),
                    value: smb.enableSMBWithTemptarget ? "✓" : "✗"
                )
                settingRow(
                    label: String(localized: "Enable SMB After Carbs", comment: "ProfilePresetDetail: SMB setting"),
                    value: smb.enableSMBAfterCarbs ? "✓" : "✗"
                )
                settingRow(
                    label: String(localized: "Enable UAM", comment: "ProfilePresetDetail: SMB setting"),
                    value: smb.enableUAM ? "✓" : "✗"
                )
                settingRow(
                    label: String(localized: "Enable SMB High BG", comment: "ProfilePresetDetail: SMB setting"),
                    value: smb.enableSMBHighBG ? "✓" : "✗"
                )
                if smb.enableSMBHighBG {
                    settingRow(
                        label: String(
                            localized: "SMB High BG Target",
                            comment: "ProfilePresetDetail: SMB setting"
                        ),
                        value: "\(formatGlucose(smb.enableSMBHighBGTarget)) \(units.rawValue)"
                    )
                }
                settingRow(
                    label: String(
                        localized: "Max SMB Basal Minutes",
                        comment: "ProfilePresetDetail: SMB setting"
                    ),
                    value: "\(formatDecimal(smb.maxSMBBasalMinutes, decimals: 0)) min"
                )
                settingRow(
                    label: String(
                        localized: "Max UAM SMB Basal Minutes",
                        comment: "ProfilePresetDetail: SMB setting"
                    ),
                    value: "\(formatDecimal(smb.maxUAMSMBBasalMinutes, decimals: 0)) min"
                )
                settingRow(
                    label: String(
                        localized: "Max Delta BG Threshold",
                        comment: "ProfilePresetDetail: SMB setting"
                    ),
                    value: formatDecimal(smb.maxDeltaBGthreshold, decimals: 2)
                )
            }
        }

        // MARK: - Dynamic ISF Section

        private func dynamicSection(_ dynamic: DynamicPresetSettings) -> some View {
            Section(
                header: Text(
                    "dynISF Settings",
                    comment: "ProfilePresetDetail: section header for Dynamic ISF settings"
                )
            ) {
                settingRow(
                    label: String(localized: "Type", comment: "ProfilePresetDetail: Dynamic ISF type label"),
                    value: dynamicISFType(for: dynamic)
                )
                settingRow(
                    label: String(
                        localized: "Adjustment Factor",
                        comment: "ProfilePresetDetail: Dynamic ISF setting"
                    ),
                    value: formatDecimal(dynamic.adjustmentFactor, decimals: 2)
                )
                settingRow(
                    label: String(
                        localized: "Adjustment Factor (Sigmoid)",
                        comment: "ProfilePresetDetail: Dynamic ISF setting"
                    ),
                    value: formatDecimal(dynamic.adjustmentFactorSigmoid, decimals: 2)
                )
                settingRow(
                    label: String(
                        localized: "Weight Percentage",
                        comment: "ProfilePresetDetail: Dynamic ISF setting"
                    ),
                    value: formatDecimal(dynamic.weightPercentage, decimals: 2)
                )
                settingRow(
                    label: String(
                        localized: "TDD Adjusted Basal",
                        comment: "ProfilePresetDetail: Dynamic ISF setting"
                    ),
                    value: dynamic.tddAdjBasal ? "✓" : "✗"
                )
            }
        }

        // MARK: - Helpers

        @ViewBuilder private func settingRow(label: String, value: String) -> some View {
            HStack {
                Text(label)
                    .font(.subheadline)
                Spacer()
                Text(value)
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(.secondary)
            }
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
                    ? String(localized: "Sigmoid", comment: "ProfilePresetDetail: sigmoid type")
                    : String(localized: "Logarithmic", comment: "ProfilePresetDetail: logarithmic type")
            }
            return String(localized: "Disabled", comment: "ProfilePresetDetail: disabled type")
        }
    }
}
