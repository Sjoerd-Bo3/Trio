import SwiftUI
import UniformTypeIdentifiers

struct RestoreBackupStepView: View {
    @Bindable var state: Onboarding.StateModel
    @State private var isFilePickerPresented = false
    @State private var showingRestoreConfirmation = false
    @State private var showingOverview = false
    @State private var cloudStatus: CloudBackupAvailability.Status = .notBuilt

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Please choose if you want to restore a Trio settings backup or start fresh.")
                .font(.headline)
                .padding(.horizontal)
                .multilineTextAlignment(.leading)

            optionButton(.restore, title: String(localized: "Restore From Backup File"))
            if cloudStatus == .available {
                optionButton(.restoreICloud, title: String(localized: "Restore From iCloud"))
            }
            optionButton(.startFresh, title: String(localized: "Start Fresh With New Settings"))

            if state.backupRestoreOption == .restore {
                restoreSection
            } else if state.backupRestoreOption == .restoreICloud {
                cloudRestoreSection
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("A Trio backup restores your setup:")
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading) {
                    BulletPoint(String(localized: "Therapy settings, which you still review on the next screens"))
                    BulletPoint(String(localized: "Algorithm settings, delivery limits, alerts and presets"))
                    BulletPoint(String(localized: "Your CGM selection; the CGM itself is set up afterwards"))
                }
                Text("Trio always starts in Open Loop after a restore. You switch to Closed Loop yourself once everything is reviewed.")
                    .padding(.top, 4)
            }
            .padding(.horizontal)
            .font(.footnote)
            .foregroundStyle(Color.secondary)
            .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { cloudStatus = await CloudBackupAvailability.status() }
        .disabled(state.backupRestoreInProgress)
        .overlay {
            if state.backupRestoreInProgress { ProgressView("Restoring settings… Keep Trio open.") }
        }
        .fileImporter(
            isPresented: $isFilePickerPresented,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                if let url = urls.first {
                    Task { await state.loadBackupFile(from: url) }
                }
            case let .failure(error):
                if (error as? CocoaError)?.code != .userCancelled { state.backupRestoreError = error.localizedDescription }
            }
        }
        .alert("Restore Backup", isPresented: Binding(
            get: { state.backupRestoreError != nil },
            set: { if !$0 { state.backupRestoreError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(state.backupRestoreError ?? "")
        }
        .sheet(isPresented: $showingOverview) {
            NavigationStack {
                if let overview = state.pendingBackupOverview {
                    BackupChangeOverviewView(changeSet: overview)
                }
            }
        }
    }

    @ViewBuilder private var cloudRestoreSection: some View {
        if state.backupWasRestored {
            restoredCard
        } else {
            TrioCloudBackupBrowser(
                onSelectForOnboarding: { state.selectCloudBackup($0) },
                selectedBackupID: state.pendingBackup?.id.uuidString
            )
            if let backup = state.pendingBackup {
                summaryCard(backup)
            }
        }
    }

    @ViewBuilder private var restoreSection: some View {
        if state.backupWasRestored {
            restoredCard
        } else if let backup = state.pendingBackup {
            summaryCard(backup)
        } else {
            Button(action: { isFilePickerPresented = true }) {
                HStack {
                    Image(systemName: "doc.badge.plus")
                    Text("Select Backup File")
                    Spacer()
                }
                .padding()
                .background(Color.blue.opacity(0.2))
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
    }

    private func optionButton(_ option: BackupRestoreOption, title: String) -> some View {
        Button(action: { state.chooseBackupRestoreOption(option) }) {
            HStack {
                Image(systemName: state.backupRestoreOption == option ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(state.backupRestoreOption == option ? .accentColor : .secondary)
                    .imageScale(.large)
                Text(title).foregroundColor(.primary)
                Spacer()
            }
            .padding()
            .background(Color.chart.opacity(0.65))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
        .disabled(state.backupWasRestored)
        .accessibilityAddTraits(state.backupRestoreOption == option ? [.isSelected] : [])
    }

    private func summaryCard(_ backup: TrioSettingsBackup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "doc.text.fill").foregroundColor(.blue)
                Text("Backup selected").fontWeight(.semibold)
                Spacer()
                if state.backupRestoreOption == .restore {
                    Button(action: { isFilePickerPresented = true }) {
                        Text("Change").font(.footnote)
                    }
                }
            }
            Text("Created: \(backup.createdAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.footnote)
                .foregroundStyle(Color.secondary)
            Text("App Version: \(backup.appVersion)")
                .font(.footnote)
                .foregroundStyle(Color.secondary)
            if let pump = backup.deviceInfo?.pumpType {
                Text("Pump: \(pump). Pumps are paired manually later.")
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
            }
            if let cgm = backup.deviceInfo?.cgmDisplayName {
                Text("CGM: \(cgm)")
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
            }
            ForEach(state.pendingBackupWarnings, id: \.self) { warning in
                Text(warning).font(.footnote).foregroundStyle(Color.orange)
            }
            if state.pendingBackupOverview != nil {
                Button("Show Settings in This Backup") { showingOverview = true }
                    .font(.footnote)
            }
            Button(action: { showingRestoreConfirmation = true }) {
                Text("Restore Settings")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .foregroundColor(.white)
                    .background(Capsule().fill(Color.blue))
            }
            .buttonStyle(.plain)
            .confirmationDialog("Restore Settings?", isPresented: $showingRestoreConfirmation, titleVisibility: .visible) {
                Button("Restore") { Task { await state.applyPendingBackup() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Trio will use the settings from this backup. It starts in Open Loop and nothing is sent to a pump.")
            }
        }
        .padding()
        .background(Color.chart.opacity(0.65))
        .cornerRadius(10)
    }

    private var restoredCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                Text("Settings restored").fontWeight(.semibold)
            }
            Text(
                "Trio is in Open Loop. The next onboarding steps are prefilled from the backup. Continue and review every screen before you confirm it."
            )
            .font(.footnote)
            ForEach(state.restoreWarnings, id: \.self) { warning in
                Text(warning).font(.footnote).foregroundStyle(Color.orange)
            }
        }
        .padding()
        .background(Color.chart.opacity(0.65))
        .cornerRadius(10)
    }
}
