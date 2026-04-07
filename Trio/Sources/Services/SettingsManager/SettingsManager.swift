import Foundation
import LoopKit
import Swinject

protocol SettingsManager: AnyObject {
    var settings: TrioSettings { get set }
    var preferences: Preferences { get set }
    var pumpSettings: PumpSettings { get }
    func updateInsulinCurve(_ insulinType: InsulinType?)
}

protocol SettingsObserver {
    func settingsDidChange(_: TrioSettings)
}

protocol PreferencesObserver {
    func preferencesDidChange(_: Preferences)
}

final class BaseSettingsManager: SettingsManager, Injectable {
    @Injected() var broadcaster: Broadcaster!
    @Injected() var storage: FileStorage!
    @Injected() var auditStorage: SettingsAuditStorage!

    @SyncAccess var settings: TrioSettings {
        didSet {
            if oldValue != settings {
                logSettingsChanges(old: oldValue, new: settings)
                saveSettings()
                DispatchQueue.main.async {
                    self.broadcaster.notify(SettingsObserver.self, on: .main) {
                        $0.settingsDidChange(self.settings)
                    }
                }
            }
        }
    }

    @SyncAccess var preferences: Preferences {
        didSet {
            if oldValue != preferences {
                logPreferencesChanges(old: oldValue, new: preferences)
                savePreferences()
                DispatchQueue.main.async {
                    self.broadcaster.notify(PreferencesObserver.self, on: .main) {
                        $0.preferencesDidChange(self.preferences)
                    }
                }
            }
        }
    }

    private func saveSettings() {
        storage.save(settings, as: OpenAPS.Trio.settings)
    }

    private func savePreferences() {
        storage.save(preferences, as: OpenAPS.Settings.preferences)
    }

    init(resolver: Resolver) {
        let storage = resolver.resolve(FileStorage.self)!
        settings = storage.retrieve(OpenAPS.Trio.settings, as: TrioSettings.self)
            ?? TrioSettings(from: OpenAPS.defaults(for: OpenAPS.Trio.settings))
            ?? TrioSettings()

        preferences =
            storage.retrieve(OpenAPS.Settings.preferences, as: Preferences.self)
                ?? Preferences(from: OpenAPS.defaults(for: OpenAPS.Settings.preferences))
                ?? Preferences()

        injectServices(resolver)
    }

    var pumpSettings: PumpSettings {
        storage.retrieve(OpenAPS.Settings.settings, as: PumpSettings.self)
            ?? PumpSettings(from: OpenAPS.defaults(for: OpenAPS.Settings.settings))
            ?? PumpSettings(insulinActionCurve: 10, maxBolus: 10, maxBasal: 2)
    }

    func updateInsulinCurve(_ insulinType: InsulinType?) {
        var prefs = preferences

        switch insulinType {
        case .apidra,
             .humalog,
             .novolog:
            prefs.curve = .rapidActing

        case .fiasp,
             .lyumjev:
            prefs.curve = .ultraRapid
        default:
            prefs.curve = .rapidActing
        }

        preferences = prefs
        savePreferences()
    }

    // MARK: - Change capture helpers

    private func logMirrorChanges<T>(
        old: T,
        new: T,
        registryMap: [String: SettingMetadata],
        keyPrefix: String,
        fallbackCategory: String
    ) {
        let mirror = Mirror(reflecting: new)
        let oldMirror = Mirror(reflecting: old)

        let oldDict = Dictionary(uniqueKeysWithValues: oldMirror.children.compactMap { child -> (String, String)? in
            guard let label = child.label else { return nil }
            return (label, "\(child.value)")
        })

        for child in mirror.children {
            guard let label = child.label else { continue }
            let newVal = "\(child.value)"
            let oldVal = oldDict[label] ?? ""
            guard oldVal != newVal else { continue }

            let meta = registryMap[label]
            auditStorage.logChange(
                category: meta?.category ?? fallbackCategory,
                subcategory: meta?.subcategory ?? "General",
                settingName: meta?.name ?? label,
                settingKey: "\(keyPrefix).\(label)",
                oldValue: oldVal,
                newValue: newVal,
                unit: meta?.unit,
                note: nil,
                source: "manual"
            )
        }
    }

    private func logSettingsChanges(old: TrioSettings, new: TrioSettings) {
        logMirrorChanges(
            old: old,
            new: new,
            registryMap: SettingsMetadataRegistry.trioSettingsMap,
            keyPrefix: "settings",
            fallbackCategory: "Settings"
        )
    }

    private func logPreferencesChanges(old: Preferences, new: Preferences) {
        logMirrorChanges(
            old: old,
            new: new,
            registryMap: SettingsMetadataRegistry.preferencesMap,
            keyPrefix: "preferences",
            fallbackCategory: "Algorithm"
        )
    }
}
