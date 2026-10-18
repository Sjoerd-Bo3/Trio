import SwiftUI

/// The protected part of a backup: sign-in details and device pairing. It is locked behind the passphrase and
/// restored only for the parts the user switches on. Pairing is offered during setup only.
struct SensitiveRestoreSection: View {
    let backup: TrioSettingsBackup
    let allowsPairing: Bool
    @Bindable var model: SensitiveRestoreModel
    @State private var promptingPassphrase = false

    /// True when there is anything protected to show.
    static func isRelevant(_ backup: TrioSettingsBackup, model: SensitiveRestoreModel) -> Bool {
        backup.sensitive != nil || !(model.tier?.isEmpty ?? true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let tier = model.tier {
                unlocked(tier)
            } else if backup.sensitive != nil {
                locked
            }
        }
        .alert("Unlock Protected Data", isPresented: $promptingPassphrase) {
            SecureField("Passphrase", text: $model.passphrase)
            Button("Cancel", role: .cancel) { model.passphrase = "" }
            Button("Unlock") { model.unlock(backup) }
        } message: {
            Text("Enter the passphrase you chose when you made this backup.")
        }
    }

    private var locked: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This backup also holds sign-in details or device pairing, protected by a passphrase.")
            if model.attemptsExhausted {
                Text(model.unlockError ?? "").font(.footnote).foregroundStyle(.secondary)
            } else {
                Button("Unlock with Passphrase") { promptingPassphrase = true }
                    .buttonStyle(.borderless)
                if let error = model.unlockError {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }
        }
    }

    @ViewBuilder private func unlocked(_ tier: SensitiveTier) -> some View {
        if let credentials = tier.credentials, !credentials.isEmpty {
            if let host = tier.nightscoutHost {
                Toggle(isOn: $model.restoreNightscout) {
                    VStack(alignment: .leading) {
                        Text("Nightscout Sign-In")
                        Text(host).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            if credentials.remoteControlSharedSecret?.isNotEmpty == true {
                Toggle("Remote Control Secret", isOn: $model.restoreRemoteSecret)
                Text("Remote commands stay off until you turn them on under Settings > Services.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        if let devices = tier.devices, !devices.isEmpty {
            if allowsPairing {
                pairing(devices)
            } else {
                Text("Pump and CGM pairing can only be restored while setting up Trio on a new phone.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func pairing(_ devices: SensitiveTier.Devices) -> some View {
        if let cgmState = devices.cgmState {
            Toggle("CGM Pairing", isOn: $model.restoreCGMPairing)
            if let note = SettingsBackup.cgmPairingNote(forManagerState: cgmState) {
                Text(note).font(.footnote).foregroundStyle(.secondary)
            }
        }
        if let pumpState = devices.pumpState {
            switch PumpAdoptionGate.kind(forManagerState: pumpState) {
            case let .success(kind):
                Toggle("Pump Pairing (\(kind.displayName))", isOn: $model.restorePumpPairing)
                if let note = SettingsBackup.pumpPairingNote(forManagerState: pumpState) {
                    Text(note).font(.footnote).foregroundStyle(.secondary)
                }
                if model.restorePumpPairing {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Another phone may still control this pump")
                            .fontWeight(.semibold)
                            .foregroundStyle(.red)
                        Text(
                            "Two phones commanding one pump can cause over- or under-delivery. Remove Trio from the old phone or wipe it before you continue."
                        )
                        .font(.footnote)
                        Toggle("The old phone is wiped or Trio is removed from it", isOn: $model.oldPhoneStopped)
                            .font(.footnote)
                    }
                }
            case let .failure(refusal):
                Text(refusal.localizedDescription).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}
