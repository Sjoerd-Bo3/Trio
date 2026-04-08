import Combine
import Swinject

extension CarbRatioEditor {
    final class Provider: BaseProvider, CarbRatioEditorProvider {
        @Injected() private var auditStorage: SettingsAuditStorage!

        var profile: CarbRatios {
            storage.retrieve(OpenAPS.Settings.carbRatios, as: CarbRatios.self)
                ?? CarbRatios(from: OpenAPS.defaults(for: OpenAPS.Settings.carbRatios))
                ?? CarbRatios(units: .grams, schedule: [])
        }

        func saveProfile(_ profile: CarbRatios) {
            let old = storage.retrieve(OpenAPS.Settings.carbRatios, as: CarbRatios.self)
                ?? CarbRatios(units: .grams, schedule: [])
            storage.save(profile, as: OpenAPS.Settings.carbRatios)
            auditStorage.logTherapyProfileChange(
                subcategory: "Carb Ratio",
                settingName: "Carb Ratio Profile",
                settingKey: "therapy.carbRatios",
                oldEntries: old.schedule.map { "\($0.start): \($0.ratio) g/U" },
                newEntries: profile.schedule.map { "\($0.start): \($0.ratio) g/U" },
                unit: "g/U"
            )
        }
    }
}
