import Foundation
import Observation

/// What the user confirmed before a pump's saved pairing may be adopted on this phone.
struct PumpAdoptionConfirmations: Equatable {
    /// "Trio is removed or the phone is wiped on the old phone."
    var oldPhoneStopped = false
    /// The final dialog naming the pump was accepted.
    var adoptionAccepted = false

    var isComplete: Bool { oldPhoneStopped && adoptionAccepted }
}

/// Decides whether a saved pump pairing may be adopted. Adoption makes this phone command a pump that another
/// phone may still control, so it is limited to onboarding on a phone without a pump, to pump types whose
/// pairing is known to move, and it needs both confirmations.
enum PumpAdoptionGate {
    enum Kind: Equatable {
        case medtrum
        case omnipodEros
        case medtronic

        var displayName: String {
            switch self {
            case .medtrum: return "Medtrum"
            case .omnipodEros: return "Omnipod (Eros)"
            case .medtronic: return "Medtronic"
            }
        }
    }

    enum Refusal: LocalizedError, Equatable {
        case notOnboarding
        case pumpAlreadyPaired
        case unreadableState
        case unsupported(String)
        case missingConfirmation

        var errorDescription: String? {
            switch self {
            case .notOnboarding:
                return String(localized: "Pump pairing can only be restored while setting up Trio.")
            case .pumpAlreadyPaired:
                return String(localized: "A pump is already paired with this phone.")
            case .unreadableState:
                return String(localized: "The saved pump pairing could not be read.")
            case let .unsupported(reason):
                return reason
            case .missingConfirmation:
                return String(localized: "Both confirmations are needed before a pump pairing is restored.")
            }
        }
    }

    /// Classifies the saved manager state. DASH and Dana pairings cannot move to another phone, and an
    /// unknown pump type has never been tested, so none of those are offered.
    static func kind(forManagerState base64: String) -> Result<Kind, Refusal> {
        guard let rawValue = SettingsBackup.decodeManagerState(base64),
              let identifier = rawValue["managerIdentifier"] as? String
        else { return .failure(.unreadableState) }
        let state = rawValue["state"] as? [String: Any] ?? rawValue
        let usesRileyLink = state.keys.contains { $0.localizedCaseInsensitiveContains("rileyLink") } ||
            rawValue.keys.contains { $0.localizedCaseInsensitiveContains("rileyLink") }
        if identifier.hasPrefix("Medtrum") { return .success(.medtrum) }
        if identifier.hasPrefix("Omni") {
            if usesRileyLink { return .success(.omnipodEros) }
            return .failure(.unsupported(String(
                localized: "A running Omnipod DASH pod cannot move to a new phone. Deactivate it and activate a new pod under Devices > Insulin Pump."
            )))
        }
        if identifier.hasPrefix("Minimed") { return .success(.medtronic) }
        if identifier.hasPrefix("Dana") {
            return .failure(.unsupported(String(
                localized: "Dana pumps do not reconnect from a saved pairing. Set the pump up again under Devices > Insulin Pump."
            )))
        }
        return .failure(.unsupported(String(
            localized: "Restoring this pump type's pairing has not been tested. Pair it manually under Devices > Insulin Pump."
        )))
    }

    /// A short label for the final dialog: the pump type and, when the state exposes one, its serial number.
    static func displayName(forManagerState base64: String) -> String {
        guard case let .success(kind) = kind(forManagerState: base64) else { return String(localized: "this pump") }
        let rawValue = SettingsBackup.decodeManagerState(base64)
        let state = rawValue?["state"] as? [String: Any] ?? [:]
        for key in ["pumpSN", "serialNumber", "pumpID", "podId"] {
            if let value = state[key], "\(value)".isNotEmpty { return "\(kind.displayName) (\(value))" }
        }
        return kind.displayName
    }

    static func check(
        managerState base64: String,
        isOnboarding: Bool,
        hasPairedPump: Bool,
        confirmations: PumpAdoptionConfirmations
    ) -> Refusal? {
        guard isOnboarding else { return .notOnboarding }
        guard !hasPairedPump else { return .pumpAlreadyPaired }
        if case let .failure(refusal) = kind(forManagerState: base64) { return refusal }
        guard confirmations.isComplete else { return .missingConfirmation }
        return nil
    }
}

/// Which parts of the protected tier the user chose to restore.
struct SensitiveSelection {
    var credentials: SensitiveTier.Credentials?
    var cgmState: String?
    var pumpState: String?
    var pumpConfirmations = PumpAdoptionConfirmations()

    var isEmpty: Bool { (credentials?.isEmpty ?? true) && cgmState == nil && pumpState == nil }
}

/// The user's choices while looking at a backup that carries a protected tier.
@Observable final class SensitiveRestoreModel {
    static let maximumAttempts = 3

    /// The readable content: plain for older files, or what the passphrase unlocked.
    var tier: SensitiveTier?
    var passphrase = ""
    var failedAttempts = 0
    var unlockError: String?
    var restoreNightscout = false
    var restoreRemoteSecret = false
    var restoreCGMPairing = false
    var restorePumpPairing = false
    var oldPhoneStopped = false
    /// Restoring the backup's treatment history is opt-in too.
    var restoreHistory = false

    var attemptsExhausted: Bool { failedAttempts >= Self.maximumAttempts }

    func reset(tier: SensitiveTier? = nil) {
        self.tier = tier
        passphrase = ""
        failedAttempts = 0
        unlockError = nil
        restoreNightscout = false
        restoreRemoteSecret = false
        restoreCGMPairing = false
        restorePumpPairing = false
        oldPhoneStopped = false
        restoreHistory = false
    }

    func unlock(_ backup: TrioSettingsBackup) {
        guard !attemptsExhausted else { return }
        defer { passphrase = "" }
        do {
            tier = try backup.unlockSensitive(passphrase: passphrase)
            unlockError = nil
        } catch {
            failedAttempts += 1
            unlockError = attemptsExhausted
                ? String(localized: "Too many wrong passphrases. You can still restore everything else.")
                : error.localizedDescription
        }
    }

    /// Builds the selection, or nil when nothing protected was chosen.
    func selection(allowsPairing: Bool, adoptionAccepted: Bool) -> SensitiveSelection? {
        guard let tier else { return nil }
        var result = SensitiveSelection()
        if let credentials = tier.credentials {
            var chosen = SensitiveTier.Credentials()
            if restoreNightscout {
                chosen.nightscoutURL = credentials.nightscoutURL
                chosen.nightscoutSecret = credentials.nightscoutSecret
            }
            if restoreRemoteSecret { chosen.remoteControlSharedSecret = credentials.remoteControlSharedSecret }
            result.credentials = chosen.isEmpty ? nil : chosen
        }
        if allowsPairing {
            if restoreCGMPairing { result.cgmState = tier.devices?.cgmState }
            if restorePumpPairing {
                result.pumpState = tier.devices?.pumpState
                result.pumpConfirmations = PumpAdoptionConfirmations(
                    oldPhoneStopped: oldPhoneStopped,
                    adoptionAccepted: adoptionAccepted
                )
            }
        }
        return result.isEmpty ? nil : result
    }
}
