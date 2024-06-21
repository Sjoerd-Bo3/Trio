import SwiftUI

extension NotificationsConfig {
    final class StateModel: BaseStateModel<Provider> {
        @Published var glucoseBadge = false
        @Published var glucoseNotificationsAlways = false
        @Published var useAlarmSound = false
        @Published var addSourceInfoToGlucoseNotifications = false
        @Published var lowGlucose: Decimal = 0
        @Published var highGlucose: Decimal = 0
        @Published var carbsRequiredThreshold: Decimal = 0
        @Published var useLiveActivity = false
        @Published var graphLAMinY: Decimal = 0
        @Published var graphLAMaxY: Decimal = 0
        @Published var showLAGraphHourLines = false
        @Published var showLAGraphGlucoseLines = false
        @Published var showLAGraphColouredGlucoseThresholdLines = false
        @Published var showLAGraphGlucoseLabels = false
        @Published var showLAGraphHourLabels = false
        @Published var lockScreenView: LockScreenView = .simple
        var units: GlucoseUnits = .mmolL

        override func subscribe() {
            let units = settingsManager.settings.units
            self.units = units

            subscribeSetting(\.glucoseBadge, on: $glucoseBadge) { glucoseBadge = $0 }
            subscribeSetting(\.glucoseNotificationsAlways, on: $glucoseNotificationsAlways) { glucoseNotificationsAlways = $0 }
            subscribeSetting(\.useAlarmSound, on: $useAlarmSound) { useAlarmSound = $0 }
            subscribeSetting(\.addSourceInfoToGlucoseNotifications, on: $addSourceInfoToGlucoseNotifications) {
                addSourceInfoToGlucoseNotifications = $0 }
            subscribeSetting(\.useLiveActivity, on: $useLiveActivity) { useLiveActivity = $0 }
            subscribeSetting(\.lockScreenView, on: $lockScreenView) { lockScreenView = $0 }
            subscribeSetting(\.showLAGraphHourLines, on: $showLAGraphHourLines) { showLAGraphHourLines = $0 }
            subscribeSetting(\.showLAGraphGlucoseLines, on: $showLAGraphGlucoseLines) { showLAGraphGlucoseLines = $0 }
            subscribeSetting(\.showLAGraphColouredGlucoseThresholdLines, on: $showLAGraphColouredGlucoseThresholdLines) {
                showLAGraphColouredGlucoseThresholdLines = $0 }
            subscribeSetting(\.showLAGraphGlucoseLabels, on: $showLAGraphGlucoseLabels) { showLAGraphGlucoseLabels = $0 }
            subscribeSetting(\.showLAGraphHourLabels, on: $showLAGraphHourLabels) { showLAGraphHourLabels = $0 }

            subscribeSetting(\.graphLAMinY, on: $graphLAMinY, initial: {
                let value = max(min($0, 400), 40)
                graphLAMinY = units == .mmolL ? value.asMmolL : value
            }, map: {
                guard units == .mmolL else { return $0 }
                return $0.asMgdL
            })

            subscribeSetting(\.graphLAMaxY, on: $graphLAMaxY, initial: {
                let value = max(min($0, 400), 40)
                graphLAMaxY = units == .mmolL ? value.asMmolL : value
            }, map: {
                guard units == .mmolL else { return $0 }
                return $0.asMgdL
            })

            subscribeSetting(\.lowGlucose, on: $lowGlucose, initial: {
                let value = max(min($0, 400), 40)
                lowGlucose = units == .mmolL ? value.asMmolL : value
            }, map: {
                guard units == .mmolL else { return $0 }
                return $0.asMgdL
            })

            subscribeSetting(\.highGlucose, on: $highGlucose, initial: {
                let value = max(min($0, 400), 40)
                highGlucose = units == .mmolL ? value.asMmolL : value
            }, map: {
                guard units == .mmolL else { return $0 }
                return $0.asMgdL
            })

            subscribeSetting(
                \.carbsRequiredThreshold,
                on: $carbsRequiredThreshold
            ) { carbsRequiredThreshold = $0 }
        }
    }
}
