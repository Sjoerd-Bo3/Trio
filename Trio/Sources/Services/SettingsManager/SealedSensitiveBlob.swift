import CommonCrypto
import CryptoKit
import Foundation
import Security

/// Sign-in details and device pairing state. They only ever leave the phone sealed with a passphrase.
struct SensitiveTier: Codable, Equatable {
    var credentials: Credentials?
    var devices: Devices?

    struct Credentials: Codable, Equatable {
        var nightscoutURL: String?
        var nightscoutSecret: String?
        var remoteControlSharedSecret: String?

        var isEmpty: Bool {
            [nightscoutURL, nightscoutSecret, remoteControlSharedSecret].allSatisfy { ($0 ?? "").isEmpty }
        }
    }

    /// Raw pump and CGM manager state, each a base64-encoded binary property list.
    struct Devices: Codable, Equatable {
        var pumpState: String?
        var cgmState: String?

        var isEmpty: Bool { pumpState == nil && cgmState == nil }
    }

    var isEmpty: Bool { (credentials?.isEmpty ?? true) && (devices?.isEmpty ?? true) }

    /// Host name of the saved Nightscout site, for display. The secret is never shown.
    var nightscoutHost: String? {
        guard let text = credentials?.nightscoutURL, !text.isEmpty else { return nil }
        return URL(string: text)?.host ?? text
    }
}

/// A passphrase-sealed container: PBKDF2-HMAC-SHA256 stretches the passphrase into an AES-256 key and AES-GCM
/// seals the payload. The header (algorithm names, iteration count, salt) and the identity of the backup the
/// blob belongs to are authenticated, so neither can be altered or moved to another backup unnoticed.
struct SealedSensitiveBlob: Codable, Equatable {
    struct Header: Codable, Equatable {
        var version = 1
        var kdf = "PBKDF2-HMAC-SHA256"
        var iterations: Int
        var salt: Data
        var cipher = "AES-256-GCM"
    }

    let header: Header
    /// AES-GCM combined form: nonce, ciphertext and tag.
    let sealed: Data

    static let defaultIterations = 600_000
    static let minimumIterations = 200_000
    /// A hostile file must not be able to make unlocking run for hours.
    static let maximumIterations = 5_000_000
    static let saltLength = 16
    static let minimumPassphraseLength = 8

    enum SealError: LocalizedError, Equatable {
        case passphraseTooShort
        case unsupportedFormat
        case wrongPassphraseOrDamaged
        case keyDerivationFailed

        var errorDescription: String? {
            switch self {
            case .passphraseTooShort:
                return String(localized: "Use a passphrase with at least 8 characters.")
            case .unsupportedFormat:
                return String(localized: "This backup protects its sign-in details in a way this version of Trio cannot open.")
            case .wrongPassphraseOrDamaged:
                return String(localized: "The passphrase is wrong, or the protected part of this backup is damaged.")
            case .keyDerivationFailed:
                return String(localized: "The passphrase could not be processed.")
            }
        }
    }

    static func seal<Value: Encodable>(
        _ value: Value,
        passphrase: String,
        binding context: Data,
        iterations: Int = defaultIterations
    ) throws -> SealedSensitiveBlob {
        guard passphrase.count >= minimumPassphraseLength else { throw SealError.passphraseTooShort }
        guard (minimumIterations ... maximumIterations).contains(iterations) else { throw SealError.unsupportedFormat }
        let header = try Header(iterations: iterations, salt: randomBytes(saltLength))
        let key = try deriveKey(passphrase: passphrase, salt: header.salt, iterations: iterations)
        let box = try AES.GCM.seal(
            JSONEncoder().encode(value),
            using: key,
            authenticating: authenticatedData(header: header, context: context)
        )
        guard let combined = box.combined else { throw SealError.unsupportedFormat }
        return SealedSensitiveBlob(header: header, sealed: combined)
    }

    func open<Value: Decodable>(_: Value.Type, passphrase: String, binding context: Data) throws -> Value {
        guard header.version == 1, header.kdf == "PBKDF2-HMAC-SHA256", header.cipher == "AES-256-GCM",
              header.salt.count == Self.saltLength,
              (Self.minimumIterations ... Self.maximumIterations).contains(header.iterations)
        else { throw SealError.unsupportedFormat }
        let key = try Self.deriveKey(passphrase: passphrase, salt: header.salt, iterations: header.iterations)
        do {
            let box = try AES.GCM.SealedBox(combined: sealed)
            let plain = try AES.GCM.open(box, using: key, authenticating: Self.authenticatedData(header: header, context: context))
            return try JSONDecoder().decode(Value.self, from: plain)
        } catch {
            throw SealError.wrongPassphraseOrDamaged
        }
    }

    private static func authenticatedData(header: Header, context: Data) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(header) + context
    }

    static func deriveKey(passphrase: String, salt: Data, iterations: Int) throws -> SymmetricKey {
        // The same passphrase must work whichever Unicode form the keyboard produced.
        let password = Array(passphrase.precomposedStringWithCanonicalMapping.utf8)
        guard !password.isEmpty else { throw SealError.passphraseTooShort }
        var derived = [UInt8](repeating: 0, count: 32)
        let status = password.withUnsafeBufferPointer { passwordBytes in
            salt.withUnsafeBytes { saltBytes in
                derived.withUnsafeMutableBufferPointer { output in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        UnsafeRawPointer(passwordBytes.baseAddress!).assumingMemoryBound(to: Int8.self),
                        passwordBytes.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress!,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        output.baseAddress!,
                        output.count
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw SealError.keyDerivationFailed }
        return SymmetricKey(data: derived)
    }

    private static func randomBytes(_ count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else {
            throw SealError.keyDerivationFailed
        }
        return Data(bytes)
    }
}

extension TrioSettingsBackup {
    /// The data a sealed tier is bound to, so a blob cannot be moved into a different backup.
    var sensitiveBindingContext: Data { Data(id.uuidString.utf8) }

    func sealingSensitive(_ tier: SensitiveTier, passphrase: String) throws -> TrioSettingsBackup {
        var result = self
        result.sensitive = try tier.isEmpty ? nil : SealedSensitiveBlob.seal(
            tier, passphrase: passphrase, binding: sensitiveBindingContext
        )
        return result
    }

    func unlockSensitive(passphrase: String) throws -> SensitiveTier? {
        try sensitive?.open(SensitiveTier.self, passphrase: passphrase, binding: sensitiveBindingContext)
    }
}
