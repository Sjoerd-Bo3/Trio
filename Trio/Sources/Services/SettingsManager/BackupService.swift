import CoreData
import Foundation
import Swinject

/// Reading and writing backup files. Pure functions, no dependencies on the running app.
enum BackupFileService {
    struct Opened {
        let snapshot: TrioSettingsBackup
        /// Parts of an older file that this version does not restore.
        let warnings: [String]
    }

    /// Opens a backup file of any supported format. The format is detected from the file's top-level
    /// keys, never from its extension.
    static func open(_ bytes: Data) throws -> Opened {
        guard bytes.count <= TrioSettingsBackup.maximumSize else { throw BackupError.backupTooLarge }
        guard let raw = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let schema = raw["schemaVersion"] as? Int
        else { throw BackupError.unrecognizedFile }
        if LegacyBackupAdapter.isLegacy(raw) {
            let legacy = try JSONCoding.decoder.decode(SettingsBackup.self, from: bytes)
            let converted = try LegacyBackupAdapter.convert(legacy)
            return Opened(snapshot: converted.snapshot, warnings: converted.warnings)
        }
        guard raw["configuration"] != nil else { throw BackupError.unrecognizedFile }
        guard schema <= TrioSettingsBackup.currentSchema else { throw BackupError.unsupportedSchema }
        return Opened(snapshot: try TrioSettingsBackup.decode(bytes), warnings: [])
    }

    static func open(url: URL) throws -> Opened {
        try open(TrioSettingsBackup.readBackupData(from: url))
    }

    /// Writes the snapshot to a temporary file ready for the share sheet.
    static func export(_ candidate: TrioSettingsBackup) throws -> URL {
        let snapshot = try candidate.validated()
        let data = try JSONEncoder().encode(snapshot)
        guard data.count <= TrioSettingsBackup.maximumSize else { throw BackupError.backupTooLarge }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrioSettings_\(formatter.string(from: snapshot.createdAt)).json")
        try TherapyFileWriter.write(data, to: url)
        return url
    }
}

/// One backup as listed in the Backup & Restore screens.
struct BackupEntry: Identifiable {
    let id: String
    let createdAt: Date
    let origin: TrioSettingsBackup.Origin
    var name: String?
    let fingerprint: String
    var appVersion: String? = nil
    var schemaVersion: Int? = nil
    var validationMessage: String? = nil
}

/// Captures, exports and restores backups using the running app's services.
@MainActor final class BackupService {
    static let shared = BackupService()

    private var storage: FileStorage?
    private var settingsManager: SettingsManager?
    private var deviceManager: DeviceDataManager?
    private var broadcaster: Broadcaster?
    private var fetchGlucoseManager: FetchGlucoseManager?

    var isReady: Bool { storage != nil && settingsManager != nil && deviceManager != nil }

    func start(resolver: Resolver) {
        storage = resolver.resolve(FileStorage.self)
        settingsManager = resolver.resolve(SettingsManager.self)
        deviceManager = resolver.resolve(DeviceDataManager.self)
        broadcaster = resolver.resolve(Broadcaster.self)
        fetchGlucoseManager = resolver.resolve(FetchGlucoseManager.self)
    }

    var hasPairedPump: Bool { deviceManager?.pumpManager != nil }

    func captureSnapshot(origin: TrioSettingsBackup.Origin, name: String? = nil) async throws -> TrioSettingsBackup {
        guard let storage else { throw BackupError.incompleteConfiguration }
        let settings = settingsManager?.settings
        let deviceInfo = TrioSettingsBackup.DeviceInfo(
            pumpType: deviceManager?.pumpManager?.localizedTitle,
            insulinType: deviceManager?.pumpManager?.status.insulinType?.title
                ?? settingsManager?.preferences.curve.rawValue,
            cgmDisplayName: settings?.cgm.displayName
        )
        return try await TrioSettingsBackup.capture(storage: storage, origin: origin, name: name, deviceInfo: deviceInfo)
    }

    func exportBackupFile() async throws -> URL {
        guard !SettingsBackupRestore.isRestoring, !BackupActivity.isUploading else { throw BackupError.operationInProgress }
        return try BackupFileService.export(try await captureSnapshot(origin: .manual))
    }

    /// The device's current configuration, for the change overview.
    func currentState() async -> BackupCurrentState? {
        guard let storage, let settingsManager else { return nil }
        let presets = (try? await TrioSettingsBackup.readPresets())
            ?? TrioSettingsBackup.Presets(overrides: [], tempTargets: [], meals: [])
        return BackupCurrentState(
            settings: settingsManager.settings,
            preferences: settingsManager.preferences,
            pumpSettings: settingsManager.pumpSettings,
            basalProfile: storage.retrieve(OpenAPS.Settings.basalProfile, as: [BasalProfileEntry].self) ?? [],
            carbRatios: storage.retrieve(OpenAPS.Settings.carbRatios, as: CarbRatios.self),
            insulinSensitivities: storage.retrieve(OpenAPS.Settings.insulinSensitivities, as: InsulinSensitivities.self),
            glucoseTargets: storage.retrieve(OpenAPS.Settings.bgTargets, as: BGTargets.self),
            presets: presets
        )
    }

    /// What restoring `backup` would change, computed from the same preparation the restore uses.
    func changeOverview(for backup: TrioSettingsBackup, onboarding: Bool) async -> ImportChangeSet? {
        guard let state = await currentState(),
              let prepared = try? SettingsBackupRestore.prepare(
                  backup,
                  currentSettings: state.settings,
                  currentPreferences: state.preferences,
                  onboarding: onboarding,
                  supportedBasalRates: nil
              )
        else { return nil }
        return SettingsImportApplier.changeSet(restoring: prepared.configuration, current: state)
    }

    @discardableResult func restoreConfiguredApp(_ backup: TrioSettingsBackup) async throws -> RestoreReport {
        guard let settingsManager, let deviceManager else { throw BackupError.restoreFailed }
        guard deviceManager.pumpManager == nil else { throw BackupError.pumpNotReady }
        let report = try await SettingsBackupRestore.applyConfigured(
            backup, settingsManager: settingsManager, deviceManager: deviceManager
        )
        notifyObservers()
        return report
    }

    @discardableResult func restoreDuringOnboarding(_ backup: TrioSettingsBackup) async throws -> RestoreReport {
        guard let settingsManager, let deviceManager else { throw BackupError.restoreFailed }
        guard deviceManager.pumpManager == nil else { throw BackupError.pumpNotReady }
        let previous = settingsManager.settings
        var report = try await SettingsBackupRestore.applyDuringOnboarding(
            backup, settingsManager: settingsManager, deviceManager: deviceManager
        )
        notifyObservers()
        // The running glucose source only follows the CGM selection when told to. Pairing never travels in
        // the core snapshot, so a restored plugin CGM still has to be set up on this phone.
        let restored = settingsManager.settings
        if restored.cgm != previous.cgm || restored.cgmPluginIdentifier != previous.cgmPluginIdentifier {
            fetchGlucoseManager?.updateGlucoseSource(
                cgmGlucoseSourceType: restored.cgm,
                cgmGlucosePluginId: restored.cgmPluginIdentifier
            )
            if restored.cgm == .plugin {
                let name = backup.deviceInfo?.cgmDisplayName ?? restored.cgmPluginIdentifier
                report.warnings.append(
                    String(localized: "The backup used the CGM \"\(name)\". Set it up again under Settings > Devices > CGM.")
                )
            }
        }
        return report
    }

    /// Lets screens that cache therapy files reload them after a restore.
    private func notifyObservers() {
        guard let storage, let settingsManager else { return }
        if let basal = storage.retrieve(OpenAPS.Settings.basalProfile, as: [BasalProfileEntry].self) {
            broadcaster?.notify(BasalProfileObserver.self, on: .main) { $0.basalProfileDidChange(basal) }
        }
        if let targets = storage.retrieve(OpenAPS.Settings.bgTargets, as: BGTargets.self) {
            broadcaster?.notify(BGTargetsObserver.self, on: .main) { $0.bgTargetsDidChange(targets) }
        }
        if let sensitivities = storage.retrieve(OpenAPS.Settings.insulinSensitivities, as: InsulinSensitivities.self) {
            broadcaster?.notify(InsulinSensitivitiesObserver.self, on: .main) { $0.insulinSensitivitiesDidChange(sensitivities) }
        }
        if let carbRatios = storage.retrieve(OpenAPS.Settings.carbRatios, as: CarbRatios.self) {
            broadcaster?.notify(CarbRatiosObserver.self, on: .main) { $0.carbRatiosDidChange(carbRatios) }
        }
        let pumpSettings = settingsManager.pumpSettings
        broadcaster?.notify(PumpSettingsObserver.self, on: .main) { $0.pumpSettingsDidChange(pumpSettings) }
    }
}
