import SwiftUI

/// Asks what a new backup should contain beyond the settings: optional sign-in details and device pairing,
/// which are then sealed with a passphrase. For an iCloud backup it also asks for the backup's name.
struct BackupExportOptionsView: View {
    enum Purpose {
        case file
        case iCloud
    }

    let purpose: Purpose
    let onConfirm: (_ name: String?, _ options: SensitiveExportOptions?) -> Void
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var includeCredentials = false
    @State private var includeDevices = false
    @State private var passphrase = ""
    @State private var confirmation = ""

    private var protectedRequested: Bool { includeCredentials || includeDevices }

    private var passphraseIsValid: Bool {
        passphrase.count >= SealedSensitiveBlob.minimumPassphraseLength && passphrase == confirmation
    }

    private var isValid: Bool {
        (purpose == .file || TrioSettingsBackup.normalizedName(name) != nil) && (!protectedRequested || passphraseIsValid)
    }

    var body: some View {
        NavigationStack {
            List {
                if purpose == .iCloud {
                    Section("Name Your Backup") {
                        TextField("Name", text: $name)
                    }.listRowBackground(Color.chart)
                }
                Section {
                    Toggle("Nightscout and Remote Control Sign-In", isOn: $includeCredentials)
                    Toggle("Pump and CGM Pairing", isOn: $includeDevices)
                } header: {
                    Text("Protected Data (Optional)").foregroundStyle(.red)
                } footer: {
                    Text(
                        "Sign-in details and device pairing are never saved in the clear. They are locked with a passphrase that you need again to restore them."
                    )
                }.listRowBackground(Color.chart)
                if includeDevices {
                    Section {
                        Text(
                            "Pairing can only be restored while setting up Trio on a new phone, and only after the old phone no longer runs Trio. Two phones controlling one pump is dangerous."
                        )
                        .font(.footnote)
                    }.listRowBackground(Color.chart)
                }
                if protectedRequested {
                    Section {
                        SecureField("Passphrase", text: $passphrase)
                        SecureField("Repeat Passphrase", text: $confirmation)
                    } header: {
                        Text("Passphrase")
                    } footer: {
                        Text(passphraseFooter)
                    }.listRowBackground(Color.chart)
                }
                if purpose == .iCloud, protectedRequested {
                    Section {
                        Text(
                            "iCloud keeps your backups encrypted with a key tied to your Apple account. Without Advanced Data Protection, Apple can recover that key, so choose a strong passphrase."
                        )
                        .font(.footnote)
                    }.listRowBackground(Color.chart)
                }
            }
            .listSectionSpacing(sectionSpacing)
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle(purpose == .file ? "Export Backup File" : "Back Up Now")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(purpose == .file ? "Export" : "Create Backup") {
                        let options = protectedRequested ? SensitiveExportOptions(
                            includeCredentials: includeCredentials,
                            includeDevices: includeDevices,
                            passphrase: passphrase
                        ) : nil
                        dismiss()
                        onConfirm(purpose == .iCloud ? name : nil, options)
                    }
                    .disabled(!isValid)
                }
            }
        }
        .presentationDetents([.large])
    }

    private var passphraseFooter: String {
        if passphrase.isEmpty || passphrase.count >= SealedSensitiveBlob.minimumPassphraseLength {
            return confirmation.isEmpty || passphrase == confirmation
                ? String(localized: "Use at least 8 characters. Trio cannot recover a forgotten passphrase; without it only the settings can be restored.")
                : String(localized: "The passphrases do not match.")
        }
        return String(localized: "Use at least 8 characters.")
    }
}
