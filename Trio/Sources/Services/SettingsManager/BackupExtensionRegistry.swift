import Foundation

/// What an extension is told when its saved data is restored.
struct BackupExtensionRestoreContext {
    let snapshotID: UUID
    let isOnboarding: Bool
}

/// A part of a backup that lives outside the core configuration, supplied by a feature of its own.
/// Its data is opaque to the backup: stored under the provider's id, handed back on restore.
protocol BackupExtensionProvider {
    /// Stable key the provider's data is stored under in the snapshot. Never change it once shipped.
    var id: String { get }
    func capture() async -> Data?
    /// Applies the saved data. Runs after the core restore has committed; a failure is reported as a warning.
    func restore(_ data: Data, context: BackupExtensionRestoreContext) async throws
    /// Rows for the change overview.
    func preview(_ data: Data) -> [ImportChange]
}

/// The extension point for additional backup content. It ships without providers; a feature registers one
/// at startup to have its data saved in and restored from backups.
enum BackupExtensionRegistry {
    /// An extension's data may not take more than this much of a backup.
    static let maximumDataSize = 1_000_000

    private static let lock = NSLock()
    private static var registered: [BackupExtensionProvider] = []

    static var providers: [BackupExtensionProvider] {
        lock.lock()
        defer { lock.unlock() }
        return registered
    }

    /// Registering a provider again with the same id replaces the earlier one.
    static func register(_ provider: BackupExtensionProvider) {
        lock.lock()
        defer { lock.unlock() }
        registered.removeAll { $0.id == provider.id }
        registered.append(provider)
    }

    static func unregisterAll() {
        lock.lock()
        defer { lock.unlock() }
        registered.removeAll()
    }

    /// Data of every provider that has something to save and stays within the size limit.
    static func captureAll() async -> [String: Data] {
        var result: [String: Data] = [:]
        for provider in providers {
            if let data = await provider.capture(), !data.isEmpty, data.count <= maximumDataSize {
                result[provider.id] = data
            }
        }
        return result
    }

    /// Restores each saved extension that has a registered provider. Never throws: every failure is a
    /// warning, and data without a provider is ignored.
    static func restoreAll(_ saved: [String: Data]?, context: BackupExtensionRestoreContext) async -> [String] {
        guard let saved, !saved.isEmpty else { return [] }
        var warnings: [String] = []
        for provider in providers {
            guard let data = saved[provider.id], data.count <= maximumDataSize else { continue }
            do {
                try await provider.restore(data, context: context)
            } catch {
                warnings.append(
                    String(localized: "Could not restore \(provider.id): \(error.localizedDescription)")
                )
            }
        }
        return warnings
    }

    static func preview(_ saved: [String: Data]?) -> [ImportChange] {
        guard let saved else { return [] }
        return providers.flatMap { provider in
            saved[provider.id].map { provider.preview($0) } ?? []
        }
    }
}
