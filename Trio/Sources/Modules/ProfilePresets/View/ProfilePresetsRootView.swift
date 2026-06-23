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
                        .onMove(perform: state.reorderPresets)
                    }
                    .listRowBackground(Color.chart)
                }

                if state.presets.count >= 2 || (state.presets.count >= 1 && state.currentProfile != nil) {
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
                                "Each preset stores: Basal Rates, Insulin Sensitivities (ISF), Carb Ratios (CR), Glucose Targets, SMB, and Dynamic ISF settings.",
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
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
            .divergenceSavePrompt(
                coordinator: state.presetSwitchCoordinator,
                activePresetName: state.activePreset?.name
            )
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
            .alert(
                Text("Rename Preset", comment: "ProfilePresets: alert title for renaming a preset"),
                isPresented: $state.showingRenameDialog
            ) {
                TextField(
                    String(localized: "Preset Name", comment: "ProfilePresets: rename text field placeholder"),
                    text: $state.renameNewName
                )
                Button(String(localized: "Rename", comment: "ProfilePresets: rename confirm button")) {
                    state.confirmRename()
                }
                Button(String(localized: "Cancel", comment: "ProfilePresets: cancel button"), role: .cancel) {
                    state.presetToRename = nil
                    state.renameNewName = ""
                }
            } message: {
                Text(
                    "Enter a new name for this preset.",
                    comment: "ProfilePresets: rename alert message"
                )
            }
            .sheet(isPresented: $state.showingComparisonSheet) {
                if let presetA = state.comparisonPresetA,
                   let presetB = state.comparisonPresetB
                {
                    NavigationView {
                        ComparisonView(
                            presetA: presetA,
                            presetB: presetB,
                            units: state.units
                        )
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button(String(localized: "Done", comment: "ProfilePresets: dismiss comparison")) {
                                    state.showingComparisonSheet = false
                                }
                            }
                        }
                    }
                }
            }
        }

        // MARK: - Preset Row

        @ViewBuilder private func presetRow(_ preset: ProfilePreset) -> some View {
            let isActive = preset.id == state.activePreset?.id

            NavigationLink {
                PresetDetailView(
                    preset: preset,
                    units: state.units,
                    formattedBasalTotal: state.formattedBasalTotal(preset)
                )
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: preset.icon)
                            .foregroundColor(.accentColor)
                            .font(.headline)
                        Text(preset.name)
                            .font(.headline)
                        if isActive, state.isProfileDiverged {
                            Text(
                                "modified",
                                comment: "ProfilePresets: label indicating active preset has been modified"
                            )
                            .font(.caption2)
                            .foregroundColor(.orange)
                        }
                        Spacer()
                        if isActive {
                            if state.isProfileDiverged {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }

                    presetSummaryPills(preset)
                }
                .padding(.vertical, 4)
            }
            .contextMenu {
                if preset.id != state.activePreset?.id {
                    Button {
                        state.requestPresetSwitch(preset)
                    } label: {
                        Label(
                            String(
                                localized: "Activate",
                                comment: "ProfilePresets: context menu option to activate preset"
                            ),
                            systemImage: "checkmark.circle"
                        )
                    }
                }

                if state.currentProfile != nil {
                    Button {
                        state.beginComparison(presetA: preset, presetB: state.currentProfile)
                    } label: {
                        Label(
                            String(
                                localized: "Compare with Current",
                                comment: "ProfilePresets: context menu option to compare preset with current profile"
                            ),
                            systemImage: "arrow.left.arrow.right"
                        )
                    }
                }

                Button {
                    state.beginAdjustment(for: preset)
                } label: {
                    Label(
                        String(
                            localized: "Create Adjusted Copy",
                            comment: "ProfilePresets: context menu option to create a percentage-adjusted copy"
                        ),
                        systemImage: "plusminus"
                    )
                }

                Button {
                    state.beginRename(for: preset)
                } label: {
                    Label(
                        String(
                            localized: "Rename",
                            comment: "ProfilePresets: context menu option to rename preset"
                        ),
                        systemImage: "pencil"
                    )
                }

                if preset.id == state.activePreset?.id, state.isProfileDiverged {
                    Button {
                        state.updatePresetToCurrentSettings(preset)
                    } label: {
                        Label(
                            String(
                                localized: "Update to Current Settings",
                                comment: "ProfilePresets: context menu option to update preset with current therapy settings"
                            ),
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                    }
                }

                Divider()

                Button(role: .destructive) {
                    state.deletePreset(preset)
                } label: {
                    Label(
                        String(
                            localized: "Delete",
                            comment: "ProfilePresets: context menu option to delete preset"
                        ),
                        systemImage: "trash"
                    )
                }
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                if preset.id != state.activePreset?.id {
                    Button {
                        state.requestPresetSwitch(preset)
                    } label: {
                        Label(
                            String(
                                localized: "Activate",
                                comment: "ProfilePresets: swipe action to activate preset"
                            ),
                            systemImage: "checkmark.circle"
                        )
                    }
                    .tint(.accentColor)
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    state.deletePreset(preset)
                } label: {
                    Label(
                        String(
                            localized: "Delete",
                            comment: "ProfilePresets: swipe action to delete preset"
                        ),
                        systemImage: "trash"
                    )
                }
            }
        }

        // MARK: - Preset Summary Pills

        @ViewBuilder private func presetSummaryPills(_ preset: ProfilePreset) -> some View {
            HStack(spacing: 6) {
                summaryPill(
                    text: "\(state.formattedBasalTotal(preset)) U",
                    icon: "drop.fill",
                    color: .insulin
                )

                if let first = preset.insulinSensitivities.sensitivities.first {
                    summaryPill(
                        text: "ISF \(state.formatGlucose(first.sensitivity))",
                        icon: "arrow.up.arrow.down",
                        color: .loopYellow
                    )
                }

                if let first = preset.carbRatios.schedule.first {
                    summaryPill(
                        text: "CR \(formatDecimal(first.ratio))",
                        icon: "fork.knife",
                        color: .loopGreen
                    )
                }

                if preset.smbSettings != nil {
                    summaryPill(
                        text: String(localized: "SMB", comment: "ProfilePresets: SMB pill label"),
                        icon: "bolt.fill",
                        color: .orange
                    )
                }

                if preset.dynamicSettings != nil {
                    summaryPill(
                        text: String(localized: "dynISF", comment: "ProfilePresets: Dynamic ISF pill label"),
                        icon: "waveform.path",
                        color: .purple
                    )
                }
            }
        }

        private func summaryPill(text: String, icon: String, color: Color) -> some View {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 8))
                Text(text)
                    .font(.caption2)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .clipShape(Capsule())
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

                            Text(adjustmentDescription)
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
                        Button(
                            String(
                                localized: "Confirm & Save",
                                comment: "ProfilePresets: confirm and save adjusted preset button"
                            )
                        ) {
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
            if let adjusted = source.scaled(by: state.adjustmentPercentage, name: "") {
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
                            original: "\(state.formatGlucose(firstISFOriginal.sensitivity)) \(state.units.rawValue)",
                            adjusted: "\(state.formatGlucose(firstISFAdjusted.sensitivity)) \(state.units.rawValue)"
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

        private enum SaveStep: Int, CaseIterable {
            case setup = 0
            case basal
            case isf
            case cr
            case targets
            case smbDyn
            case summary

            var title: String {
                switch self {
                case .setup:
                    return String(localized: "Setup", comment: "ProfilePresets: save step for name/icon/options")
                case .basal:
                    return String(localized: "Basal", comment: "ProfilePresets: save step for basal rates")
                case .isf:
                    return String(localized: "ISF", comment: "ProfilePresets: save step for ISF")
                case .cr:
                    return String(localized: "CR", comment: "ProfilePresets: save step for carb ratios")
                case .targets:
                    return String(localized: "Targets", comment: "ProfilePresets: save step for glucose targets")
                case .smbDyn:
                    return String(localized: "SMB / dynISF", comment: "ProfilePresets: save step for SMB and dynamic ISF settings")
                case .summary:
                    return String(localized: "Summary", comment: "ProfilePresets: save step for final summary")
                }
            }
        }

        @State private var currentSaveStep: SaveStep = .setup

        private var savePresetSheet: some View {
            NavigationView {
                VStack(spacing: 0) {
                    // Progress indicator
                    saveStepProgressBar

                    // Step title
                    Text(currentSaveStep.title)
                        .font(.headline)
                        .padding(.top, 8)
                        .padding(.bottom, 4)

                    Divider()

                    // Step content
                    Group {
                        switch currentSaveStep {
                        case .setup:
                            saveSetupTab
                        case .basal:
                            saveBasalTab
                        case .isf:
                            saveISFTab
                        case .cr:
                            saveCRTab
                        case .targets:
                            saveTargetsTab
                        case .smbDyn:
                            saveSMBDynTab
                        case .summary:
                            saveSummaryTab
                        }
                    }

                    Divider()

                    // Navigation buttons
                    saveNavigationButtons
                }
                .navigationTitle(
                    Text("Save Profile Preset", comment: "ProfilePresets: navigation title for save sheet")
                )
                .navigationBarTitleDisplayMode(.inline)
                .onAppear {
                    state.prepareSavePreview()
                    currentSaveStep = .setup
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "Cancel", comment: "ProfilePresets: cancel button")) {
                            state.newPresetName = ""
                            state.newPresetIcon = ProfilePreset.defaultIcon
                            state.showingSaveDialog = false
                        }
                    }
                }
            }
        }

        private var saveStepProgressBar: some View {
            let allSteps = SaveStep.allCases
            let currentIndex = allSteps.firstIndex(of: currentSaveStep) ?? 0
            let progress = Double(currentIndex) / Double(allSteps.count - 1)

            return VStack(spacing: 4) {
                // Step dots
                HStack(spacing: 0) {
                    ForEach(Array(allSteps.enumerated()), id: \.offset) { index, _ in
                        Circle()
                            .fill(index <= currentIndex ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                        if index < allSteps.count - 1 {
                            Spacer()
                        }
                    }
                }
                .padding(.horizontal, 24)

                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.accentColor)
                            .frame(width: geometry.size.width * progress, height: 4)
                            .animation(.easeInOut(duration: 0.3), value: progress)
                    }
                }
                .frame(height: 4)
                .padding(.horizontal, 24)

                // Step counter
                Text(verbatim: "\(currentIndex + 1) / \(allSteps.count)")
                .font(.caption2)
                .foregroundColor(.secondary)
            }
            .padding(.top, 12)
        }

        private var saveNavigationButtons: some View {
            let allSteps = SaveStep.allCases
            let currentIndex = allSteps.firstIndex(of: currentSaveStep) ?? 0

            return HStack {
                // Back button
                if currentSaveStep != .setup {
                    Button {
                        withAnimation {
                            if currentIndex > 0 {
                                currentSaveStep = allSteps[currentIndex - 1]
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back", comment: "ProfilePresets: back button")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .foregroundColor(.primary)
                    }
                    .accessibilityLabel(
                        Text(
                            "Back to \(currentIndex > 0 ? allSteps[currentIndex - 1].title : "")",
                            comment: "ProfilePresets: accessibility label for back button"
                        )
                    )
                }

                Spacer()

                // Next / Confirm & Save button
                if currentSaveStep == .summary {
                    Button {
                        state.saveCurrentProfileAsPreset()
                        state.showingSaveDialog = false
                    } label: {
                        HStack(spacing: 4) {
                            Text("Confirm & Save", comment: "ProfilePresets: confirm save button")
                            Image(systemName: "checkmark")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .foregroundColor(.white)
                        .background(Capsule().fill(
                            state.newPresetName.trimmingCharacters(in: .whitespaces).isEmpty
                                ? Color.gray
                                : Color.accentColor
                        ))
                    }
                    .disabled(state.newPresetName.trimmingCharacters(in: .whitespaces).isEmpty)
                } else {
                    Button {
                        withAnimation {
                            if currentIndex + 1 < allSteps.count {
                                currentSaveStep = allSteps[currentIndex + 1]
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("Next", comment: "ProfilePresets: next step button")
                            Image(systemName: "chevron.right")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .foregroundColor(.white)
                        .background(Capsule().fill(Color.accentColor))
                    }
                    .accessibilityLabel(
                        Text(
                            "Next: \(currentIndex + 1 < allSteps.count ? allSteps[currentIndex + 1].title : "")",
                            comment: "ProfilePresets: accessibility label for next button"
                        )
                    )
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }

        // MARK: - Save Sheet Tabs

        private var saveSetupTab: some View {
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

                Section(
                    header: Text(
                        "Preset Icon",
                        comment: "ProfilePresets: section header for preset icon selection"
                    )
                ) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                        ForEach(ProfilePreset.availableIcons, id: \.self) { iconName in
                            Button {
                                state.newPresetIcon = iconName
                            } label: {
                                Image(systemName: iconName)
                                    .font(.title2)
                                    .frame(width: 44, height: 44)
                                    .background(
                                        state.newPresetIcon == iconName
                                            ? Color.accentColor.opacity(0.2)
                                            : Color.clear
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(
                                                state.newPresetIcon == iconName
                                                    ? Color.accentColor
                                                    : Color.clear,
                                                lineWidth: 2
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }

        private var saveBasalTab: some View {
            List {
                if let preview = state.savePreviewProfile {
                    Section(
                        header: Text("Basal Rates", comment: "ProfilePresets: basal rates tab header")
                    ) {
                        BasalChartView(basalProfile: preview.basalProfile)
                            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))

                        HStack {
                            Text("Total Daily Basal", comment: "ProfilePresets: total daily basal label")
                                .font(.subheadline.bold())
                            Spacer()
                            Text("\(state.formattedBasalTotal(preview)) U/day")
                                .font(.subheadline.bold())
                                .foregroundColor(.insulin)
                        }

                        ForEach(Array(preview.basalProfile.enumerated()), id: \.offset) { _, entry in
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
                } else {
                    Text("Loading…", comment: "ProfilePresets: loading placeholder")
                        .foregroundColor(.secondary)
                }
            }
        }

        private var saveISFTab: some View {
            List {
                if let preview = state.savePreviewProfile {
                    Section(
                        header: Text(
                            "Insulin Sensitivities (ISF)",
                            comment: "ProfilePresets: ISF tab header"
                        )
                    ) {
                        ISFChartView(sensitivities: preview.insulinSensitivities.sensitivities, units: state.units)
                            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))

                        ForEach(
                            Array(preview.insulinSensitivities.sensitivities.enumerated()),
                            id: \.offset
                        ) { _, entry in
                            HStack {
                                Text(entry.start)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(state.formatGlucose(entry.sensitivity)) \(state.units.rawValue)")
                                    .font(.subheadline.monospacedDigit())
                            }
                        }
                    }
                } else {
                    Text("Loading…", comment: "ProfilePresets: loading placeholder")
                        .foregroundColor(.secondary)
                }
            }
        }

        private var saveCRTab: some View {
            List {
                if let preview = state.savePreviewProfile {
                    Section(
                        header: Text("Carb Ratios (CR)", comment: "ProfilePresets: CR tab header")
                    ) {
                        CRChartView(schedule: preview.carbRatios.schedule)
                            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))

                        ForEach(Array(preview.carbRatios.schedule.enumerated()), id: \.offset) { _, entry in
                            HStack {
                                Text(entry.start)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("\(formatDecimal(entry.ratio)) g/U")
                                    .font(.subheadline.monospacedDigit())
                            }
                        }
                    }
                } else {
                    Text("Loading…", comment: "ProfilePresets: loading placeholder")
                        .foregroundColor(.secondary)
                }
            }
        }

        private var saveTargetsTab: some View {
            List {
                if let preview = state.savePreviewProfile {
                    Section(
                        header: Text("Glucose Targets", comment: "ProfilePresets: targets tab header")
                    ) {
                        TargetsChartView(targets: preview.bgTargets.targets, units: state.units)
                            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))

                        ForEach(Array(preview.bgTargets.targets.enumerated()), id: \.offset) { _, entry in
                            HStack {
                                Text(entry.start)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(
                                    "\(state.formatGlucose(entry.low)) – \(state.formatGlucose(entry.high)) \(state.units.rawValue)"
                                )
                                .font(.subheadline.monospacedDigit())
                            }
                        }
                    }
                } else {
                    Text("Loading…", comment: "ProfilePresets: loading placeholder")
                        .foregroundColor(.secondary)
                }
            }
        }

        private var saveSMBDynTab: some View {
            List {
                if let preview = state.savePreviewProfile {
                    if let smb = preview.smbSettings {
                        Section(
                            header: Text("SMB Settings", comment: "ProfilePresets: SMB settings tab header")
                        ) {
                            settingRow(
                                label: String(localized: "Enable SMB Always", comment: "ProfilePresets: SMB setting"),
                                value: smb.enableSMBAlways ? "✓" : "✗"
                            )
                            settingRow(
                                label: String(localized: "Enable SMB with COB", comment: "ProfilePresets: SMB setting"),
                                value: smb.enableSMBWithCOB ? "✓" : "✗"
                            )
                            settingRow(
                                label: String(localized: "Enable SMB with Temp Target", comment: "ProfilePresets: SMB setting"),
                                value: smb.enableSMBWithTemptarget ? "✓" : "✗"
                            )
                            settingRow(
                                label: String(localized: "Enable SMB After Carbs", comment: "ProfilePresets: SMB setting"),
                                value: smb.enableSMBAfterCarbs ? "✓" : "✗"
                            )
                            settingRow(
                                label: String(localized: "Enable UAM", comment: "ProfilePresets: SMB setting"),
                                value: smb.enableUAM ? "✓" : "✗"
                            )
                            settingRow(
                                label: String(localized: "Enable SMB High BG", comment: "ProfilePresets: SMB setting"),
                                value: smb.enableSMBHighBG ? "✓" : "✗"
                            )
                            if smb.enableSMBHighBG {
                                settingRow(
                                    label: String(localized: "SMB High BG Target", comment: "ProfilePresets: SMB setting"),
                                    value: "\(state.formatGlucose(smb.enableSMBHighBGTarget)) \(state.units.rawValue)"
                                )
                            }
                            settingRow(
                                label: String(localized: "Max SMB Basal Minutes", comment: "ProfilePresets: SMB setting"),
                                value: "\(formatDecimal(smb.maxSMBBasalMinutes, decimals: 0)) min"
                            )
                            settingRow(
                                label: String(localized: "Max UAM SMB Basal Minutes", comment: "ProfilePresets: SMB setting"),
                                value: "\(formatDecimal(smb.maxUAMSMBBasalMinutes, decimals: 0)) min"
                            )
                            settingRow(
                                label: String(localized: "Max Delta BG Threshold", comment: "ProfilePresets: SMB setting"),
                                value: formatDecimal(smb.maxDeltaBGthreshold, decimals: 2)
                            )
                        }
                    }

                    if let dynamic = preview.dynamicSettings {
                        Section(
                            header: Text("dynISF Settings", comment: "ProfilePresets: dynamic ISF settings tab header")
                        ) {
                            settingRow(
                                label: String(localized: "Type", comment: "ProfilePresets: Dynamic ISF type label"),
                                value: state.dynamicISFType(for: dynamic)
                            )
                            settingRow(
                                label: String(
                                    localized: "Adjustment Factor",
                                    comment: "ProfilePresets: Dynamic ISF setting"
                                ),
                                value: formatDecimal(dynamic.adjustmentFactor, decimals: 2)
                            )
                            settingRow(
                                label: String(
                                    localized: "Adjustment Factor (Sigmoid)",
                                    comment: "ProfilePresets: Dynamic ISF setting"
                                ),
                                value: formatDecimal(dynamic.adjustmentFactorSigmoid, decimals: 2)
                            )
                            settingRow(
                                label: String(
                                    localized: "Weight Percentage",
                                    comment: "ProfilePresets: Dynamic ISF setting"
                                ),
                                value: formatDecimal(dynamic.weightPercentage, decimals: 2)
                            )
                            settingRow(
                                label: String(
                                    localized: "TDD Adjusted Basal",
                                    comment: "ProfilePresets: Dynamic ISF setting"
                                ),
                                value: dynamic.tddAdjBasal ? "✓" : "✗"
                            )
                        }
                    }
                } else {
                    Text("Loading…", comment: "ProfilePresets: loading placeholder")
                        .foregroundColor(.secondary)
                }
            }
        }

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

        private var saveSummaryTab: some View {
            Form {
                if state.newPresetName.trimmingCharacters(in: .whitespaces).isEmpty {
                    Section {
                        Label {
                            Text(
                                "Please enter a preset name on the Setup tab before saving.",
                                comment: "ProfilePresets: warning when name is empty on summary"
                            )
                        } icon: {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundColor(.orange)
                        }
                        .font(.subheadline)
                    }
                }

                Section(
                    header: Text("Preset Info", comment: "ProfilePresets: summary section header for preset info")
                ) {
                    HStack {
                        Image(systemName: state.newPresetIcon)
                            .font(.title2)
                            .foregroundColor(.accentColor)
                        Text(
                            state.newPresetName.isEmpty
                                ? String(localized: "(No name)", comment: "ProfilePresets: placeholder when no name entered")
                                : state.newPresetName
                        )
                        .font(.headline)
                    }
                }

                if let preview = state.savePreviewProfile {
                    Section(
                        header: Text(
                            "Settings to Save",
                            comment: "ProfilePresets: summary section header for settings"
                        )
                    ) {
                        HStack {
                            Label {
                                Text(
                                    "Total Daily Basal",
                                    comment: "ProfilePresets: total daily basal label in summary"
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

                        HStack {
                            Label {
                                Text("ISF", comment: "ProfilePresets: ISF label in summary")
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
                                Text("CR", comment: "ProfilePresets: CR label in summary")
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
                                    comment: "ProfilePresets: glucose targets label in summary"
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

                        HStack {
                            Label {
                                Text("SMB Settings", comment: "ProfilePresets: SMB label in summary")
                            } icon: {
                                Image(systemName: "bolt.fill")
                                    .foregroundColor(.orange)
                            }
                            .font(.subheadline)
                            Spacer()
                            Text("Included", comment: "ProfilePresets: included label")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Label {
                                Text("Dynamic ISF", comment: "ProfilePresets: Dynamic ISF label in summary")
                            } icon: {
                                Image(systemName: "waveform.path")
                                    .foregroundColor(.purple)
                            }
                            .font(.subheadline)
                            Spacer()
                            Text("Included", comment: "ProfilePresets: included label")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section {
                    Label {
                        Text(
                            "Tap 'Confirm & Save' to save this preset. You can activate it later from the preset list or the Adjustments tab.",
                            comment: "ProfilePresets: save confirmation info text"
                        )
                    } icon: {
                        Image(systemName: "info.circle")
                            .foregroundColor(.accentColor)
                    }
                    .font(.footnote)
                }
            }
        }

        // MARK: - Save Options Section

        // MARK: - Helpers

        @ViewBuilder private var comparePresetsRow: some View {
            let comparisonOptions = state.presets + (state.currentProfile.map { [$0] } ?? [])

            Picker(
                String(localized: "First", comment: "ProfilePresets: first preset picker label"),
                selection: Binding(
                    get: { state.defaultComparisonPresetA },
                    set: { state.comparisonPresetA = $0 }
                )
            ) {
                ForEach(comparisonOptions) { preset in
                    Text(preset.name).tag(Optional(preset))
                }
            }
            .font(.subheadline)

            Picker(
                String(localized: "Second", comment: "ProfilePresets: second preset picker label"),
                selection: Binding(
                    get: { state.defaultComparisonPresetB },
                    set: { state.comparisonPresetB = $0 }
                )
            ) {
                ForEach(comparisonOptions) { preset in
                    Text(preset.name).tag(Optional(preset))
                }
            }
            .font(.subheadline)

            if let presetA = state.defaultComparisonPresetA,
               let presetB = state.defaultComparisonPresetB,
               presetA.id != presetB.id
            {
                Button {
                    state.beginComparison(presetA: presetA, presetB: presetB)
                } label: {
                    Label {
                        Text(
                            "Compare",
                            comment: "ProfilePresets: button to compare two selected presets"
                        )
                    } icon: {
                        Image(systemName: "arrow.left.arrow.right")
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
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

        private func formatDecimal(_ value: Decimal, decimals: Int) -> String {
            String(format: "%.\(decimals)f", NSDecimalNumber(decimal: value).doubleValue)
        }

        private func formatRate(_ value: Decimal) -> String {
            String(format: "%.2f", NSDecimalNumber(decimal: value).doubleValue)
        }
    }
}
