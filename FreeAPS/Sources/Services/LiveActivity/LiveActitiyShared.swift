import ActivityKit
import Foundation

struct LiveActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        let bg: String
        let direction: String?
        let change: String
        let date: Date
        let chart: [Double]
        let chartDate: [Date?]
        let rotationDegrees: Double
        let highGlucose: Double
        let lowGlucose: Double

        let graphMinYGlucose: Double
        let graphMaxYGlucose: Double
        let showLAGraphHourLines: Bool
        let showLAGraphGlucoseLines: Bool
        let showLAGraphColouredGlucoseThresholdLines: Bool
        let showLAGraphGlucoseLabels: Bool
        let showLAGraphHourLabels: Bool

        let cob: Decimal
        let iob: Decimal
        let lockScreenView: String
    }

    let startDate: Date
}
