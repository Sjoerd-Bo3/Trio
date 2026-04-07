import Foundation
import Swinject

extension TargetsEditor {
    final class Provider: BaseProvider, TargetsEditorProvider {
        @Injected() private var auditStorage: SettingsAuditStorage!

        var profile: BGTargets {
            var retrievedTargets = storage.retrieve(OpenAPS.Settings.bgTargets, as: BGTargets.self)
                ?? BGTargets(from: OpenAPS.defaults(for: OpenAPS.Settings.bgTargets))
                ?? BGTargets(units: .mgdL, userPreferredUnits: .mgdL, targets: [])

            // migrate existing mmol/L Trio users from mmol/L settings to pure mg/dl settings
            if retrievedTargets.units == .mmolL || retrievedTargets.userPreferredUnits == .mmolL {
                let convertedTargets = retrievedTargets.targets.map { target in
                    BGTargetEntry(
                        low: storage.parseSettingIfMmolL(value: target.low),
                        high: storage.parseSettingIfMmolL(value: target.high),
                        start: target.start,
                        offset: target.offset
                    )
                }
                retrievedTargets = BGTargets(units: .mgdL, userPreferredUnits: .mgdL, targets: convertedTargets)
                saveProfile(retrievedTargets)
            }

            return retrievedTargets
        }

        func saveProfile(_ profile: BGTargets) {
            let old = storage.retrieve(OpenAPS.Settings.bgTargets, as: BGTargets.self)
                ?? BGTargets(units: .mgdL, userPreferredUnits: .mgdL, targets: [])
            storage.save(profile, as: OpenAPS.Settings.bgTargets)
            logTargetsChange(old: old, new: profile)
        }

        private func logTargetsChange(old: BGTargets, new: BGTargets) {
            let oldStr = old.targets.map { "\($0.start): \($0.low)-\($0.high) mg/dL" }.joined(separator: ", ")
            let newStr = new.targets.map { "\($0.start): \($0.low)-\($0.high) mg/dL" }.joined(separator: ", ")
            guard oldStr != newStr else { return }
            auditStorage.logChange(
                category: "Therapy",
                subcategory: "BG Targets",
                settingName: "BG Target Profile",
                settingKey: "therapy.bgTargets",
                oldValue: oldStr.isEmpty ? "(empty)" : oldStr,
                newValue: newStr.isEmpty ? "(empty)" : newStr,
                unit: "mg/dL",
                note: nil,
                source: "manual"
            )
        }
    }
}
