import Combine
import Foundation
import HealthKit
import LoopKit
import LoopKitUI

extension SettingsImport {
    final class Provider: BaseProvider, SettingsImportProvider {
        private let processQueue = DispatchQueue(label: "SettingsImportProvider.processQueue")
        @Injected() private var broadcaster: Broadcaster!

        var supportedBasalRates: [Decimal]? {
            deviceManager.pumpManager?.supportedBasalRates.map { Decimal($0) }
        }

        /// Saves the basal profile, syncing it to the pump first when one is paired — the file is
        /// only written after the pump accepted the schedule, so pump and file never diverge.
        /// Returns true when the profile was synced to a pump, false when it was only saved
        /// locally because no pump is paired (pump setup programs it later).
        func saveBasalProfile(_ profile: [BasalProfileEntry]) async throws -> Bool {
            guard let pump = deviceManager?.pumpManager else {
                storage.save(profile, as: OpenAPS.Settings.basalProfile)
                return false
            }

            let syncValues = profile.map {
                RepeatingScheduleValue(startTime: TimeInterval($0.minutes * 60), value: Double($0.rate))
            }

            return try await withCheckedThrowingContinuation { continuation in
                pump.syncBasalRateSchedule(items: syncValues) { result in
                    switch result {
                    case .success:
                        self.storage.save(profile, as: OpenAPS.Settings.basalProfile)
                        continuation.resume(returning: true)
                    case let .failure(error):
                        continuation.resume(throwing: error)
                    }
                }
            }
        }

        /// Saves delivery limits and DIA, mirroring `UnitsLimitsSettingsProvider.save`: with a pump,
        /// the limits are synced first and the pump's echoed values are persisted (some pumps only
        /// report limits); without one, they are saved locally. Nothing is persisted when the pump
        /// rejects the sync.
        func savePumpSettings(_ settings: PumpSettings) async throws {
            func save(_ settings: PumpSettings) {
                storage.save(settings, as: OpenAPS.Settings.settings)
                processQueue.async {
                    self.broadcaster.notify(PumpSettingsObserver.self, on: self.processQueue) {
                        $0.pumpSettingsDidChange(settings)
                    }
                }
            }

            guard let pump = deviceManager?.pumpManager else {
                save(settings)
                return
            }

            let limits = DeliveryLimits(
                maximumBasalRate: HKQuantity(unit: .internationalUnitsPerHour, doubleValue: Double(settings.maxBasal)),
                maximumBolus: HKQuantity(unit: .internationalUnit(), doubleValue: Double(settings.maxBolus))
            )

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                processQueue.async {
                    pump.syncDeliveryLimits(limits: limits) { result in
                        switch result {
                        case let .success(actual):
                            save(PumpSettings(
                                insulinActionCurve: settings.insulinActionCurve,
                                maxBolus: Decimal(
                                    actual.maximumBolus?
                                        .doubleValue(for: .internationalUnit()) ?? Double(settings.maxBolus)
                                ),
                                maxBasal: Decimal(
                                    actual.maximumBasalRate?
                                        .doubleValue(for: .internationalUnitsPerHour) ?? Double(settings.maxBasal)
                                )
                            ))
                            continuation.resume()
                        case let .failure(error):
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }
        }
    }
}
