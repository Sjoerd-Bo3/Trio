import SwiftUI
import Swinject

extension ProfilePresets {
    struct RootView: BaseView {
        let resolver: Resolver
        @State var state = StateModel()

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        var body: some View {
            Form {
                Section {
                    Button {
                        state.showingSaveDialog = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.accentColor)
                            Text(
                                "Save Current Profile as Preset",
                                comment: "ProfilePresets: button to save the current active profile as a new preset"
                            )
                        }
                    }
                }
                .listRowBackground(Color.chart)

                if state.presets.isEmpty {
                    Section {
                        Text(
                            "No profile presets saved yet. Save your current profile settings as a preset to quickly switch between different configurations.",
                            comment: "ProfilePresets: empty state message when no presets exist"
                        )
                        .foregroundColor(.secondary)
                        .font(.footnote)
                    }
                    .listRowBackground(Color.chart)
                } else {
                    Section(
                        header: Text(
                            "Saved Presets",
                            comment: "ProfilePresets: section header for list of saved presets"
                        )
                    ) {
                        ForEach(state.presets) { preset in
                            presetRow(preset)
                        }
                        .onDelete(perform: deletePresets)
                    }
                    .listRowBackground(Color.chart)
                }

                if state.presets.count >= 2 {
                    Section(
                        header: Text(
                            "Compare Presets",
                            comment: "ProfilePresets: section header for comparing two presets"
                        )
                    ) {
                        comparePresetsRow
                    }
                    .listRowBackground(Color.chart)
                }

                Section(
                    header: Text(
                        "About Profile Presets",
                        comment: "ProfilePresets: section header for info about profile presets"
                    )
                ) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label {
                            Text(
                                "Profile presets let you save and quickly switch between different therapy settings.",
                                comment: "ProfilePresets: explanation of what presets do"
                            )
                        } icon: {
                            Image(systemName: "info.circle")
                                .foregroundColor(.accentColor)
                        }
                        .font(.footnote)

                        Label {
                            Text(
                                "Each preset stores: Basal Rates, Insulin Sensitivities (ISF), Carb Ratios (CR), and Glucose Targets. Optionally also SMB and Dynamic ISF settings.",
                                comment: "ProfilePresets: description of what is stored in a preset"
                            )
                        } icon: {
                            Image(systemName: "list.bullet.clipboard")
                                .foregroundColor(.accentColor)
                        }
                        .font(.footnote)

                        Label {
                            Text(
                                "Use the percentage adjustment to create stronger or weaker variations of an existing preset as a starting point.",
                                comment: "ProfilePresets: explanation of percentage adjustment feature"
                            )
                        } icon: {
                            Image(systemName: "percent")
                                .foregroundColor(.accentColor)
                        }
                        .font(.footnote)

                        Label {
                            Text(
                                "Useful for switching between different therapy needs, such as sport days, sick days, or work days.",
                                comment: "ProfilePresets: use case examples"
                            )
                        } icon: {
                            Image(systemName: "figure.run")
                                .foregroundColor(.accentColor)
                        }
                        .font(.footnote)

                        Label {
                            Text(
                                "Note: Activating a preset will overwrite your current therapy settings. Basal rates are saved locally only and not synced to your pump automatically.",
                                comment: "ProfilePresets: warning about activating a preset"
                            )
                        } icon: {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                        }
                        .font(.footnote)
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Color.chart)
            }
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .onAppear(perform: configureView)
            .navigationTitle(Text("Profile Presets", comment: "ProfilePresets: navigation title"))
            .navigationBarTitleDisplayMode(.automatic)
            .sheet(isPresented: $state.showingSaveDialog) {
                savePresetSheet
            }
            .alert(
                Text("Activate Preset", comment: "ProfilePresets: alert title for activating a preset"),
                isPresented: $state.showingActivateConfirmation
            ) {
                Button(String(localized: "Activate", comment: "ProfilePresets: activate button")) {
                    if let preset = state.selectedPreset {
                        state.activatePreset(preset)
                    }
                    state.selectedPreset = nil
                }
                Button(String(localized: "Cancel", comment: "ProfilePresets: cancel button"), role: .cancel) {
                    state.selectedPreset = nil
                }
            } message: {
                if let preset = state.selectedPreset {
                    let extraSettings = activateExtraSettingsDescription(for: preset)
                    Text(
                        "This will overwrite your current Basal Rates, ISF, CR, and Glucose Targets with the settings from '\(preset.name)'.\(extraSettings) Are you sure?",
                        comment: "ProfilePresets: confirmation message for activating a preset"
                    )
                }
            }
            .alert(
                Text(
                    "Cannot Save Preset",
                    comment: "ProfilePresets: alert title when saving fails due to incomplete settings"
                ),
                isPresented: $state.showingSaveError
            ) {
                Button(String(localized: "OK", comment: "ProfilePresets: dismiss button")) {}
            } message: {
                Text(
                    "Your current therapy settings are incomplete. Please ensure Basal Rates, ISF, CR, and Glucose Targets are all configured before saving a preset.",
                    comment: "ProfilePresets: error message when settings are incomplete"
                )
            }
            .alert(
                Text(
                    "Cannot Activate Preset",
                    comment: "ProfilePresets: alert title when activating fails due to invalid preset"
                ),
                isPresented: $state.showingActivateError
            ) {
                Button(String(localized: "OK", comment: "ProfilePresets: dismiss button")) {}
            } message: {
                Text(
                    "This preset contains incomplete therapy settings and cannot be activated.",
                    comment: "ProfilePresets: error message when preset is invalid"
                )
            }
            .sheet(isPresented: $state.showingAdjustmentSheet) {
                adjustmentSheet
            }
        }

        // MARK: - Preset Row

        @ViewBuilder private func presetRow(_ preset: ProfilePreset) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(preset.name)
                        .font(.headline)
                    Spacer()
                    Button {
                        state.selectedPreset = preset
                        state.showingActivateConfirmation = true
                    } label: {
                        Text("Activate", comment: "ProfilePresets: button to activate a preset")
                            .font(.subheadline.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }

                presetDetails(preset)

                HStack(spacing: 12) {
                    // Detail button
                    NavigationLink {
                        PresetDetailView(
                            preset: preset,
                            units: state.units,
                            formattedBasalTotal: state.formattedBasalTotal(preset)
                        )
                    } label: {
                        Label {
                            Text(
                                "View Details",
                                comment: "ProfilePresets: button to view full preset details"
                            )
                        } icon: {
                            Image(systemName: "list.bullet")
                        }
                        .font(.caption)
                        .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)

                    // Compare with current
                    if let currentProfile = state.currentProfile {
                        NavigationLink {
                            ComparisonView(
                                presetA: preset,
                                presetB: currentProfile,
                                units: state.units
                            )
                        } label: {
                            Label {
                                Text(
                                    "Compare with Current",
                                    comment: "ProfilePresets: button to compare preset with current profile"
                                )
                            } icon: {
                                Image(systemName: "arrow.left.arrow.right")
                            }
                            .font(.caption)
                            .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                    }

                    // Adjust button
                    Button {
                        state.beginAdjustment(for: preset)
                    } label: {
                        Label {
                            Text(
                                "Create Adjusted Copy",
                                comment: "ProfilePresets: button to create a percentage-adjusted copy of a preset"
                            )
                        } icon: {
                            Image(systemName: "plusminus")
                        }
                        .font(.caption)
                        .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }

        // MARK: - Preset Details

        @ViewBuilder private func presetDetails(_ preset: ProfilePreset) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 16) {
                    Label {
                        Text(
                            "Basal: \(state.formattedBasalTotal(preset)) U/day",
                            comment: "ProfilePresets: total daily basal for a preset"
                        )
                    } icon: {
                        Image(systemName: "drop.fill")
                            .foregroundColor(.insulin)
                    }
                    .font(.caption)
                }

                HStack(spacing: 16) {
                    Label {
                        Text(
                            "ISF: \(preset.insulinSensitivities.sensitivities.count) entries",
                            comment: "ProfilePresets: number of ISF schedule entries"
                        )
                    } icon: {
                        Image(systemName: "arrow.up.arrow.down")
                            .foregroundColor(.loopYellow)
                    }
                    .font(.caption)

                    Label {
                        Text(
                            "CR: \(preset.carbRatios.schedule.count) entries",
                            comment: "ProfilePresets: number of CR schedule entries"
                        )
                    } icon: {
                        Image(systemName: "fork.knife")
                            .foregroundColor(.loopGreen)
                    }
                    .font(.caption)
                }

                // Extra settings badges
                HStack(spacing: 8) {
                    if preset.smbSettings != nil {
                        Label {
                            Text("SMB", comment: "ProfilePresets: badge indicating SMB settings are included")
                        } icon: {
                            Image(systemName: "bolt.fill")
                        }
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.2))
                        .foregroundColor(.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }

                    if preset.dynamicSettings != nil {
                        Label {
                            Text(
                                "Dynamic ISF",
                                comment: "ProfilePresets: badge indicating Dynamic ISF settings are included"
                            )
                        } icon: {
                            Image(systemName: "waveform.path")
                        }
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.2))
                        .foregroundColor(.purple)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
            .foregroundColor(.secondary)
        }

        // MARK: - Adjustment Sheet

        private var adjustmentSheet: some View {
            NavigationView {
                Form {
                    if let source = state.adjustmentSourcePreset {
                        Section(
                            header: Text(
                                "Percentage Adjustment",
                                comment: "ProfilePresets: section header for percentage adjustment"
                            )
                        ) {
                            Stepper(
                                value: $state.adjustmentPercentage,
                                in: 50 ... 150,
                                step: 5
                            ) {
                                Text(
                                    "\(state.adjustmentPercentage)%",
                                    comment: "ProfilePresets: percentage adjustment value"
                                )
                                .font(.title2.bold())
                                .monospacedDigit()
                            }

                            Text(
                                adjustmentDescription,
                                comment: "ProfilePresets: description of the percentage adjustment effect"
                            )
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        }

                        Section(
                            header: Text(
                                "New Preset Name",
                                comment: "ProfilePresets: section header for adjusted preset name"
                            )
                        ) {
                            TextField(
                                String(
                                    localized: "Preset Name",
                                    comment: "ProfilePresets: placeholder for adjusted preset name"
                                ),
                                text: $state.adjustmentPresetName
                            )
                        }

                        Section(
                            header: Text(
                                "Preview",
                                comment: "ProfilePresets: section header for adjusted values preview"
                            )
                        ) {
                            adjustmentPreview(source: source)
                        }
                    }
                }
                .navigationTitle(
                    Text(
                        "Create Adjusted Profile",
                        comment: "ProfilePresets: navigation title for adjustment sheet"
                    )
                )
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "Cancel", comment: "ProfilePresets: cancel button")) {
                            state.showingAdjustmentSheet = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "Save", comment: "ProfilePresets: save button")) {
                            state.createAdjustedPreset()
                            state.showingAdjustmentSheet = false
                        }
                        .disabled(state.adjustmentPresetName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }

        private var adjustmentDescription: String {
            let pct = state.adjustmentPercentage
            if pct > 100 {
                return String(
                    localized: "Increases basal rates by \(pct - 100)% and makes ISF/CR more aggressive (lower values).",
                    comment: "ProfilePresets: description when percentage is above 100"
                )
            } else if pct < 100 {
                return String(
                    localized: "Decreases basal rates by \(100 - pct)% and makes ISF/CR less aggressive (higher values).",
                    comment: "ProfilePresets: description when percentage is below 100"
                )
            } else {
                return String(
                    localized: "Creates an exact copy of the original preset.",
                    comment: "ProfilePresets: description when percentage is 100"
                )
            }
        }

        @ViewBuilder private func adjustmentPreview(source: ProfilePreset) -> some View {
            let adjusted = source.scaled(by: state.adjustmentPercentage, name: "")

            VStack(alignment: .leading, spacing: 6) {
                previewRow(
                    label: String(localized: "Basal Total", comment: "ProfilePresets: basal total label in preview"),
                    original: "\(state.formattedBasalTotal(source)) U/day",
                    adjusted: "\(state.formattedBasalTotal(adjusted)) U/day"
                )

                if let firstISFOriginal = source.insulinSensitivities.sensitivities.first,
                   let firstISFAdjusted = adjusted.insulinSensitivities.sensitivities.first
                {
                    previewRow(
                        label: String(
                            localized: "ISF (first entry)",
                            comment: "ProfilePresets: ISF first entry label in preview"
                        ),
                        original: formatDecimal(firstISFOriginal.sensitivity),
                        adjusted: formatDecimal(firstISFAdjusted.sensitivity)
                    )
                }

                if let firstCROriginal = source.carbRatios.schedule.first,
                   let firstCRAdjusted = adjusted.carbRatios.schedule.first
                {
                    previewRow(
                        label: String(
                            localized: "CR (first entry)",
                            comment: "ProfilePresets: CR first entry label in preview"
                        ),
                        original: formatDecimal(firstCROriginal.ratio),
                        adjusted: formatDecimal(firstCRAdjusted.ratio)
                    )
                }
            }
        }

        @ViewBuilder private func previewRow(label: String, original: String, adjusted: String) -> some View {
            HStack {
                Text(label)
                    .font(.caption)
                Spacer()
                Text(original)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(adjusted)
                    .font(.caption.bold())
                    .foregroundColor(original == adjusted ? .primary : .accentColor)
            }
        }

        // MARK: - Save Preset Sheet

        private var savePresetSheet: some View {
            NavigationView {
                Form {
                    Section(
                        header: Text(
                            "Preset Name",
                            comment: "ProfilePresets: section header for preset name input"
                        )
                    ) {
                        TextField(
                            String(
                                localized: "Enter a name",
                                comment: "ProfilePresets: placeholder for preset name input"
                            ),
                            text: $state.newPresetName
                        )
                    }

                    saveOptionsSection

                    if let preview = state.savePreviewProfile {
                        Section(
                            header: Text(
                                "Settings Summary",
                                comment: "ProfilePresets: section header for settings summary in save sheet"
                            )
                        ) {
                            HStack {
                                Label {
                                    Text(
                                        "Total Daily Basal",
                                        comment: "ProfilePresets: total daily basal label in save summary"
                                    )
                                } icon: {
                                    Image(systemName: "drop.fill")
                                        .foregroundColor(.insulin)
                                }
                                .font(.subheadline)
                                Spacer()
                                Text("\(state.formattedBasalTotal(preview)) U/day")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundColor(.secondary)
                            }

                            ForEach(Array(preview.basalProfile.enumerated()), id: \.offset) { _, entry in
                                HStack {
                                    Text(entry.start)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("\(formatRate(entry.rate)) U/hr")
                                        .font(.caption.monospacedDigit())
                                        .foregroundColor(.secondary)
                                }
                            }

                            HStack {
                                Label {
                                    Text("ISF", comment: "ProfilePresets: ISF label in save summary")
                                } icon: {
                                    Image(systemName: "arrow.up.arrow.down")
                                        .foregroundColor(.loopYellow)
                                }
                                .font(.subheadline)
                                Spacer()
                                if let first = preview.insulinSensitivities.sensitivities.first {
                                    Text(
                                        "\(state.formatGlucose(first.sensitivity)) \(state.units.rawValue) (\(preview.insulinSensitivities.sensitivities.count) entries)"
                                    )
                                    .font(.caption.monospacedDigit())
                                    .foregroundColor(.secondary)
                                }
                            }

                            HStack {
                                Label {
                                    Text("CR", comment: "ProfilePresets: CR label in save summary")
                                } icon: {
                                    Image(systemName: "fork.knife")
                                        .foregroundColor(.loopGreen)
                                }
                                .font(.subheadline)
                                Spacer()
                                if let first = preview.carbRatios.schedule.first {
                                    Text(
                                        "\(formatDecimal(first.ratio)) g/U (\(preview.carbRatios.schedule.count) entries)"
                                    )
                                    .font(.caption.monospacedDigit())
                                    .foregroundColor(.secondary)
                                }
                            }

                            HStack {
                                Label {
                                    Text(
                                        "Targets",
                                        comment: "ProfilePresets: glucose targets label in save summary"
                                    )
                                } icon: {
                                    Image(systemName: "target")
                                        .foregroundColor(.loopGreen)
                                }
                                .font(.subheadline)
                                Spacer()
                                if let first = preview.bgTargets.targets.first {
                                    Text(
                                        "\(state.formatGlucose(first.low))–\(state.formatGlucose(first.high)) \(state.units.rawValue)"
                                    )
                                    .font(.caption.monospacedDigit())
                                    .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                .navigationTitle(
                    Text("Save Profile Preset", comment: "ProfilePresets: navigation title for save sheet")
                )
                .navigationBarTitleDisplayMode(.inline)
                .onAppear {
                    state.prepareSavePreview()
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "Cancel", comment: "ProfilePresets: cancel button")) {
                            state.newPresetName = ""
                            state.includeSMBSettings = false
                            state.includeDynamicSettings = false
                            state.showingSaveDialog = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "Save", comment: "ProfilePresets: save button")) {
                            state.saveCurrentProfileAsPreset()
                            state.showingSaveDialog = false
                        }
                        .disabled(state.newPresetName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }

        // MARK: - Save Options Section

        private var saveOptionsSection: some View {
            Section(
                header: Text(
                    "Include Extra Settings",
                    comment: "ProfilePresets: section header for extra settings toggles"
                )
            ) {
                Toggle(isOn: $state.includeSMBSettings) {
                    Label {
                        Text("SMB Settings", comment: "ProfilePresets: toggle label for including SMB settings")
                    } icon: {
                        Image(systemName: "bolt.fill")
                            .foregroundColor(.orange)
                    }
                }

                Toggle(isOn: $state.includeDynamicSettings) {
                    Label {
                        Text(
                            "Dynamic ISF Settings",
                            comment: "ProfilePresets: toggle label for including Dynamic ISF settings"
                        )
                    } icon: {
                        Image(systemName: "waveform.path")
                            .foregroundColor(.purple)
                    }
                }
            }
        }

        // MARK: - Helpers

        @ViewBuilder private var comparePresetsRow: some View {
            HStack {
                Picker(
                    String(localized: "First", comment: "ProfilePresets: first preset picker label"),
                    selection: Binding(
                        get: { state.defaultComparisonPresetA },
                        set: { state.comparisonPresetA = $0 }
                    )
                ) {
                    ForEach(state.presets) { preset in
                        Text(preset.name).tag(Optional(preset))
                    }
                }
                .pickerStyle(.menu)
                .font(.subheadline)

                Picker(
                    String(localized: "Second", comment: "ProfilePresets: second preset picker label"),
                    selection: Binding(
                        get: { state.defaultComparisonPresetB },
                        set: { state.comparisonPresetB = $0 }
                    )
                ) {
                    ForEach(state.presets) { preset in
                        Text(preset.name).tag(Optional(preset))
                    }
                    if let currentProfile = state.currentProfile {
                        Text(currentProfile.name).tag(Optional(currentProfile))
                    }
                }
                .pickerStyle(.menu)
                .font(.subheadline)
            }

            if let presetA = state.defaultComparisonPresetA,
               let presetB = state.defaultComparisonPresetB
            {
                NavigationLink {
                    ComparisonView(
                        presetA: presetA,
                        presetB: presetB,
                        units: state.units
                    )
                } label: {
                    Label {
                        Text(
                            "Compare Selected Presets",
                            comment: "ProfilePresets: button to compare two selected presets"
                        )
                    } icon: {
                        Image(systemName: "arrow.left.arrow.right")
                    }
                    .font(.subheadline)
                    .foregroundColor(.accentColor)
                }
            }
        }

        private func deletePresets(at offsets: IndexSet) {
            for index in offsets {
                let preset = state.presets[index]
                state.deletePreset(preset)
            }
        }

        private func activateExtraSettingsDescription(for preset: ProfilePreset) -> String {
            var extras: [String] = []
            if preset.smbSettings != nil {
                extras.append(String(localized: "SMB", comment: "ProfilePresets: SMB settings label"))
            }
            if preset.dynamicSettings != nil {
                extras.append(String(localized: "Dynamic ISF", comment: "ProfilePresets: Dynamic ISF settings label"))
            }
            if extras.isEmpty { return "" }
            return " " + String(
                localized: "This will also apply \(extras.joined(separator: " and ")) settings.",
                comment: "ProfilePresets: extra settings description in activate confirmation"
            )
        }

        private func formatDecimal(_ value: Decimal) -> String {
            String(format: "%.1f", NSDecimalNumber(decimal: value).doubleValue)
        }

        private func formatRate(_ value: Decimal) -> String {
            String(format: "%.2f", NSDecimalNumber(decimal: value).doubleValue)
        }
    }
}
