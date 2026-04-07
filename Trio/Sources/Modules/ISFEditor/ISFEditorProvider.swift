import Foundation
import Swinject

extension ISFEditor {
    final class Provider: BaseProvider, ISFEditorProvider {
        @Injected() private var auditStorage: SettingsAuditStorage!

        var profile: InsulinSensitivities {
            var retrievedSensitivities = storage.retrieve(OpenAPS.Settings.insulinSensitivities, as: InsulinSensitivities.self)
                ?? InsulinSensitivities(from: OpenAPS.defaults(for: OpenAPS.Settings.insulinSensitivities))
                ?? InsulinSensitivities(
                    units: .mgdL,
                    userPreferredUnits: .mgdL,
                    sensitivities: []
                )

            // migrate existing mmol/L Trio users from mmol/L settings to pure mg/dl settings
            if retrievedSensitivities.units == .mmolL || retrievedSensitivities.userPreferredUnits == .mmolL {
                let convertedSensitivities = retrievedSensitivities.sensitivities.map { isf in
                    InsulinSensitivityEntry(
                        sensitivity: storage.parseSettingIfMmolL(value: isf.sensitivity),
                        offset: isf.offset,
                        start: isf.start
                    )
                }
                retrievedSensitivities = InsulinSensitivities(
                    units: .mgdL,
                    userPreferredUnits: .mgdL,
                    sensitivities: convertedSensitivities
                )
                saveProfile(retrievedSensitivities)
            }

            return retrievedSensitivities
        }

        func saveProfile(_ profile: InsulinSensitivities) {
            let old = storage.retrieve(OpenAPS.Settings.insulinSensitivities, as: InsulinSensitivities.self)
                ?? InsulinSensitivities(units: .mgdL, userPreferredUnits: .mgdL, sensitivities: [])
            storage.save(profile, as: OpenAPS.Settings.insulinSensitivities)
            auditStorage.logTherapyProfileChange(
                subcategory: "Insulin Sensitivity Factor",
                settingName: "ISF Profile",
                settingKey: "therapy.insulinSensitivities",
                oldEntries: old.sensitivities.map { "\($0.start): \($0.sensitivity) mg/dL/U" },
                newEntries: profile.sensitivities.map { "\($0.start): \($0.sensitivity) mg/dL/U" },
                unit: "mg/dL/U"
            )
        }
    }
}
