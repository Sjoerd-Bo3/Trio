import Foundation

enum SettingsImport {
    enum Config {}
}

protocol SettingsImportProvider: Provider {
    var supportedBasalRates: [Decimal]? { get }
    func saveBasalProfile(_ profile: [BasalProfileEntry]) async throws -> Bool
    func savePumpSettings(_ settings: PumpSettings) async throws
}
