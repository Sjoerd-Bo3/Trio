import SwiftUI
import Swinject
import UniformTypeIdentifiers

extension SettingsImport {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        @State private var isFilePickerPresented = false
        @State private var isImportConfirmationPresented = false
        @State private var isPairingConfirmationPresented = false

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState
        @Environment(\.dismiss) var dismiss

        var body: some View {
            List {
                switch state.phase {
                case .pickFile:
                    pickFileSections
                case .preview:
                    previewSections
                case .applying:
                    applyingSection
                case .results:
                    resultsSections
                }
            }
            .listSectionSpacing(sectionSpacing)
            .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
            .onAppear(perform: configureView)
            .navigationTitle("Import Settings")
            .navigationBarTitleDisplayMode(.automatic)
            .fileImporter(
                isPresented: $isFilePickerPresented,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case let .success(urls):
                    if let url = urls.first {
                        state.loadBackup(from: url)
                    }
                case let .failure(error):
                    state.importErrorMessage = error.localizedDescription
                }
            }
            .confirmationDialog(
                Text("Overwrite current settings?"),
                isPresented: $isImportConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("Import & Overwrite", role: .destructive) {
                    if state.importDevicePairing {
                        isPairingConfirmationPresented = true
                    } else {
                        Task { await state.applyImport() }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(importConfirmationMessage)
            }
            .confirmationDialog(
                Text("Restore device pairing?"),
                isPresented: $isPairingConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("Restore Pairing & Import", role: .destructive) {
                    Task { await state.applyImport() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "Only restore device pairing if the previous phone no longer runs Trio. Two phones controlling one pump is dangerous."
                )
            }
            .alert(
                "Import Error",
                isPresented: Binding(
                    get: { state.importErrorMessage != nil },
                    set: { if !$0 { state.importErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(state.importErrorMessage ?? "")
            }
        }

        private var importConfirmationMessage: String {
            var message = String(localized: "The selected categories will be overwritten with the values from the backup.")
            if state.closedLoopActive {
                message += " " +
                    String(
                        localized: "Closed loop is currently active. New settings take effect on the next loop cycle — review your settings afterwards."
                    )
            }
            return message
        }

        // MARK: - Pick file

        @ViewBuilder private var pickFileSections: some View {
            Section(
                header: Text("Restore from Backup"),
                content: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Select a Trio settings backup (.json) created via Export Settings.")
                        BulletPoint(String(localized: "You will see exactly what changes before anything is applied."))
                        BulletPoint(String(localized: "All values are checked against Trio's safety limits."))
                        BulletPoint(String(localized: "Pump and CGM pairing can only be restored if the backup includes it."))
                    }
                    .padding(.vertical, 4)
                }
            ).listRowBackground(Color.chart)

            Section {
                Button(
                    action: {
                        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                        isFilePickerPresented = true
                    },
                    label: {
                        Text("Select Backup File")
                    }
                )
                .frame(maxWidth: .infinity, alignment: .center)
                .tint(.white)
            }.listRowBackground(Color(.systemBlue))
        }

        // MARK: - Preview

        @ViewBuilder private var previewSections: some View {
            backupDetailsSection
            categoriesSection
            if state.presetCategorySelected {
                presetConflictSection
            }
            if state.backup?.credentials != nil || state.backup?.devices?.pumpState != nil ||
                state.backup?.devices?.cgmState != nil
            {
                sensitiveDataSection
            }
            notImportedSection
            importButtonSection
        }

        private var backupDetailsSection: some View {
            Section(
                header: Text("Backup Details"),
                content: {
                    if let exportDate = state.backup?.exportDate {
                        detailRow(
                            String(localized: "Export Date"),
                            DateFormatter.localizedString(from: exportDate, dateStyle: .medium, timeStyle: .short)
                        )
                    }
                    if let appVersion = state.backup?.appVersion {
                        detailRow(
                            String(localized: "App Version"),
                            "\(appVersion) (\(state.backup?.buildNumber ?? "?"))"
                        )
                    }
                    if let branch = state.backup?.branch {
                        detailRow(String(localized: "Branch"), branch)
                    }
                    if let pumpType = state.backup?.devices?.pumpType {
                        detailRow(String(localized: "Pump Type"), pumpType)
                    }
                    if let cgmName = state.backup?.devices?.cgmDisplayName {
                        detailRow(String(localized: "CGM"), cgmName)
                    }
                    if state.backupSchemaIsNewer {
                        Text("This backup was created by a newer Trio version. Unknown settings are ignored.")
                            .foregroundColor(.orange)
                            .font(.footnote)
                    }
                    if let therapyMessage = state.therapyValidationMessage {
                        Text(therapyMessage)
                            .foregroundColor(.orange)
                            .font(.footnote)
                    }
                }
            ).listRowBackground(Color.chart)
        }

        private var allAvailableSelected: Bool {
            state.selectedCategories.isSuperset(of: state.availableCategories)
        }

        private var categoriesSection: some View {
            Section(
                header: Text("Import Categories"),
                footer: Text("Only settings that differ from your current configuration are listed."),
                content: {
                    Button(action: {
                        if allAvailableSelected {
                            state.selectedCategories = []
                        } else {
                            state.selectedCategories = state.availableCategories
                        }
                    }) {
                        HStack {
                            Image(systemName: allAvailableSelected ? "checkmark.square.fill" : "square")
                                .foregroundColor(allAvailableSelected ? .blue : .secondary)
                            Text(allAvailableSelected ? String(localized: "Deselect All") : String(localized: "Select All"))
                                .fontWeight(.bold)
                                .foregroundColor(.primary)
                            Spacer()
                        }
                    }
                    .buttonStyle(PlainButtonStyle())

                    ForEach(SettingsBackupCategory.allCases.filter { state.availableCategories.contains($0) }) { category in
                        categoryRow(category)
                    }
                }
            ).listRowBackground(Color.chart)
        }

        @ViewBuilder private func categoryRow(_ category: SettingsBackupCategory) -> some View {
            let changeCount = state.changeSet.changeCount(for: category)

            DisclosureGroup(
                content: {
                    ForEach(state.changeSet.settingChanges[category] ?? []) { change in
                        changeRow(change)
                    }
                    if category == .therapy {
                        ForEach(state.changeSet.therapyChanges) { scheduleChange in
                            Text(scheduleChange.label)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            ForEach(scheduleChange.entryChanges) { change in
                                changeRow(change)
                            }
                        }
                    }
                    ForEach(state.changeSet.presetChanges[category] ?? []) { presetChange in
                        HStack {
                            Text(presetChange.name)
                            Spacer()
                            Text(presetChange.kind.displayName)
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                    if category == .history {
                        ForEach(state.changeSet.historyCounts) { historyCount in
                            HStack {
                                Text(historyCount.label)
                                    .font(.subheadline)
                                Spacer()
                                Text("\(historyCount.count)")
                                    .foregroundColor(.secondary)
                                    .font(.subheadline)
                            }
                        }
                        Text(
                            "The backup carries everything the old phone still held — Trio keeps about 3 months of treatment data, plus daily insulin totals for the one-year statistics. Existing entries are never duplicated."
                        )
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    }
                },
                label: {
                    HStack {
                        Button(action: {
                            if state.selectedCategories.contains(category) {
                                state.selectedCategories.remove(category)
                            } else {
                                state.selectedCategories.insert(category)
                            }
                        }) {
                            Image(
                                systemName: state.selectedCategories
                                    .contains(category) ? "checkmark.square.fill" : "square"
                            )
                            .foregroundColor(state.selectedCategories.contains(category) ? .blue : .secondary)
                        }
                        .buttonStyle(PlainButtonStyle())

                        Text(category.displayName)

                        Spacer()

                        Text(categoryBadge(category, changeCount: changeCount))
                            .font(.caption)
                            .foregroundColor(changeCount == 0 ? .secondary : .blue)
                    }
                }
            )
        }

        private func categoryBadge(_ category: SettingsBackupCategory, changeCount: Int) -> String {
            if category == .history {
                return changeCount == 0
                    ? String(localized: "no recent entries")
                    : String(localized: "\(changeCount) entry(s)")
            }
            return changeCount == 0
                ? String(localized: "no changes")
                : String(localized: "\(changeCount) change(s)")
        }

        private func changeRow(_ change: ImportChange) -> some View {
            HStack(alignment: .top) {
                Text(change.label)
                    .font(.subheadline)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(change.oldDisplay)
                        .strikethrough()
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text(change.newDisplay)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
            }
        }

        private var presetConflictSection: some View {
            Section(
                header: Text("Preset Conflicts"),
                footer: Text(state.conflictStrategy.explanation),
                content: {
                    Picker(
                        selection: $state.conflictStrategy,
                        label: Text("Existing Presets")
                    ) {
                        ForEach(PresetConflictStrategy.allCases) { strategy in
                            Text(strategy.displayName).tag(strategy)
                        }
                    }
                    .pickerStyle(.menu)
                }
            ).listRowBackground(Color.chart)
        }

        private var sensitiveDataSection: some View {
            Section {
                if state.backup?.credentials != nil {
                    Toggle(isOn: $state.importCredentials) {
                        Text("Import Credentials")
                    }
                }
                if state.backup?.devices?.pumpState != nil || state.backup?.devices?.cgmState != nil {
                    Toggle(isOn: $state.importDevicePairing) {
                        Text("Restore Device Pairing")
                    }
                }
            } header: {
                Text("Sensitive Data")
            } footer: {
                if state.importDevicePairing {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(
                            "Only restore device pairing if the previous phone no longer runs Trio. Two phones controlling one pump is dangerous."
                        )
                        .foregroundColor(.orange)
                        ForEach(SettingsBackup.devicePairingNotes(for: state.backup?.devices), id: \.self) { note in
                            Text(note)
                        }
                    }
                } else {
                    Text("The backup contains sensitive data. Choose what to restore.")
                }
            }
            .listRowBackground(Color.chart)
        }

        private var notImportedSection: some View {
            Section(
                header: Text("Not Imported"),
                content: {
                    ForEach(state.notImportedNotes, id: \.self) { note in
                        BulletPoint(note)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            ).listRowBackground(Color.chart)
        }

        @ViewBuilder private var importButtonSection: some View {
            Section {
                Button(
                    action: {
                        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                        isImportConfirmationPresented = true
                    },
                    label: {
                        Text("Import Settings")
                    }
                )
                .disabled(state.selectedCategories.isEmpty)
                .frame(maxWidth: .infinity, alignment: .center)
                .tint(.white)
            }.listRowBackground(
                state.selectedCategories.isEmpty ? Color(.systemGray4) : Color(.systemBlue)
            )

            Section {
                Button(
                    action: {
                        state.backup = nil
                        state.phase = .pickFile
                    },
                    label: {
                        Text("Choose Different File")
                    }
                )
                .frame(maxWidth: .infinity, alignment: .center)
            }.listRowBackground(Color.chart)
        }

        // MARK: - Applying

        private var applyingSection: some View {
            Section {
                HStack {
                    Spacer()
                    ProgressView().padding(.trailing, 10)
                    Text("Importing...")
                    Spacer()
                }
            }.listRowBackground(Color.chart)
        }

        // MARK: - Results

        @ViewBuilder private var resultsSections: some View {
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.largeTitle)
                            .foregroundColor(.green)
                        Text("Import Complete")
                            .font(.headline)
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
            }.listRowBackground(Color.chart)

            Section(
                header: Text("Applied Categories"),
                content: {
                    ForEach(state.appliedCategories) { category in
                        Text(category.displayName)
                    }
                }
            ).listRowBackground(Color.chart)

            if state.warnings.isNotEmpty {
                Section(
                    header: Text("Warnings"),
                    content: {
                        ForEach(state.warnings, id: \.self) { warning in
                            BulletPoint(warning)
                                .font(.footnote)
                                .foregroundColor(.orange)
                        }
                    }
                ).listRowBackground(Color.chart)
            }

            Section {
                Button(
                    action: { dismiss() },
                    label: {
                        Text("Done")
                    }
                )
                .frame(maxWidth: .infinity, alignment: .center)
                .tint(.white)
            }.listRowBackground(Color(.systemBlue))
        }

        private func detailRow(_ label: String, _ value: String) -> some View {
            HStack {
                Text(label)
                Spacer()
                Text(value).foregroundColor(.secondary)
            }
        }
    }
}
