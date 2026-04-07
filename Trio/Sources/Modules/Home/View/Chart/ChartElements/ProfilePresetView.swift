import Charts
import CoreData
import Foundation
import SwiftUI

struct ProfilePresetView: ChartContent {
    let profilePresetRunStored: [ProfilePresetRunStored]
    let units: GlucoseUnits
    let minY: Decimal
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

            // Draw a subtle background band across the full Y range
            RectangleMark(
                xStart: .value("Start", start, unit: .second),
                xEnd: .value("End", end, unit: .second),
                yStart: .value("Min", units == .mgdL ? minY : minY.asMmolL),
                yEnd: .value("Max", units == .mgdL ? maxY : maxY.asMmolL)
            )
            .foregroundStyle(isDiverted ? Color.orange.opacity(0.1) : Color.teal.opacity(0.1))
            .annotation(position: .overlay, alignment: .topLeading) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(isDiverted ? Color.orange : Color.teal)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
            }
        }
    }
}
