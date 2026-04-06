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
                                "Each preset stores: Basal Rates, Insulin Sensitivities (ISF), Carb Ratios (CR), and Glucose Targets.",
                                comment: "ProfilePresets: description of what is stored in a preset"
                            )
                        } icon: {
                            Image(systemName: "list.bullet.clipboard")
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
            .alert(
                Text("Save Profile Preset", comment: "ProfilePresets: alert title for saving a new preset"),
                isPresented: $state.showingSaveDialog
            ) {
                TextField(
                    String(
                        localized: "Preset Name",
                        comment: "ProfilePresets: placeholder for preset name input"
                    ),
                    text: $state.newPresetName
                )
                Button(String(localized: "Save", comment: "ProfilePresets: save button")) {
                    state.saveCurrentProfileAsPreset()
                }
                Button(String(localized: "Cancel", comment: "ProfilePresets: cancel button"), role: .cancel) {
                    state.newPresetName = ""
                }
            } message: {
                Text(
                    "Enter a name for this profile preset. Your current Basal Rates, ISF, CR, and Glucose Targets will be saved.",
                    comment: "ProfilePresets: alert message explaining what will be saved"
                )
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
                    Text(
                        "This will overwrite your current Basal Rates, ISF, CR, and Glucose Targets with the settings from '\(preset.name)'. Are you sure?",
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
        }

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
            }
            .padding(.vertical, 4)
        }

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
            }
            .foregroundColor(.secondary)
        }

        private func deletePresets(at offsets: IndexSet) {
            for index in offsets {
                let preset = state.presets[index]
                state.deletePreset(preset)
            }
        }
    }
}
