import CoreData
import SwiftUI
import Swinject

extension Adjustments {
    struct RootView: BaseView {
        let resolver: Resolver
        @State var state = StateModel()
        @State var isEditing = false
        @State var showOverrideCreationSheet = false
        @State var showTempTargetCreationSheet = false
        @State var showingDetail = false
        @State var showOverrideCheckmark: Bool = false
        @State var showTempTargetCheckmark: Bool = false
        @State var selectedOverridePresetID: String?
        @State var selectedTempTargetPresetID: String?
        @State var selectedOverride: OverrideStored?
        @State var selectedTempTarget: TempTargetStored?
        @State var overrideToDelete: OverrideStored?
        @State var tempTargetToDelete: TempTargetStored?
        @State var isPromptPresented = false
        @State var isRemoveAlertPresented = false
        @State var removeAlert: Alert?
        @State var isEditingTT = false
        @State var showCancelOverrideConfirmDialog = false
        @State var showCancelTempTargetConfirmDialog = false
        @State var pendingPresetActivation: PendingPresetActivation?
        @State var showProfileCheckmark: Bool = false
        @State var selectedProfilePresetID: String?
        @State var newPresetName: String = ""

        private var shouldDisplayStickyOverrideStopButton: Bool {
            state.isOverrideEnabled && state.activeOverrideName.isNotEmpty
        }

        private var shouldDisplayStickyTempTargetStopButton: Bool {
            state.isTempTargetEnabled && state.activeTempTargetName.isNotEmpty
        }

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        func formattedGlucose(glucose: Decimal) -> String {
            let formattedValue: String
            if state.units == .mgdL {
                formattedValue = Formatter.glucoseFormatter(for: state.units)
                    .string(from: glucose as NSDecimalNumber) ?? "\(glucose)"
            } else {
                formattedValue = glucose.formattedAsMmolL
            }
            return "\(formattedValue) \(state.units.rawValue)"
        }

        var body: some View {
            tempTargetDeleteConfirmation(overrideDeleteConfirmation(mainContent))
        }

        private var mainContent: some View {
            ZStack(alignment: .center, content: {
                VStack {
                    Picker("Adjustment Tabs", selection: $state.selectedTab) {
                        ForEach(Adjustments.Tab.allCases.indexed(), id: \.1) { index, item in
                            Text(item.name).tag(index)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal)

                    List {
                        switch state.selectedTab {
                        case .overrides: overrides()
                        case .tempTargets: tempTargets()
                        case .profiles: profilesTab()
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(appState.trioBackgroundColor(for: colorScheme))
                }
                .listSectionSpacing(10)
                .safeAreaInset(
                    edge: .bottom,
                    spacing: shouldDisplayStickyOverrideStopButton || shouldDisplayStickyTempTargetStopButton ? 30 : 0
                ) {
                    if shouldDisplayStickyOverrideStopButton, state.selectedTab == .overrides {
                        stickyStopOverrideButton
                    } else if shouldDisplayStickyTempTargetStopButton, state.selectedTab == .tempTargets {
                        stickyStopTempTargetButton
                    } else {
                        EmptyView()
                    }
                }
                .scrollContentBackground(.hidden)
                .background(appState.trioBackgroundColor(for: colorScheme))
                .onAppear(perform: configureView)
                .navigationBarTitle("Adjustments")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        switch state.selectedTab {
                        case .overrides:
                            Button(action: {
                                showOverrideCreationSheet = true
                            }, label: {
                                HStack {
                                    Text("Add Override")
                                    Image(systemName: "plus")
                                }
                            })
                        case .tempTargets:
                            Button(action: {
                                showTempTargetCreationSheet = true
                            }, label: {
                                HStack {
                                    Text("Add Temp Target")
                                    Image(systemName: "plus")
                                }
                            })
                        case .profiles:
                            EmptyView()
                        }
                    }
                }
                .sheet(isPresented: $state.showOverrideEditSheet, onDismiss: {
                    Task {
                        await state.resetStateVariables()
                        state.showOverrideEditSheet = false
                    }

                }) {
                    if let override = selectedOverride {
                        EditOverrideForm(overrideToEdit: override, state: state)
                    }
                }
                .sheet(isPresented: $showOverrideCreationSheet, onDismiss: {
                    Task {
                        await state.resetStateVariables()
                        showOverrideCreationSheet = false
                    }
                }) {
                    AddOverrideForm(state: state)
                }
                .sheet(isPresented: $showTempTargetCreationSheet, onDismiss: {
                    Task {
                        await state.resetTempTargetState()
                        showTempTargetCreationSheet = false
                    }
                }) {
                    AddTempTargetForm(state: state)
                }
                .sheet(isPresented: $state.showTempTargetEditSheet, onDismiss: {
                    Task {
                        await state.resetTempTargetState()
                        state.showTempTargetEditSheet = false
                    }

                }) {
                    if let tempTarget = selectedTempTarget {
                        EditTempTargetForm(tempTargetToEdit: tempTarget, state: state)
                    }
                }
                .confirmationDialog("Override to Stop", isPresented: $showCancelOverrideConfirmDialog) {
                    Button("Stop", role: .destructive) {
                        Task {
                            // Save cancelled Override in OverrideRunStored Entity
                            // Cancel ALL active Override
                            await state.disableAllActiveOverrides(createOverrideRunEntry: true)
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Stop the Override \"\(state.currentActiveOverride?.name ?? "")\"?")
                }
                .confirmationDialog("Temp Target to Stop", isPresented: $showCancelTempTargetConfirmDialog) {
                    Button("Stop", role: .destructive) {
                        Task {
                            // Save cancelled Temp Targets in TempTargetRunStored Entity
                            // Cancel ALL active Temp Targets
                            await state.disableAllActiveTempTargets(createTempTargetRunEntry: true)
                            // Update View
                            state.updateLatestTempTargetConfiguration()
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Stop the Temp Target \"\(state.currentActiveTempTarget?.name ?? "")\"?")
                }
                .confirmationDialog(
                    "Activate Preset",
                    isPresented: presetActivationConfirmationBinding
                ) {
                    Button("Activate") {
                        if let activation = pendingPresetActivation {
                            activatePreset(activation)
                        }
                    }

                    Button("Cancel", role: .cancel) {
                        state.shouldDisplayPresetStartConfirmDialog = false
                        pendingPresetActivation = nil
                    }
                } message: {
                    if let activation = pendingPresetActivation {
                        Text(activation.confirmationMessage)
                    }
                }
                .alert(
                    Text("Activate Profile", comment: "Adjustments: profile activation alert title"),
                    isPresented: $state.showingProfileActivateConfirmation
                ) {
                    Button(String(localized: "Activate", comment: "Adjustments: activate button")) {
                        if let preset = state.selectedProfilePreset {
                            state.activateProfilePreset(preset)
                            selectedProfilePresetID = preset.id
                            showProfileCheckmark = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                showProfileCheckmark = false
                            }
                        }
                        state.selectedProfilePreset = nil
                    }
                    Button(String(localized: "Cancel", comment: "Adjustments: cancel button"), role: .cancel) {
                        state.selectedProfilePreset = nil
                    }
                } message: {
                    if let preset = state.selectedProfilePreset {
                        Text(
                            "This will overwrite your current therapy settings with the settings from '\(preset.name)'. Are you sure?",
                            comment: "Adjustments: profile activation confirmation message"
                        )
                    }
                }
                .divergenceSavePrompt(
                    coordinator: state.presetSwitchCoordinator,
                    activePresetName: state.activeProfilePreset?.name
                )
                .alert(
                    Text(
                        "Save as New Preset",
                        comment: "Adjustments: title for save as new preset alert"
                    ),
                    isPresented: $state.showingSaveNewPresetSheet
                ) {
                    TextField(
                        String(
                            localized: "Preset Name",
                            comment: "Adjustments: placeholder for new preset name"
                        ),
                        text: $newPresetName
                    )
                    Button(String(
                        localized: "Save",
                        comment: "Adjustments: save button for new preset"
                    )) {
                        let trimmed = newPresetName.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        state.saveCurrentAsNewPreset(name: trimmed, icon: ProfilePreset.defaultIcon)
                        newPresetName = ""
                    }
                    Button(String(
                        localized: "Cancel",
                        comment: "Adjustments: cancel save new preset"
                    ), role: .cancel) {
                        newPresetName = ""
                    }
                } message: {
                    Text(
                        "Enter a name for the new profile preset.",
                        comment: "Adjustments: message for save as new preset alert"
                    )
                }
            }).background(appState.trioBackgroundColor(for: colorScheme))
        }

        var defaultText: some View {
            switch state.selectedTab {
            case .overrides:
                Section {} header: {
                    Text("Add Preset or Override by tapping 'Add Override +' in the top right-hand corner of the screen.")
                        .textCase(nil)
                        .foregroundStyle(.secondary)
                }
            case .tempTargets:
                Section {} header: {
                    Text(
                        "Add Preset or Temp Target by tapping 'Add Temp Target +' in the top right-hand corner of the screen."
                    )
                    .textCase(nil)
                    .foregroundStyle(.secondary)
                }
            case .profiles:
                Section {} header: {
                    Text(
                        "Manage profile presets in Settings > Profile Presets."
                    )
                    .textCase(nil)
                    .foregroundStyle(.secondary)
                }
            }
        }

        @ViewBuilder var currentActiveAdjustment: some View {
            switch state.selectedTab {
            case .overrides:
                Section {
                    HStack {
                        Text("\(state.activeOverrideName) is running")

                        Spacer()
                        Image(systemName: "square.and.pencil")
                            .foregroundStyle(Color.primary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Task {
                            /// To avoid editing the Preset when a Preset-Override is running we first duplicate the Preset-Override as a non-Preset Override
                            /// The currentActiveOverride variable in the State will update automatically via MOC notification
                            await state.duplicateOverridePresetAndCancelPreviousOverride()

                            /// selectedOverride is used for passing the chosen Override to the EditSheet so we have to set the updated currentActiveOverride to be the selectedOverride
                            selectedOverride = state.currentActiveOverride

                            /// Now we can show the Edit sheet
                            state.showOverrideEditSheet = true
                        }
                    }
                }
                .listRowBackground(Color.purple.opacity(0.8))
            case .tempTargets:
                Section {
                    HStack {
                        Text("\(state.activeTempTargetName) is running")

                        Spacer()
                        Image(systemName: "square.and.pencil")
                            .foregroundStyle(Color.primary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Task {
                            /// To avoid editing the Preset when a Preset-Override is running we first duplicate the Preset-Override as a non-Preset Override
                            /// The currentActiveOverride variable in the State will update automatically via MOC notification
                            await state.duplicateTempTargetPresetAndCancelPreviousTempTarget()

                            /// selectedOverride is used for passing the chosen Override to the EditSheet so we have to set the updated currentActiveOverride to be the selectedOverride
                            selectedTempTarget = state.currentActiveTempTarget

                            /// Now we can show the Edit sheet
                            state.showTempTargetEditSheet = true
                        }
                    }
                }
                .listRowBackground(Color.loopGreen.opacity(0.8))
            case .profiles:
                if let active = state.activeProfilePreset {
                    Section {
                        HStack {
                            Image(systemName: active.icon)
                                .foregroundStyle(Color.primary)
                            if state.isProfileDiverged {
                                Text(
                                    "'\(active.name)' (modified)",
                                    comment: "Adjustments: active profile preset diverged indicator"
                                )
                            } else {
                                Text(
                                    "'\(active.name)' is active",
                                    comment: "Adjustments: active profile preset indicator"
                                )
                            }
                            Spacer()
                            if state.isProfileDiverged {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Color.orange)
                            }
                        }
                    }
                    .listRowBackground(
                        state.isProfileDiverged
                            ? Color.orange.opacity(0.6)
                            : Color.accentColor.opacity(0.8)
                    )
                }
            }
        }

        @ViewBuilder var cancelAdjustmentButton: some View {
            switch state.selectedTab {
            case .overrides:
                Button(action: {
                    showCancelOverrideConfirmDialog = true
                }, label: {
                    Text("Stop Override")

                })
                    .frame(maxWidth: .infinity, alignment: .center)
                    .disabled(!state.isOverrideEnabled)
                    .listRowBackground(!state.isOverrideEnabled ? Color(.systemGray4) : Color(.systemRed))
                    .tint(.white)
            case .tempTargets:
                Button(action: {
                    showCancelTempTargetConfirmDialog = true
                }, label: {
                    Text("Stop Temp Target")

                })
                    .frame(maxWidth: .infinity, alignment: .center)
                    .disabled(!state.isTempTargetEnabled)
                    .listRowBackground(!state.isTempTargetEnabled ? Color(.systemGray4) : Color(.systemRed))
                    .tint(.white)
            case .profiles:
                EmptyView()
            }
        }

        func formattedTimeRemaining(_ timeInterval: TimeInterval) -> String {
            let totalSeconds = Int(timeInterval)
            let hours = totalSeconds / 3600
            let minutes = (totalSeconds % 3600) / 60
            let seconds = totalSeconds % 60

            if hours > 0 {
                return "\(hours)h \(minutes)m \(seconds)s"
            } else if minutes > 0 {
                return "\(minutes)m \(seconds)s"
            } else {
                return "<1m"
            }
        }

        // MARK: - Profiles Tab

        @ViewBuilder func profilesTab() -> some View {
            if state.activeProfilePreset != nil {
                currentActiveAdjustment
            }

            if state.profilePresets.isEmpty {
                Section {} header: {
                    Text(
                        "No profile presets saved. Create presets in Settings > Profile Presets.",
                        comment: "Adjustments: empty profile presets message"
                    )
                    .textCase(nil)
                    .foregroundStyle(.secondary)
                }
            } else {
                Section(
                    header: Text(
                        "Profile Presets",
                        comment: "Adjustments: section header for profile preset list"
                    )
                ) {
                    ForEach(state.profilePresets) { preset in
                        profilePresetView(for: preset)
                    }
                    .onMove(perform: state.reorderProfilePresets)
                }
                .listRowBackground(Color.chart)
                .onAppear {
                    state.refreshProfileDivergence()
                }
            }
        }

        @ViewBuilder private func profilePresetView(for preset: ProfilePreset) -> some View {
            let isSelected = preset.id == selectedProfilePresetID
            let isActive = preset.id == state.activeProfilePreset?.id

            ZStack(alignment: .trailing) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: preset.icon)
                                .foregroundColor(.accentColor)
                                .font(.title3)
                            Text(preset.name)
                                .font(.subheadline)
                            if isActive, state.isProfileDiverged {
                                Text(
                                    "modified",
                                    comment: "Adjustments: label indicating active preset has been modified"
                                )
                                .font(.caption2)
                                .foregroundColor(.orange)
                            }
                            Spacer()
                        }
                        adjustmentPresetPills(preset)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !isActive else { return }
                        state.requestProfilePresetSwitch(preset)
                    }
                }

                if showProfileCheckmark, isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .imageScale(.large)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.green)
                } else if isActive {
                    if state.isProfileDiverged {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.accentColor)
                    }
                }
            }
            .contextMenu {
                if isActive, state.isProfileDiverged {
                    Button {
                        state.updateProfilePresetToCurrentSettings(preset)
                    } label: {
                        Label(
                            String(
                                localized: "Update to Current Settings",
                                comment: "Adjustments: context menu option to update preset with current therapy settings"
                            ),
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                    }
                }
            }
        }

        @ViewBuilder private func adjustmentPresetPills(_ preset: ProfilePreset) -> some View {
            HStack(spacing: 4) {
                if preset.smbSettings != nil {
                    adjustmentPill(
                        text: String(localized: "SMB", comment: "Adjustments: SMB pill"),
                        color: .orange
                    )
                }
                if preset.dynamicSettings != nil {
                    adjustmentPill(
                        text: String(localized: "Dynamic", comment: "Adjustments: Dynamic ISF pill"),
                        color: .purple
                    )
                }
            }
        }

        private func adjustmentPill(text: String, color: Color) -> some View {
            Text(text)
                .font(.system(size: 9))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(color.opacity(0.15))
                .foregroundColor(color)
                .clipShape(Capsule())
        }
    }
}

// MARK: Preset Activation Handling

extension Adjustments.RootView: View {
    enum PendingPresetActivation {
        case override(objectID: NSManagedObjectID, presetID: String?, name: String)
        case tempTarget(objectID: NSManagedObjectID, presetID: String?, name: String)

        var name: String {
            switch self {
            case let .override(_, _, name),
                 let .tempTarget(_, _, name):
                return name
            }
        }

        var adjustmentType: String {
            switch self {
            case .override:
                return String(localized: "Override")
            case .tempTarget:
                return String(localized: "Temp Target")
            }
        }

        var confirmationMessage: String {
            String(localized: "Start the \(adjustmentType) \"\(name)\"?", comment: "Confirmation message for starting a preset")
        }
    }

    private var presetActivationConfirmationBinding: Binding<Bool> {
        Binding(
            get: {
                state.requireAdjustmentsConfirmation &&
                    state.shouldDisplayPresetStartConfirmDialog &&
                    pendingPresetActivation != nil
            },
            set: { isPresented in
                if !isPresented {
                    state.shouldDisplayPresetStartConfirmDialog = false
                    pendingPresetActivation = nil
                }
            }
        )
    }

    func requestPresetActivation(_ activation: PendingPresetActivation) {
        if state.requireAdjustmentsConfirmation {
            pendingPresetActivation = activation
            state.shouldDisplayPresetStartConfirmDialog = true
        } else {
            activatePreset(activation)
        }
    }

    func activatePreset(_ activation: PendingPresetActivation) {
        Task {
            switch activation {
            case let .override(objectID, presetID, _):
                await state.enactOverridePreset(withID: objectID)

                await MainActor.run {
                    state.hideModal()
                    selectedOverridePresetID = presetID
                    showOverrideCheckmark = true
                    state.shouldDisplayPresetStartConfirmDialog = false
                    pendingPresetActivation = nil
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    showOverrideCheckmark = false
                }

            case let .tempTarget(objectID, presetID, _):
                await state.enactTempTargetPreset(withID: objectID)

                await MainActor.run {
                    selectedTempTargetPresetID = presetID
                    showTempTargetCheckmark = true
                    state.shouldDisplayPresetStartConfirmDialog = false
                    pendingPresetActivation = nil
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    showTempTargetCheckmark = false
                }
            }
        }
    }
}
