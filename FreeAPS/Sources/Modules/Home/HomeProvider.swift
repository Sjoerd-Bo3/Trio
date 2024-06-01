import Foundation
import LoopKitUI
import SwiftDate

extension Home {
    final class Provider: BaseProvider, HomeProvider {
        @Injected() var apsManager: APSManager!
        @Injected() var glucoseStorage: GlucoseStorage!
        @Injected() var tempTargetsStorage: TempTargetsStorage!
        @Injected() var announcementStorage: AnnouncementsStorage!

        func pumpTimeZone() -> TimeZone? {
            apsManager.pumpManager?.status.timeZone
        }

        func heartbeatNow() {
            apsManager.heartbeat(date: Date())
        }

        func tempTargets(hours: Int) -> [TempTarget] {
            tempTargetsStorage.recent().filter {
                $0.createdAt.addingTimeInterval(hours.hours.timeInterval) > Date()
            }
        }

        func tempTarget() -> TempTarget? {
            tempTargetsStorage.current()
        }

        func announcement(_ hours: Int) -> [Announcement] {
            announcementStorage.validate().filter {
                $0.createdAt.addingTimeInterval(hours.hours.timeInterval) > Date()
            }
        }

        func pumpSettings() -> PumpSettings {
            storage.retrieve(OpenAPS.Settings.settings, as: PumpSettings.self)
                ?? PumpSettings(from: OpenAPS.defaults(for: OpenAPS.Settings.settings))
                ?? PumpSettings(insulinActionCurve: 6, maxBolus: 10, maxBasal: 2)
        }

        func pumpReservoir() -> Decimal? {
            storage.retrieve(OpenAPS.Monitor.reservoir, as: Decimal.self)
        }

        func autotunedBasalProfile() -> [BasalProfileEntry] {
            storage.retrieve(OpenAPS.Settings.profile, as: Autotune.self)?.basalProfile
                ?? storage.retrieve(OpenAPS.Settings.pumpProfile, as: Autotune.self)?.basalProfile
                ?? [BasalProfileEntry(start: "00:00", minutes: 0, rate: 1)]
        }

        func basalProfile() -> [BasalProfileEntry] {
            storage.retrieve(OpenAPS.Settings.pumpProfile, as: Autotune.self)?.basalProfile
                ?? [BasalProfileEntry(start: "00:00", minutes: 0, rate: 1)]
        }
    }
}
