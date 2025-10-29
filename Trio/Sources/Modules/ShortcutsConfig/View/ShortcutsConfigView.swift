import Combine
import SwiftUI
import Swinject
import UIKit

extension ShortcutsConfig {
    struct RootView: BaseView {
        let resolver: Resolver

        @StateObject var state = StateModel()
        @StateObject private var hintManager = SettingsHintManager()

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        var body: some View {
            List {
                Section(
                    header: Text("Shortcuts Integration"),
                    content: {
                        Text(
                            "Trio lets you create automations using iOS Shortcuts. Go to the Shortcuts app to create new automations."
                        )
                    }
                ).listRowBackground(Color.chart)

                Section {
                    Button {
                        UIApplication.shared.open(URL(string: "shortcuts://")!)
                    }
                    label: { Label("Open iOS Shortcuts", systemImage: "arrow.triangle.branch").font(.title3).padding() }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .buttonStyle(.bordered)
                }
                .listRowBackground(Color.clear)

                SettingInputSection(
                    decimalValue: $hintManager.decimalPlaceholder,
                    booleanValue: $state.allowBolusByShortcuts,
                    shouldDisplayHint: $hintManager.shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = String(localized: "Allow Bolusing with Shortcuts")
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: String(localized: "Allow Bolusing with Shortcuts"),
                    miniHint: String(localized: "Automate boluses using the iOS Shortcuts App."),
                    verboseHint: VStack(alignment: .leading, spacing: 10) {
                        Text("Default: OFF").bold()
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Enabling this setting allows the iOS Shortcuts App to send bolus commands to Trio.")
                            Text(
                                "Disabling this setting will still allow other commands, like Temp Targets, Add Carbs, and Start/End Overrides"
                            )
                        }
                    }
                )
            }
            .listSectionSpacing(sectionSpacing)
            .settingsHint(manager: hintManager)
            .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
            .onAppear(perform: configureView)
            .navigationTitle("Shortcuts")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
