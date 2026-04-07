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
            let old = self.profile
            storage.save(profile, as: OpenAPS.Settings.carbRatios)
            logCRChange(old: old, new: profile)
        }

        private func logCRChange(old: CarbRatios, new: CarbRatios) {
            let oldStr = old.schedule.map { "\($0.start): \($0.ratio) g/U" }.joined(separator: ", ")
            let newStr = new.schedule.map { "\($0.start): \($0.ratio) g/U" }.joined(separator: ", ")
            guard oldStr != newStr else { return }
            auditStorage.logChange(
                category: "Therapy",
                subcategory: "Carb Ratio",
                settingName: "Carb Ratio Profile",
                settingKey: "therapy.carbRatios",
                oldValue: oldStr.isEmpty ? "(empty)" : oldStr,
                newValue: newStr.isEmpty ? "(empty)" : newStr,
                unit: "g/U",
                note: nil,
                source: "manual"
            )
        }
    }
}
