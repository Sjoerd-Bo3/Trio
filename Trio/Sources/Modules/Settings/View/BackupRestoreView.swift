import SwiftUI
import UniformTypeIdentifiers

struct BackupRestoreView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @State private var exporting = false
    @State private var message: String?
    @State private var importing = false
    @State private var presentation: BackupPresentation?
    @State private var attention: String?
    @State private var reviewPending = false
    @State private var cloudStatus: CloudBackupAvailability.Status = .notBuilt
    @State private var backingUp = false
    @State private var naming = false
    @State private var name = ""
    @State private var createdName: String?
    @State private var lastBackup: Date?

    private enum BackupPresentation: Identifiable {
        case exported(BackupExportFile)
        case imported(BackupFileService.Opened)

        var id: String {
            switch self {
            case let .exported(file): return file.id.uuidString
            case let .imported(opened): return opened.snapshot.id.uuidString
            }
        }
    }

    var body: some View {
        ZStack {
            backupList
        }
        .navigationTitle("Backup & Restore")
        .navigationBarTitleDisplayMode(.large)
        .onAppear(perform: refreshNotices)
        .task { cloudStatus = await CloudBackupAvailability.status() }
        .onReceive(Foundation.NotificationCenter.default.publisher(for: TrioCloudBackupCoordinator.uploadNotification)) { _ in
            lastBackup = TrioCloudBackupCoordinator.shared.lastSuccessfulBackupDate
        }
        .alert("Name Your Backup", isPresented: $naming) {
            TextField("Name", text: $name)
            Button("Cancel", role: .cancel) {}
            Button("Create Backup") {
                let requestedName = name
                Task { @MainActor in
                    backingUp = true
                    defer { backingUp = false
                        lastBackup = TrioCloudBackupCoordinator.shared.lastSuccessfulBackupDate }
                    do {
                        let entry = try await TrioCloudBackupCoordinator.shared.createManualBackup(name: requestedName)
                        createdName = entry.name ?? TrioSettingsBackup.normalizedName(requestedName)
                        name = ""
                    } catch { message = error.localizedDescription }
                }
            }
            .disabled(TrioSettingsBackup.normalizedName(name) == nil)
        }
        .alert("Success!", isPresented: Binding(get: { createdName != nil }, set: { if !$0 { createdName = nil } })) {
            Button("Done", role: .cancel) {}
        } message: {
            Text("Your \"\(createdName ?? "")\" backup has been saved to iCloud.")
        }
        .alert("Backup & Restore", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(message ?? "") }
        .sheet(item: $presentation) { destination in
            switch destination {
            case let .exported(file):
                ShareSheet(activityItems: [file.url])
            case let .imported(opened):
                NavigationStack {
                    BackupDetailView(
                        entry: opened.snapshot.entry,
                        snapshot: opened.snapshot,
                        warnings: opened.warnings,
                        allowsExport: false,
                        onSelectForOnboarding: nil
                    )
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let opened = try BackupFileService.open(url: url)
                // Let the importer close before presenting backup details.
                DispatchQueue.main.async { presentation = .imported(opened) }
            } catch {
                if (error as? CocoaError)?.code != .userCancelled { message = error.localizedDescription }
            }
        }
    }

    private var backupList: some View {
        List {
            if let attention {
                Section {
                    Text("A previous settings restore did not finish. Trio switched to Open Loop. Check your therapy settings and your pump before returning to Closed Loop.")
                    Text(attention).font(.footnote).foregroundStyle(.secondary)
                    Button("Dismiss") {
                        UserDefaults.standard.removeObject(forKey: SettingsBackupRestore.needsAttentionKey)
                        refreshNotices()
                    }
                    .buttonStyle(.borderless)
                } header: { Text("Restore Needs Attention") }.listRowBackground(Color.chart)
            }
            if reviewPending {
                Section {
                    Text("Settings were restored from a backup and Trio is in Open Loop. Review your therapy settings, then switch to Closed Loop yourself when you are ready.")
                    Button("I Have Reviewed My Settings") {
                        UserDefaults.standard.removeObject(forKey: SettingsBackupRestore.reviewPendingKey)
                        refreshNotices()
                    }
                    .buttonStyle(.borderless)
                } header: { Text("Review Restored Settings") }.listRowBackground(Color.chart)
            }
            if cloudStatus != .notBuilt {
                iCloudSections
            }
            Section {
                Button {
                    guard !exporting, presentation == nil, !importing else { return }
                    exporting = true
                    Task { @MainActor in
                        defer { exporting = false }
                        do {
                            presentation = .exported(BackupExportFile(url: try await BackupService.shared.exportBackupFile()))
                        } catch { message = error.localizedDescription }
                    }
                } label: {
                    HStack {
                        Text("Export Backup File")
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(exporting)
                Button("Import Backup File") {
                    guard !exporting, presentation == nil, !importing else { return }
                    importing = true
                }
                .buttonStyle(.borderless)
            } header: { Text("Backup File") } footer: {
                Text("A backup file holds your therapy, algorithm and app settings. It never contains your pump or CGM pairing or any sign-in details.")
            }.listRowBackground(Color.chart)
        }
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
        .listSectionSpacing(sectionSpacing)
        .allowsHitTesting(!exporting && !importing && !backingUp)
    }

    @ViewBuilder private var iCloudSections: some View {
        if cloudStatus == .available {
            Section {
                Button {
                    guard !backingUp, presentation == nil, !importing else { return }
                    name = ""
                    naming = true
                } label: {
                    HStack {
                        Text("Back Up Now")
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .disabled(backingUp)
            } header: { Text("iCloud Backup") } footer: {
                Text(
                    lastBackup
                        .map { "Last successful backup: \($0.formatted(date: .abbreviated, time: .shortened))" } ??
                        "No recent backups."
                )
            }.listRowBackground(Color.chart)
            Section {
                NavigationLink("View Backups") { TrioCloudBackupBrowser() }
            }.listRowBackground(Color.chart)
            Section {
                NavigationLink("Configuration") { TrioCloudBackupConfigurationView() }
            }.listRowBackground(Color.chart)
        } else {
            Section {
                Text("Sign in to iCloud in iPhone Settings and enable iCloud for Trio to back up your settings to iCloud.")
                    .foregroundStyle(.secondary)
            } header: { Text("iCloud Backup") }.listRowBackground(Color.chart)
        }
    }

    private func refreshNotices() {
        lastBackup = TrioCloudBackupCoordinator.shared.lastSuccessfulBackupDate
        attention = UserDefaults.standard.string(forKey: SettingsBackupRestore.needsAttentionKey)
        reviewPending = UserDefaults.standard.bool(forKey: SettingsBackupRestore.reviewPendingKey)
    }
}

struct BackupExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

extension TrioSettingsBackup {
    var entry: BackupEntry {
        .init(id: id.uuidString, createdAt: createdAt, origin: origin, name: name, fingerprint: fingerprint)
    }
}
