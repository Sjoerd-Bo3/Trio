import SwiftUI
import UniformTypeIdentifiers

struct TrioBackupImportStepView: View {
    @Bindable var state: Onboarding.StateModel
    @State private var isFilePickerPresented = false
    @State private var activeImportError: TrioBackupImportError?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Please choose if you want to restore a Trio settings backup file or set up Trio manually.")
                .font(.headline)
                .padding(.horizontal)
                .multilineTextAlignment(.leading)

            ForEach([TrioBackupImportOption.useImport, TrioBackupImportOption.skipImport], id: \.self) { option in
                Button(action: {
                    state.backupImportOption = option
                }) {
                    HStack {
                        Image(systemName: state.backupImportOption == option ? "largecircle.fill.circle" : "circle")
                            .foregroundColor(state.backupImportOption == option ? .accentColor : .secondary)
                            .imageScale(.large)

                        Text(option.displayName)
                            .foregroundColor(.primary)

                        Spacer()
                    }
                    .padding()
                    .background(Color.chart.opacity(0.65))
                    .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }

            if state.backupImportOption == .useImport {
                if let backup = state.importedBackup {
                    backupSummaryCard(backup)
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

            VStack(alignment: .leading, spacing: 10) {
                Text("A Trio backup can prefill your entire setup:")
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading) {
                    BulletPoint(String(localized: "Therapy settings — you still review every value"))
                    BulletPoint(String(localized: "Algorithm settings and delivery limits"))
                    BulletPoint(String(localized: "Features, notifications, services, and presets"))
                }
            }
            .padding(.horizontal)
            .font(.footnote)
            .foregroundStyle(Color.secondary)
            .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fileImporter(
            isPresented: $isFilePickerPresented,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                if let url = urls.first {
                    state.loadOnboardingBackup(from: url)
                }
            case let .failure(error):
                state.backupImportError = TrioBackupImportError(message: error.localizedDescription)
            }
        }
        .alert(item: $activeImportError) { error in
            Alert(
                title: Text("Import Failed"),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .onChange(of: state.backupImportError?.id) { _, _ in
            if let error = state.backupImportError {
                activeImportError = error
                state.backupImportError = nil
            }
        }
    }

    private func backupSummaryCard(_ backup: SettingsBackup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Backup loaded")
                    .fontWeight(.semibold)
                Spacer()
                Button(action: { isFilePickerPresented = true }) {
                    Text("Change")
                        .font(.footnote)
                }
            }

            if let exportDate = backup.exportDate {
                Text("Created: \(DateFormatter.localizedString(from: exportDate, dateStyle: .medium, timeStyle: .short))")
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
            }
            if let appVersion = backup.appVersion {
                Text("App Version: \(appVersion)")
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
            }
            if let pumpType = backup.devices?.pumpType {
                Text("Pump: \(pumpType)")
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
            }
            if let history = backup.history {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Includes treatment history — this will be restored:")
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                    ForEach(SettingsBackupHistory.previewCounts(history)) { historyCount in
                        HStack {
                            Text(historyCount.label)
                            Spacer()
                            Text("\(historyCount.count)")
                        }
                        .font(.footnote)
                        .foregroundStyle(Color.secondary)
                    }
                }
            }

            if backup.credentials != nil {
                Toggle(isOn: $state.importBackupCredentials) {
                    Text("Restore Nightscout credentials")
                        .font(.footnote)
                }
            }
            if backup.devices?.pumpState != nil || backup.devices?.cgmState != nil {
                Toggle(isOn: $state.importBackupDevicePairing) {
                    Text("Restore pump/CGM pairing")
                        .font(.footnote)
                }
                if state.importBackupDevicePairing {
                    Text("Only restore pairing if the previous phone no longer runs Trio. Two phones controlling one pump is dangerous.")
                        .font(.footnote)
                        .foregroundStyle(Color.orange)
                }
            }
        }
        .padding()
        .background(Color.chart.opacity(0.65))
        .cornerRadius(10)
    }
}
