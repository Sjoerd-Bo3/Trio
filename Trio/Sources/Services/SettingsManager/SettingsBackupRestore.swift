import CoreData
import CryptoKit
import Foundation

/// Mutual exclusion between a restore and any backup upload that runs on its own schedule.
enum BackupActivity {
    @MainActor static var isUploading = false
}

/// Single choke point for every write that touches therapy files or the restore journal.
/// These files must be written exactly the way `FileStorage` writes them (atomic, default file
/// protection): a stronger class makes them unreadable while the phone is locked, and the loop
/// would then silently fall back to bundled defaults.
enum TherapyFileWriter {
    static let options: Data.WritingOptions = [.atomic]

    static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: options)
    }
}

/// What the startup recovery found. Recovery never throws; the caller always continues loading services.
enum RestoreRecoveryOutcome: Equatable {
    case none
    case rolledBack
    case needsAttention(String)
}

/// What a finished restore reports back to the UI.
struct RestoreReport {
    /// Values the guardrails clamped or snapped, plus other non-fatal notes.
    var warnings: [String] = []
}

/// Restore settings and Dynamic ISF history only while no pump is paired.
/// A rollback journal protects settings files, presets and history across a crash.
enum SettingsBackupRestore {
    @MainActor private static var restoring = false
    @MainActor static var isRestoring: Bool { restoring }
    static let pumpRecoveryKey = "trio.backupRestore.pumpReconciliationPending"
    /// Set after a restore until the user has looked at the restored settings.
    static let reviewPendingKey = "trio.backupRestore.reviewPending"
    /// Holds the reason when startup recovery could not finish; cleared when the user dismisses the notice.
    static let needsAttentionKey = "trio.backupRestore.needsAttention"
    static let rollbackFileName = ".trio-backup-rollback.json"
    static let journalFileName = ".trio-backup-restore-journal.json"
    static let names = [
        OpenAPS.Trio.settings, OpenAPS.Settings.preferences,
        OpenAPS.Settings.settings, OpenAPS.Settings.basalProfile,
        OpenAPS.Settings.carbRatios, OpenAPS.Settings.insulinSensitivities,
        OpenAPS.Settings.bgTargets
    ]

    static func configurationFiles(_ value: TrioSettingsBackup.Configuration) throws -> [(String, Data)] {
        try [
            (OpenAPS.Trio.settings, JSONCoding.encoder.encode(value.settings)),
            (OpenAPS.Settings.preferences, JSONCoding.encoder.encode(value.preferences)),
            (OpenAPS.Settings.settings, JSONCoding.encoder.encode(value.pumpSettings)),
            (OpenAPS.Settings.basalProfile, JSONCoding.encoder.encode(value.basalProfile)),
            (OpenAPS.Settings.carbRatios, JSONCoding.encoder.encode(value.carbRatios)),
            (OpenAPS.Settings.insulinSensitivities, JSONCoding.encoder.encode(value.insulinSensitivities)),
            (OpenAPS.Settings.bgTargets, JSONCoding.encoder.encode(value.glucoseTargets))
        ]
    }

    struct PreviousFile: Codable {
        let name: String
        let contents: Data?
    }

    struct Journal: Codable {
        let files: [PreviousFile]
        let presets: TrioSettingsBackup.Presets
        var defaults: [String: Data]? = nil
        var checksum: String? = nil
        var insertedTDDIDs: [UUID]? = nil
        var requiresPumpReconciliation: Bool? = nil

        private func digest() throws -> String {
            var unsigned = self
            unsigned.checksum = nil
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return SHA256.hash(data: try encoder.encode(unsigned)).map { String(format: "%02x", $0) }.joined()
        }

        func sealed() throws -> Self {
            var value = self
            value.checksum = try digest()
            return value
        }

        func verify() throws {
            // Older in-progress journals were written without a checksum.
            if let checksum, checksum != (try digest()) { throw BackupError.integrityCheckFailed }
        }
    }

    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// True while a journal from an interrupted restore is still on disk.
    static var hasUnresolvedJournal: Bool {
        FileManager.default.fileExists(atPath: documents.appendingPathComponent(journalFileName).path)
    }

    @MainActor static func applyDuringOnboarding(
        _ candidate: TrioSettingsBackup,
        settingsManager: SettingsManager,
        deviceManager: DeviceDataManager
    ) async throws -> RestoreReport {
        guard OnboardingManager.shared.shouldShowOnboarding else { throw BackupError.notOnboarding }
        return try await apply(
            candidate,
            settingsManager: settingsManager,
            hasPairedPump: { deviceManager.pumpManager != nil },
            supportedBasalRates: nil,
            onboarding: true
        )
    }

    @MainActor static func applyConfigured(
        _ candidate: TrioSettingsBackup,
        settingsManager: SettingsManager,
        deviceManager: DeviceDataManager
    ) async throws -> RestoreReport {
        guard !OnboardingManager.shared.shouldShowOnboarding else { throw BackupError.notOnboarding }
        return try await apply(
            candidate,
            settingsManager: settingsManager,
            hasPairedPump: { deviceManager.pumpManager != nil },
            supportedBasalRates: nil,
            onboarding: false
        )
    }

    /// The restore itself. Everything that can refuse a restore happens before the journal exists
    /// and leaves settings, preferences and alert stores untouched; only a failure after the journal
    /// was created runs the rollback.
    @MainActor static func apply(
        _ candidate: TrioSettingsBackup,
        settingsManager: SettingsManager,
        hasPairedPump: @escaping () -> Bool,
        supportedBasalRates: [Decimal]?,
        onboarding: Bool,
        isOnboarding: @escaping () -> Bool = { OnboardingManager.shared.shouldShowOnboarding },
        directory: URL? = nil,
        context: NSManagedObjectContext? = nil,
        defaults: UserDefaults = .standard,
        phase: @escaping (Phase) throws -> Void = { _ in }
    ) async throws -> RestoreReport {
        // Restoration requires an unpaired pump and must never mutate pump hardware.
        guard !hasPairedPump() else { throw BackupError.pumpNotReady }
        guard !restoring, !BackupActivity.isUploading else {
            throw BackupError.operationInProgress
        }
        let documents = directory ?? Self.documents
        let journalURL = documents.appendingPathComponent(journalFileName)
        guard !FileManager.default.fileExists(atPath: journalURL.path) else { throw BackupError.unresolvedRestore }
        restoring = true
        defer { restoring = false }
        let previousSettings = settingsManager.settings
        let previousPreferences = settingsManager.preferences
        let prepared = try prepare(
            candidate,
            currentSettings: previousSettings,
            currentPreferences: previousPreferences,
            onboarding: onboarding,
            supportedBasalRates: supportedBasalRates
        )
        let snapshot = prepared.snapshot
        let safe = prepared.configuration
        var journalCreated = false
        do {
            try await performTransaction(
                newFiles: configurationFiles(safe),
                presets: safe.presets,
                directory: documents,
                context: context,
                defaults: defaults,
                tddHistory: snapshot.eligibleTDDHistory(),
                preflight: {
                    guard !hasPairedPump() else { throw BackupError.pumpNotReady }
                    if onboarding && !isOnboarding() {
                        throw BackupError.notOnboarding
                    }
                },
                prepareHardware: {
                    // Never reactivate delivery. Open Loop is persisted first.
                    settingsManager.settings = try persistOpenLoop(previousSettings, directory: documents)
                },
                synchronizeCache: {
                    try safe.appConfiguration?.apply(defaults: defaults)
                    settingsManager.settings = safe.settings
                    settingsManager.preferences = safe.preferences
                },
                verifyConfiguration: {
                    guard !hasPairedPump(),
                          settingsManager.settings == safe.settings
                    else { throw BackupError.restoreFailed }
                    if let app = safe.appConfiguration {
                        guard try canonical(app) == canonical(TrioSettingsBackup.AppConfiguration.capture(defaults: defaults))
                        else { throw BackupError.restoreFailed }
                    }
                },
                phase: { step in
                    if step == .journalWritten { journalCreated = true }
                    try phase(step)
                }
            )
            if context == nil { await CoreDataStack.shared.fetchPersistentHistory() }
            defaults.set(true, forKey: reviewPendingKey)
            return RestoreReport(warnings: prepared.warnings)
        } catch {
            // A refusal before the journal exists changed nothing, so there is nothing to undo.
            guard journalCreated || FileManager.default.fileExists(atPath: journalURL.path) else { throw error }
            do {
                try await recoverInterruptedRestoreIfNeeded(directory: documents, context: context, defaults: defaults)
                settingsManager.settings = try persistOpenLoop(previousSettings, directory: documents)
                settingsManager.preferences = previousPreferences
                GlucoseAlertsStore.shared.reloadSavedConfiguration()
                DeviceAlertsStore.shared.reloadSavedConfiguration()
            } catch { throw BackupError.restoreFailed }
            throw error
        }
    }

    /// Validates a snapshot and derives the configuration a restore would write: normalized, forced to
    /// Open Loop, with this phone's connections kept (configured app) and guardrails applied. The
    /// restore and the change overview both start here, so they always agree.
    static func prepare(
        _ candidate: TrioSettingsBackup,
        currentSettings: TrioSettings,
        currentPreferences: Preferences,
        onboarding: Bool,
        supportedBasalRates: [Decimal]?
    ) throws -> (snapshot: TrioSettingsBackup, configuration: TrioSettingsBackup.Configuration, warnings: [String]) {
        let snapshot = try candidate.validated()
        let proposed = try TrioSettingsBackup.normalized(snapshot.configuration)
        let prepared = onboarding
            ? try onboardingConfiguration(proposed)
            : configuredConfiguration(proposed, currentSettings: currentSettings, currentPreferences: currentPreferences)
        let guarded = SettingsImportApplier.applyGuardrails(to: prepared, supportedBasalRates: supportedBasalRates)
        try TrioSettingsBackup.validate(guarded.configuration)
        return (snapshot, guarded.configuration, guarded.warnings)
    }

    /// Fresh installations may not have created the nested settings directory yet.
    static func persistOpenLoop(_ source: TrioSettings, directory: URL? = nil) throws -> TrioSettings {
        var settings = source
        settings.dosingMode = .open
        let url = (directory ?? documents).appendingPathComponent(OpenAPS.Trio.settings)
        try TherapyFileWriter.write(JSONCoding.encoder.encode(settings), to: url)
        return settings
    }

    static func configuredConfiguration(
        _ source: TrioSettingsBackup.Configuration,
        currentSettings: TrioSettings,
        currentPreferences: Preferences
    ) -> TrioSettingsBackup.Configuration {
        var result = source
        result.settings.dosingMode = .open
        // Connections belong to this phone, so the device keeps its own.
        result.settings.cgm = currentSettings.cgm
        result.settings.cgmPluginIdentifier = currentSettings.cgmPluginIdentifier
        result.settings.isUploadEnabled = currentSettings.isUploadEnabled
        result.settings.isDownloadEnabled = currentSettings.isDownloadEnabled
        result.settings.useLocalGlucoseSource = currentSettings.useLocalGlucoseSource
        result.preferences.bolusIncrement = currentPreferences.bolusIncrement
        return result
    }

    static func onboardingConfiguration(_ source: TrioSettingsBackup.Configuration) throws -> TrioSettingsBackup.Configuration {
        var result = try TrioSettingsBackup.normalized(source)
        result.settings.dosingMode = .open
        return result
    }

    // MARK: - Startup recovery

    /// Runs the interrupted-restore recovery without ever throwing, so a damaged journal cannot keep
    /// Trio from starting. On failure the loop is forced to Open Loop on a best-effort basis and the
    /// reason is stored for the "needs attention" notice.
    static func recoverAtStartup(
        directory: URL? = nil,
        context: NSManagedObjectContext? = nil,
        defaults: UserDefaults = .standard
    ) async -> RestoreRecoveryOutcome {
        let documents = directory ?? Self.documents
        guard FileManager.default.fileExists(atPath: documents.appendingPathComponent(journalFileName).path) else {
            return .none
        }
        do {
            try await recoverInterruptedRestoreIfNeeded(directory: documents, context: context, defaults: defaults)
            defaults.set(true, forKey: reviewPendingKey)
            return .rolledBack
        } catch {
            debug(.default, "Interrupted settings restore could not be recovered: \(error)")
            forceOpenLoopBestEffort(directory: documents)
            let reason = error.localizedDescription
            defaults.set(reason, forKey: needsAttentionKey)
            return .needsAttention(reason)
        }
    }

    /// Rewrites the stored settings with Open Loop if they can be read; never throws.
    static func forceOpenLoopBestEffort(directory: URL? = nil) {
        let url = (directory ?? documents).appendingPathComponent(OpenAPS.Trio.settings)
        guard let data = try? Data(contentsOf: url),
              let settings = try? JSONCoding.decoder.decode(TrioSettings.self, from: data),
              settings.dosingMode != .open else { return }
        _ = try? persistOpenLoop(settings, directory: directory)
    }
}
