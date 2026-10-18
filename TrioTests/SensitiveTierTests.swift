import Foundation
import Testing
@testable import Trio

@Suite("Protected Backup Tier") struct SensitiveTierTests {
    private let context = Data("backup-1".utf8)
    private let passphrase = "correct horse battery"

    private var tier: SensitiveTier {
        SensitiveTier(
            credentials: .init(
                nightscoutURL: "https://example.nightscout.test",
                nightscoutSecret: "supersecretvalue",
                remoteControlSharedSecret: "sharedremotesecret"
            ),
            devices: .init(pumpState: SettingsBackup.encodeManagerState(["managerIdentifier": "Medtrum", "state": ["pumpSN": 42]]))
        )
    }

    private func seal(_ tier: SensitiveTier? = nil, passphrase: String? = nil) throws -> SealedSensitiveBlob {
        try SealedSensitiveBlob.seal(
            tier ?? self.tier,
            passphrase: passphrase ?? self.passphrase,
            binding: context,
            iterations: SealedSensitiveBlob.minimumIterations
        )
    }

    // MARK: - Envelope

    @Test("A sealed tier opens with its passphrase and binding") func roundTrip() throws {
        let blob = try seal()
        let opened = try blob.open(SensitiveTier.self, passphrase: passphrase, binding: context)
        #expect(opened == tier)
    }

    @Test("A wrong passphrase, binding or edit is rejected") func rejectsWrongKeyOrTampering() throws {
        let blob = try seal()
        #expect(throws: SealedSensitiveBlob.SealError.wrongPassphraseOrDamaged) {
            _ = try blob.open(SensitiveTier.self, passphrase: "another passphrase", binding: context)
        }
        #expect(throws: SealedSensitiveBlob.SealError.wrongPassphraseOrDamaged) {
            _ = try blob.open(SensitiveTier.self, passphrase: passphrase, binding: Data("backup-2".utf8))
        }
        var damaged = blob.sealed
        damaged[damaged.count - 1] ^= 0x01
        #expect(throws: SealedSensitiveBlob.SealError.wrongPassphraseOrDamaged) {
            _ = try SealedSensitiveBlob(header: blob.header, sealed: damaged)
                .open(SensitiveTier.self, passphrase: passphrase, binding: context)
        }
        // The header is authenticated: a different salt or iteration count never opens the blob.
        var header = blob.header
        header.salt[0] ^= 0x01
        #expect(throws: SealedSensitiveBlob.SealError.wrongPassphraseOrDamaged) {
            _ = try SealedSensitiveBlob(header: header, sealed: blob.sealed)
                .open(SensitiveTier.self, passphrase: passphrase, binding: context)
        }
        header = blob.header
        header.iterations += 1
        #expect(throws: SealedSensitiveBlob.SealError.wrongPassphraseOrDamaged) {
            _ = try SealedSensitiveBlob(header: header, sealed: blob.sealed)
                .open(SensitiveTier.self, passphrase: passphrase, binding: context)
        }
    }

    @Test("The header records strong, bounded key derivation parameters") func headerParameters() throws {
        let blob = try seal()
        #expect(blob.header.kdf == "PBKDF2-HMAC-SHA256" && blob.header.cipher == "AES-256-GCM")
        #expect(blob.header.iterations >= 200_000)
        #expect(blob.header.salt.count == SealedSensitiveBlob.saltLength)
        #expect(SealedSensitiveBlob.defaultIterations >= 200_000)
        #expect(try seal().header.salt != blob.header.salt)

        var weak = blob.header
        weak.iterations = 1000
        #expect(throws: SealedSensitiveBlob.SealError.unsupportedFormat) {
            _ = try SealedSensitiveBlob(header: weak, sealed: blob.sealed)
                .open(SensitiveTier.self, passphrase: passphrase, binding: context)
        }
        var excessive = blob.header
        excessive.iterations = SealedSensitiveBlob.maximumIterations + 1
        #expect(throws: SealedSensitiveBlob.SealError.unsupportedFormat) {
            _ = try SealedSensitiveBlob(header: excessive, sealed: blob.sealed)
                .open(SensitiveTier.self, passphrase: passphrase, binding: context)
        }
    }

    @Test("Short passphrases are refused") func shortPassphrase() {
        #expect(throws: SealedSensitiveBlob.SealError.passphraseTooShort) { _ = try seal(passphrase: "short") }
    }

    @Test("The same passphrase works in composed and decomposed Unicode") func unicodeNormalization() throws {
        let composed = "pässwörd-lang"
        let decomposed = composed.decomposedStringWithCanonicalMapping
        #expect(composed != decomposed || composed.unicodeScalars.count != decomposed.unicodeScalars.count)
        let blob = try seal(passphrase: composed)
        #expect(try blob.open(SensitiveTier.self, passphrase: decomposed, binding: context) == tier)
    }

    // MARK: - Inside a snapshot

    @Test("An encoded snapshot never contains sealed secrets in the clear") func noPlaintextInSnapshot() throws {
        let backup = try BackupSnapshotTests().makeBackup(BackupSnapshotTests().validConfiguration())
        let sealed = try backup.sealingSensitive(tier, passphrase: passphrase)
        let text = String(decoding: try JSONEncoder().encode(sealed), as: UTF8.self)
        for secret in ["supersecretvalue", "sharedremotesecret", "example.nightscout.test", "Medtrum", "pumpSN"] {
            #expect(!text.contains(secret), "\(secret) must not appear in the file")
        }
        #expect(text.contains("\"sensitive\""))
        let other = SettingsBackup.encodeManagerState(["managerIdentifier": "Medtrum"]) ?? ""
        #expect(!text.contains(other))
    }

    @Test("The protected tier does not change the configuration fingerprint and survives a round trip") func snapshotTier() throws {
        let plain = try BackupSnapshotTests().makeBackup(BackupSnapshotTests().validConfiguration())
        let sealed = try plain.sealingSensitive(tier, passphrase: passphrase)
        #expect(sealed.fingerprint == plain.fingerprint)
        let decoded = try BackupFileService.open(JSONEncoder().encode(sealed)).snapshot
        #expect(decoded.sensitive == sealed.sensitive)
        #expect(try decoded.unlockSensitive(passphrase: passphrase) == tier)
        #expect(throws: SealedSensitiveBlob.SealError.wrongPassphraseOrDamaged) {
            _ = try decoded.unlockSensitive(passphrase: "not the passphrase")
        }
    }

    @Test("A protected tier cannot be moved into a different backup") func bindingToBackup() throws {
        let first = try BackupSnapshotTests().makeBackup(BackupSnapshotTests().validConfiguration())
        let second = try BackupSnapshotTests().makeBackup(BackupSnapshotTests().validConfiguration())
        var moved = second
        moved.sensitive = try first.sealingSensitive(tier, passphrase: passphrase).sensitive
        #expect(throws: SealedSensitiveBlob.SealError.wrongPassphraseOrDamaged) {
            _ = try moved.unlockSensitive(passphrase: passphrase)
        }
    }

    @Test("A damaged protected tier does not stop the settings from opening") func damagedTierIsIgnored() throws {
        let backup = try BackupSnapshotTests().makeBackup(BackupSnapshotTests().validConfiguration())
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(backup)) as? [String: Any])
        object["sensitive"] = ["header": "broken"]
        let opened = try BackupFileService.open(JSONSerialization.data(withJSONObject: object))
        #expect(opened.snapshot.sensitive == nil)
        #expect(opened.snapshot.fingerprint == backup.fingerprint)
    }

    // MARK: - Pump adoption

    private func pumpState(_ identifier: String, state: [String: Any] = ["pumpSN": 1]) throws -> String {
        try #require(SettingsBackup.encodeManagerState(["managerIdentifier": identifier, "state": state]))
    }

    private let confirmed = PumpAdoptionConfirmations(oldPhoneStopped: true, adoptionAccepted: true)

    @Test("Pump pairing moves only for Medtrum, Omnipod Eros and Medtronic during onboarding with both confirmations")
    func adoptionAllowed() throws {
        let eros = try pumpState("Omni", state: ["rileyLinkConnectionManagerState": ["autoConnectIDs": ["x"]]])
        for state in [try pumpState("Medtrum"), eros, try pumpState("Minimed500")] {
            #expect(PumpAdoptionGate.check(
                managerState: state, isOnboarding: true, hasPairedPump: false, confirmations: confirmed
            ) == nil)
        }
        #expect(PumpAdoptionGate.kind(forManagerState: eros) == .success(.omnipodEros))
    }

    @Test("Pump pairing is refused outside onboarding, with a pump paired or without both confirmations") func adoptionRefused() throws {
        let state = try pumpState("Medtrum")
        #expect(PumpAdoptionGate.check(
            managerState: state, isOnboarding: false, hasPairedPump: false, confirmations: confirmed
        ) == .notOnboarding)
        #expect(PumpAdoptionGate.check(
            managerState: state, isOnboarding: true, hasPairedPump: true, confirmations: confirmed
        ) == .pumpAlreadyPaired)
        for partial in [
            PumpAdoptionConfirmations(),
            PumpAdoptionConfirmations(oldPhoneStopped: true, adoptionAccepted: false),
            PumpAdoptionConfirmations(oldPhoneStopped: false, adoptionAccepted: true)
        ] {
            #expect(PumpAdoptionGate.check(
                managerState: state, isOnboarding: true, hasPairedPump: false, confirmations: partial
            ) == .missingConfirmation)
        }
        #expect(PumpAdoptionGate.check(
            managerState: "not base64", isOnboarding: true, hasPairedPump: false, confirmations: confirmed
        ) == .unreadableState)
    }

    @Test("Omnipod DASH, Dana and unknown pumps are never offered for adoption") func adoptionUnsupported() throws {
        let dash = try pumpState("Omni", state: ["podState": ["address": 1]])
        for state in [dash, try pumpState("Dana"), try pumpState("FuturePump")] {
            let refusal = PumpAdoptionGate.check(
                managerState: state, isOnboarding: true, hasPairedPump: false, confirmations: confirmed
            )
            guard case .unsupported = refusal else {
                Issue.record("Expected an unsupported pump, got \(String(describing: refusal))")
                continue
            }
        }
    }

    // MARK: - Choices

    @Test("Nothing protected is restored unless the user switches it on") func selectionDefaultsOff() {
        let model = SensitiveRestoreModel()
        model.tier = tier
        #expect(model.selection(allowsPairing: true, adoptionAccepted: true) == nil)
    }

    @Test("Credentials are restored by part and pairing only when allowed") func selectionParts() throws {
        let model = SensitiveRestoreModel()
        model.tier = tier
        model.restoreNightscout = true
        model.restorePumpPairing = true
        model.oldPhoneStopped = true
        let configured = try #require(model.selection(allowsPairing: false, adoptionAccepted: true))
        #expect(configured.credentials?.nightscoutURL == "https://example.nightscout.test")
        #expect(configured.credentials?.remoteControlSharedSecret == nil)
        #expect(configured.pumpState == nil && configured.cgmState == nil)
        let onboarding = try #require(model.selection(allowsPairing: true, adoptionAccepted: false))
        #expect(onboarding.pumpState != nil)
        #expect(!onboarding.pumpConfirmations.isComplete)
        #expect(try #require(model.selection(allowsPairing: true, adoptionAccepted: true)).pumpConfirmations.isComplete)
    }

    @Test("Unlocking stops after three wrong passphrases") func unlockAttempts() throws {
        let backup = try BackupSnapshotTests().makeBackup(BackupSnapshotTests().validConfiguration())
            .sealingSensitive(tier, passphrase: passphrase)
        let model = SensitiveRestoreModel()
        for _ in 0 ..< SensitiveRestoreModel.maximumAttempts {
            model.passphrase = "wrong passphrase"
            model.unlock(backup)
        }
        #expect(model.attemptsExhausted && model.tier == nil)
        model.passphrase = passphrase
        model.unlock(backup)
        #expect(model.tier == nil)
        model.reset()
        model.passphrase = passphrase
        model.unlock(backup)
        #expect(model.tier == tier)
        #expect(model.passphrase.isEmpty)
    }
}
