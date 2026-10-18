import CoreData
import Foundation
import Swinject

/// Reading and writing backup files. Pure functions, no dependencies on the running app.
enum BackupFileService {
    struct Opened {
        let snapshot: TrioSettingsBackup
        /// Parts of an older file that this version does not restore.
        let warnings: [String]
        /// Readable protected content of an older file; current files keep theirs sealed in the snapshot.
        var sensitive: SensitiveTier? = nil
    }

    /// Opens a backup file of any supported format. The format is detected from the file's top-level
    /// keys, never from its extension.
    static func open(_ bytes: Data) throws -> Opened {
        guard bytes.count <= TrioSettingsBackup.maximumFileSize else { throw BackupError.backupTooLarge }
        guard let raw = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let schema = raw["schemaVersion"] as? Int
        else { throw BackupError.unrecognizedFile }
        if LegacyBackupAdapter.isLegacy(raw) {
            let legacy = try JSONCoding.decoder.decode(SettingsBackup.self, from: bytes)
            let converted = try LegacyBackupAdapter.convert(legacy)
            return Opened(snapshot: converted.snapshot, warnings: converted.warnings, sensitive: converted.sensitive)
        }
        guard raw["configuration"] != nil else { throw BackupError.unrecognizedFile }
        guard schema <= TrioSettingsBackup.currentSchema else { throw BackupError.unsupportedSchema }
        let snapshot = try TrioSettingsBackup.decode(bytes, limit: TrioSettingsBackup.maximumFileSize)
        // Only a backup that carries treatment history may be larger than a plain configuration.
        if snapshot.treatmentHistory == nil, bytes.count > TrioSettingsBackup.maximumSize { throw BackupError.backupTooLarge }
        return Opened(snapshot: snapshot, warnings: [])
    }

    static func open(url: URL) throws -> Opened {
        try open(TrioSettingsBackup.readBackupData(from: url, limit: TrioSettingsBackup.maximumFileSize))
    }

    /// Writes the snapshot to a temporary file ready for the share sheet.
    static func export(_ candidate: TrioSettingsBackup) throws -> URL {
        let snapshot = try candidate.validated()
        let data = try JSONEncoder().encode(snapshot)
        guard data.count <= (snapshot.treatmentHistory == nil ? TrioSettingsBackup.maximumSize : TrioSettingsBackup.maximumFileSize)
        else { throw BackupError.backupTooLarge }
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

/// What the user opted to put into the protected tier of a new backup.
struct SensitiveExportOptions {
    var includeCredentials = false
    var includeDevices = false
    var passphrase = ""

    var includesAnything: Bool { includeCredentials || includeDevices }
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
    private var keychain: Keychain?

    var isReady: Bool { storage != nil && settingsManager != nil && deviceManager != nil }

    func start(resolver: Resolver) {
        storage = resolver.resolve(FileStorage.self)
        settingsManager = resolver.resolve(SettingsManager.self)
        deviceManager = resolver.resolve(DeviceDataManager.self)
        broadcaster = resolver.resolve(Broadcaster.self)
        fetchGlucoseManager = resolver.resolve(FetchGlucoseManager.self)
        keychain = resolver.resolve(Keychain.self)
    }

    var hasPairedPump: Bool { deviceManager?.pumpManager != nil }

    /// Captures the configuration and, when asked, seals the opt-in sign-in and pairing tier into it.
    func captureSnapshot(
        origin: TrioSettingsBackup.Origin,
        name: String? = nil,
        sensitive: SensitiveExportOptions?,
        includeHistory: Bool = false
    ) async throws -> TrioSettingsBackup {
        var snapshot = try await captureSnapshot(origin: origin, name: name)
        if includeHistory {
            snapshot = try snapshot.withTreatmentHistory(await SettingsBackupHistory.export())
        }
        guard let sensitive, sensitive.includesAnything else { return snapshot }
        return try snapshot.sealingSensitive(collectSensitiveTier(sensitive), passphrase: sensitive.passphrase)
    }

    func captureSnapshot(origin: TrioSettingsBackup.Origin, name: String? = nil) async throws -> TrioSettingsBackup {
        guard let storage else { throw BackupError.incompleteConfiguration }
        let settings = settingsManager?.settings
        let deviceInfo = TrioSettingsBackup.DeviceInfo(
            pumpType: deviceManager?.pumpManager?.localizedTitle,
            insulinType: deviceManager?.pumpManager?.status.insulinType?.title
                ?? settingsManager?.preferences.curve.rawValue,
            cgmDisplayName: settings?.cgm.displayName
        )
        var snapshot = try await TrioSettingsBackup.capture(storage: storage, origin: origin, name: name, deviceInfo: deviceInfo)
        let extensions = await BackupExtensionRegistry.captureAll()
        snapshot.extensions = extensions.isEmpty ? nil : extensions
        return snapshot
    }

    func exportBackupFile(sensitive: SensitiveExportOptions? = nil, includeHistory: Bool = false) async throws -> URL {
        guard !SettingsBackupRestore.isRestoring, !BackupActivity.isUploading else { throw BackupError.operationInProgress }
        return try BackupFileService.export(
            try await captureSnapshot(origin: .manual, sensitive: sensitive, includeHistory: includeHistory)
        )
    }

    /// Reads the opt-in tier from the keychain and the running managers. Nothing here is logged.
    func collectSensitiveTier(_ options: SensitiveExportOptions) -> SensitiveTier {
        var tier = SensitiveTier()
        if options.includeCredentials {
            var credentials = SensitiveTier.Credentials()
            credentials.nightscoutURL = keychain?.getValue(String.self, forKey: NightscoutConfig.Config.urlKey)
            credentials.nightscoutSecret = keychain?.getValue(String.self, forKey: NightscoutConfig.Config.secretKey)
            credentials.remoteControlSharedSecret = UserDefaults.standard.string(forKey: "trioRemoteControlSharedSecret")
            tier.credentials = credentials.isEmpty ? nil : credentials
        }
        if options.includeDevices {
            var devices = SensitiveTier.Devices()
            if let pumpManager = deviceManager?.pumpManager {
                devices.pumpState = SettingsBackup.encodeManagerState(pumpManager.rawValue)
            }
            // Some plugins (LibreTransmitter) keep their pairing outside the manager state and export an empty
            // dictionary. Skip those instead of promising a restorable pairing.
            if let cgmManager = fetchGlucoseManager?.cgmManager,
               (cgmManager.rawValue["state"] as? [String: Any])?.isEmpty == false
            {
                devices.cgmState = SettingsBackup.encodeManagerState(cgmManager.rawValue)
            }
            tier.devices = devices.isEmpty ? nil : devices
        }
        return tier
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

    @discardableResult func restoreConfiguredApp(
        _ backup: TrioSettingsBackup,
        sensitive: SensitiveSelection? = nil,
        restoreHistory: Bool = false
    ) async throws -> RestoreReport {
        guard let settingsManager, let deviceManager else { throw BackupError.restoreFailed }
        guard deviceManager.pumpManager == nil else { throw BackupError.pumpNotReady }
        var report = try await SettingsBackupRestore.applyConfigured(
            backup, settingsManager: settingsManager, deviceManager: deviceManager
        )
        notifyObservers()
        // The core restore has committed; the protected tier is a separate step whose failure only warns.
        if let sensitive { report.warnings += applySensitive(sensitive, onboarding: false) }
        report.warnings += await applyOptionalTiers(backup, restoreHistory: restoreHistory, onboarding: false)
        TrioCloudBackupCoordinator.shared.restoreCompleted()
        return report
    }

    @discardableResult func restoreDuringOnboarding(
        _ backup: TrioSettingsBackup,
        sensitive: SensitiveSelection? = nil,
        restoreHistory: Bool = false
    ) async throws -> RestoreReport {
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
        if let sensitive { report.warnings += applySensitive(sensitive, onboarding: true) }
        report.warnings += await applyOptionalTiers(backup, restoreHistory: restoreHistory, onboarding: true)
        return report
    }

    /// Treatment history (when chosen) and registered extensions, applied after the core restore committed.
    /// Failures are warnings; history is deduplicated by date so repeating a restore adds nothing.
    func applyOptionalTiers(_ backup: TrioSettingsBackup, restoreHistory: Bool, onboarding: Bool) async -> [String] {
        var warnings: [String] = []
        if restoreHistory {
            do {
                if let tier = try backup.historyTier() {
                    warnings += await SettingsBackupHistory.apply(tier)
                }
            } catch {
                warnings.append(String(localized: "Treatment history could not be read: \(error.localizedDescription)"))
            }
        }
        warnings += await BackupExtensionRegistry.restoreAll(
            backup.extensions,
            context: BackupExtensionRestoreContext(snapshotID: backup.id, isOnboarding: onboarding)
        )
        return warnings
    }

    /// Writes the chosen sign-in details, then adopts device pairing (onboarding only). Every failure is a
    /// warning: the core restore has already committed and is never rolled back for these.
    func applySensitive(_ selection: SensitiveSelection, onboarding: Bool) -> [String] {
        var warnings: [String] = []
        if let credentials = selection.credentials {
            warnings += applyCredentials(credentials)
        }
        guard onboarding else { return warnings }
        if let cgmState = selection.cgmState {
            warnings += adoptCGM(cgmState)
        }
        if let pumpState = selection.pumpState {
            warnings += adoptPump(pumpState, confirmations: selection.pumpConfirmations, onboarding: onboarding)
        }
        return warnings
    }

    private func applyCredentials(_ credentials: SensitiveTier.Credentials) -> [String] {
        var warnings: [String] = []
        if let url = credentials.nightscoutURL, url.isNotEmpty, let secret = credentials.nightscoutSecret {
            keychain?.setValue(url, forKey: NightscoutConfig.Config.urlKey)
            keychain?.setValue(secret, forKey: NightscoutConfig.Config.secretKey)
            if keychain?.getValue(String.self, forKey: NightscoutConfig.Config.urlKey) == url,
               keychain?.getValue(String.self, forKey: NightscoutConfig.Config.secretKey) == secret
            {
                warnings.append(
                    String(localized: "Nightscout sign-in restored. Check the connection under Settings > Services > Nightscout.")
                )
            } else {
                warnings.append(String(
                    localized: "Nightscout sign-in could not be saved to the keychain. Enter it again under Settings > Services > Nightscout."
                ))
            }
        }
        if let sharedSecret = credentials.remoteControlSharedSecret, sharedSecret.isNotEmpty {
            UserDefaults.standard.set(sharedSecret, forKey: "trioRemoteControlSharedSecret")
            warnings.append(String(
                localized: "Remote control secret restored. Remote commands stay off until you open Settings > Services > Remote Control."
            ))
        }
        return warnings
    }

    private func adoptCGM(_ base64: String) -> [String] {
        let failure = String(localized: "CGM pairing could not be restored. Add your CGM under Settings > Devices > CGM.")
        guard let settings = settingsManager?.settings, settings.cgm == .plugin,
              let rawValue = SettingsBackup.decodeManagerState(base64),
              fetchGlucoseManager?.adoptCGMManagerState(rawValue, cgmGlucosePluginId: settings.cgmPluginIdentifier) == true
        else { return [failure] }
        return [SettingsBackup.cgmPairingNote(forManagerState: base64)].compactMap { $0 }
    }

    private func adoptPump(_ base64: String, confirmations: PumpAdoptionConfirmations, onboarding: Bool) -> [String] {
        if let refusal = PumpAdoptionGate.check(
            managerState: base64,
            isOnboarding: onboarding && OnboardingManager.shared.shouldShowOnboarding,
            hasPairedPump: hasPairedPump,
            confirmations: confirmations
        ) {
            return [refusal.localizedDescription]
        }
        guard let rawValue = SettingsBackup.decodeManagerState(base64),
              deviceManager?.adoptPumpManager(fromRawValue: rawValue) == true
        else {
            return [String(localized: "Pump pairing could not be restored. Pair your pump under Settings > Devices > Insulin Pump.")]
        }
        // No pump command is sent here and Trio stays in Open Loop until the user switches it.
        return [
            String(localized: "Pump pairing restored. Trio stays in Open Loop. Check the pump status before returning to Closed Loop.")
        ] + [SettingsBackup.pumpPairingNote(forManagerState: base64)].compactMap { $0 }
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
