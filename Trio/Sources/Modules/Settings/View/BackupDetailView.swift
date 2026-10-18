import SwiftUI

struct BackupDetailView: View {
    let entry: BackupEntry
    let warnings: [String]
    let onSelectForOnboarding: ((TrioSettingsBackup) -> Void)?
    let allowsExport: Bool
    /// Fetches the snapshot when it was not handed in (for example from a list of remote backups).
    let loader: (() async throws -> TrioSettingsBackup)?
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var backup: TrioSettingsBackup?
    @State private var overview: ImportChangeSet?
    @State private var loading = true
    @State private var message: String?
    @State private var showingRestoreConfirmation = false
    @State private var restoring = false
    @State private var restored = false
    @State private var restoreWarnings: [String] = []
    @State private var exported: BackupExportFile?
    @State private var sensitiveModel: SensitiveRestoreModel

    init(
        entry: BackupEntry,
        snapshot: TrioSettingsBackup? = nil,
        warnings: [String] = [],
        plainSensitive: SensitiveTier? = nil,
        allowsExport: Bool = true,
        loader: (() async throws -> TrioSettingsBackup)? = nil,
        onSelectForOnboarding: ((TrioSettingsBackup) -> Void)?
    ) {
        self.entry = entry
        self.warnings = warnings
        self.onSelectForOnboarding = onSelectForOnboarding
        self.allowsExport = allowsExport
        self.loader = loader
        _backup = State(initialValue: snapshot)
        let model = SensitiveRestoreModel()
        model.tier = plainSensitive
        _sensitiveModel = State(initialValue: model)
    }

    private var pumpBlocksRestore: Bool {
        onSelectForOnboarding == nil && BackupService.shared.hasPairedPump
    }

    var body: some View {
        ZStack {
            backupList
        }
        .sheet(item: $exported) { file in
            ShareSheet(activityItems: [file.url])
        }
    }

    private var backupList: some View {
        List {
            Section("Info") {
                LabeledContent("Name", value: entry.name ?? (entry.origin == .manual ? "Manual Backup" : "Automatic Backup"))
                LabeledContent("Created", value: entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("App Version", value: backup?.appVersion ?? entry.appVersion ?? "—")
                if let info = backup?.deviceInfo {
                    if let pump = info.pumpType { LabeledContent("Pump", value: pump) }
                    if let cgm = info.cgmDisplayName { LabeledContent("CGM", value: cgm) }
                }
            }.listRowBackground(Color.chart)
            if warnings.isNotEmpty {
                Section("Not Restored") {
                    ForEach(warnings, id: \.self) { Text($0).font(.footnote) }
                }.listRowBackground(Color.chart)
            }
            if let backup {
                if let overview {
                    Section {
                        NavigationLink {
                            BackupChangeOverviewView(changeSet: overview)
                        } label: {
                            LabeledContent("Changes to This Phone", value: "\(overview.totalChangeCount)")
                        }
                    } footer: {
                        Text("Compares this backup with your current settings. Restoring always switches Trio to Open Loop.")
                    }.listRowBackground(Color.chart)
                }
                if SensitiveRestoreSection.isRelevant(backup, model: sensitiveModel) {
                    Section("Protected Data") {
                        SensitiveRestoreSection(
                            backup: backup,
                            allowsPairing: onSelectForOnboarding != nil,
                            model: sensitiveModel
                        )
                    }.listRowBackground(Color.chart)
                }
                if HistoryRestoreRow.isRelevant(backup) {
                    Section("Treatment History") {
                        HistoryRestoreRow(backup: backup, model: sensitiveModel)
                    }.listRowBackground(Color.chart)
                }
                let nodes = BackupSettingsNode.make(from: backup)
                Section("Settings") {
                    ForEach(nodes) { node in
                        NavigationLink {
                            BackupSettingsPreviewView(node: node)
                        } label: { Text(LocalizedStringKey(node.title)) }
                    }
                }.listRowBackground(Color.chart)
                Section {
                    VStack {
                        restoreButton
                        if allowsExport && onSelectForOnboarding == nil { exportButton }
                        if pumpBlocksRestore {
                            Text("A paired pump blocks restoring settings. Remove your pump under Devices first.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.top, 4)
                        }
                    }
                    .padding(.top, 12)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                }.listRowBackground(Color.clear)
            } else {
                Section {
                    if loading { ProgressView("Loading backup…") }
                    else { Text("This backup couldn’t be opened.").foregroundStyle(.secondary) }
                }.listRowBackground(Color.chart)
            }
        }
        .disabled(restoring)
        .listSectionSpacing(sectionSpacing)
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
        .navigationTitle("Backup Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .tint(.primary).accessibilityLabel("Close backup details").disabled(restoring)
            }
        }
        .task {
            defer { loading = false }
            do {
                if backup == nil, let loader { backup = try await loader() }
                if let backup {
                    overview = await BackupService.shared.changeOverview(for: backup, onboarding: onSelectForOnboarding != nil)
                }
            } catch { message = error.localizedDescription }
        }
        .alert("Backup & Restore", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("Done", role: .cancel) {}
        } message: { Text(message ?? "") }
        .alert("Settings Restored!", isPresented: $restored) {
            Button("Done") { dismiss() }
        } message: {
            Text(
                "Trio has been switched to Open Loop.\n\nReview your restored settings before pairing a new insulin pump and returning to Closed Loop."
                    + (restoreWarnings.isEmpty ? "" : "\n\n" + restoreWarnings.joined(separator: "\n"))
            )
        }
        .overlay {
            if restoring {
                ZStack {
                    appState.trioBackgroundColor(for: colorScheme).ignoresSafeArea()
                    ProgressView("Restoring settings… Keep Trio open.")
                }
            }
        }
        .interactiveDismissDisabled(restoring)
    }

    private var restoreButton: some View {
        Group {
            if onSelectForOnboarding == nil {
                restoreActionButton.buttonStyle(.borderedProminent)
            } else {
                restoreActionButton.buttonStyle(.bordered)
            }
        }
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(.accentColor)
        .disabled(backup == nil || restoring || pumpBlocksRestore)
        // Attach the confirmation to its source button so iPad popovers anchor correctly.
        .confirmationDialog("Restore Settings?", isPresented: $showingRestoreConfirmation, titleVisibility: .visible) {
            Button("Restore", role: .destructive) {
                Task { await restore() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "A restore will overwrite your current settings with the settings from the selected backup. Trio will be in Open Loop afterwards."
            )
        }
    }

    private var restoreActionButton: some View {
        Button {
            guard let backup else { return }
            if let onSelectForOnboarding {
                onSelectForOnboarding(backup)
                dismiss()
            } else {
                showingRestoreConfirmation = true
            }
        } label: {
            actionLabel(
                onSelectForOnboarding == nil ? "Restore Settings" : "Select Backup",
                systemImage: onSelectForOnboarding == nil ? "arrow.down.doc" : nil,
                color: onSelectForOnboarding == nil ? (colorScheme == .dark ? .bgDarkBlue : .white) : .accentColor
            )
        }
    }

    private var exportButton: some View {
        Button {
            guard let backup, !restoring else { return }
            do {
                exported = BackupExportFile(url: try BackupFileService.export(backup))
            } catch { message = error.localizedDescription }
        } label: {
            actionLabel("Export Backup File", systemImage: "square.and.arrow.up", color: .accentColor)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(.accentColor)
        .disabled(backup == nil || restoring)
    }

    private func actionLabel(_ title: LocalizedStringKey, systemImage: String?, color: Color) -> some View {
        HStack {
            if let systemImage { Image(systemName: systemImage).accessibilityHidden(true) }
            Spacer(minLength: 0)
            Text(title).multilineTextAlignment(.center)
            Spacer(minLength: 0)
            // Match the leading icon's width to keep the title centered.
            if let systemImage { Image(systemName: systemImage).hidden().accessibilityHidden(true) }
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity)
        .bold()
    }

    @MainActor private func restore() async {
        guard let backup, !restoring else { return }
        restoring = true
        defer { restoring = false }
        do {
            let selection = sensitiveModel.selection(allowsPairing: false, adoptionAccepted: false)
            restoreWarnings = try await BackupService.shared.restoreConfiguredApp(
                backup,
                sensitive: selection,
                restoreHistory: sensitiveModel.restoreHistory
            ).warnings
            restored = true
        } catch {
            message = "Restore stopped. No pump settings were sent.\n\n" + error.localizedDescription
        }
    }
}
