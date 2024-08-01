import SwiftUI

extension UserInterfaceSettings {
    final class StateModel: BaseStateModel<Provider> {
        @Published var overrideHbA1cUnit = false
        @Published var tins: Bool = false
        @Published var lockScreenView: LockScreenView = .simple
        @Published var low: Decimal = 70
        @Published var high: Decimal = 180
        @Published var hours: Decimal = 6
        @Published var xGridLines = false
        @Published var yGridLines: Bool = false
        @Published var oneDimensionalGraph = false
        @Published var rulerMarks: Bool = true
        @Published var carbsRequiredThreshold: Decimal = 0

        var units: GlucoseUnits = .mgdL

        override func subscribe() {
            let units = settingsManager.settings.units
            self.units = units

            subscribeSetting(\.overrideHbA1cUnit, on: $overrideHbA1cUnit) { overrideHbA1cUnit = $0 }
            subscribeSetting(\.xGridLines, on: $xGridLines) { xGridLines = $0 }
            subscribeSetting(\.yGridLines, on: $yGridLines) { yGridLines = $0 }
            subscribeSetting(\.rulerMarks, on: $rulerMarks) { rulerMarks = $0 }
            subscribeSetting(\.tins, on: $tins) { tins = $0 }
            subscribeSetting(\.oneDimensionalGraph, on: $oneDimensionalGraph) { oneDimensionalGraph = $0 }
            subscribeSetting(\.lockScreenView, on: $lockScreenView) { lockScreenView = $0 }

            subscribeSetting(\.low, on: $low, initial: {
                let value = max(min($0, 90), 40)
                low = units == .mmolL ? value.asMmolL : value
            }, map: {
                guard units == .mmolL else { return $0 }
                return $0.asMgdL
            })

            subscribeSetting(\.high, on: $high, initial: {
                let value = max(min($0, 270), 110)
                high = units == .mmolL ? value.asMmolL : value
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
