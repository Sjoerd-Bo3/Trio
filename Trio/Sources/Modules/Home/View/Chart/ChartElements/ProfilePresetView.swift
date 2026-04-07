import Charts
import CoreData
import Foundation
import SwiftUI

struct ProfilePresetView: ChartContent {
    let profilePresetRunStored: [ProfilePresetRunStored]
    let units: GlucoseUnits
    let maxY: Decimal

    var body: some ChartContent {
        ForEach(profilePresetRunStored) { run in
            let start: Date = run.startDate ?? .distantPast
            let end: Date = run.endDate ?? Date()
            let isDiverted = run.isDiverted
            let presetName = run.name ?? String(localized: "Profile")
            let label = isDiverted
                ? String(localized: "\(presetName) (Diverted)")
                : presetName
            let displayMaxY = units == .mgdL ? maxY : maxY.asMmolL

            // Draw a thin bar at the top of the chart, matching the override/TT pattern
            RuleMark(
                xStart: .value("Start", start, unit: .second),
                xEnd: .value("End", end, unit: .second),
                y: .value("Value", displayMaxY)
            )
            .foregroundStyle(isDiverted ? Color.orange.opacity(0.4) : Color.teal.opacity(0.4))
            .lineStyle(.init(lineWidth: 8))
            .annotation(position: .overlay, alignment: .leading) {
                Text(label)
                    .font(.system(size: 8))
                    .foregroundStyle(isDiverted ? Color.orange : Color.teal)
                    .padding(.horizontal, 2)
            }
        }
    }
}
