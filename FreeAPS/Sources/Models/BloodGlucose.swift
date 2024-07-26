import Foundation
import HealthKit
import LoopKit

struct BloodGlucose: JSON, Identifiable, Hashable {
    enum Direction: String, JSON {
        case tripleUp = "TripleUp"
        case doubleUp = "DoubleUp"
        case singleUp = "SingleUp"
        case fortyFiveUp = "FortyFiveUp"
        case flat = "Flat"
        case fortyFiveDown = "FortyFiveDown"
        case singleDown = "SingleDown"
        case doubleDown = "DoubleDown"
        case tripleDown = "TripleDown"
        case none = "NONE"
        case notComputable = "NOT COMPUTABLE"
        case rateOutOfRange = "RATE OUT OF RANGE"

        init?(from string: String) {
            switch string {
            case "↑↑↑",
                 "TripleUp":
                self = .tripleUp
            case "↑↑",
                 "DoubleUp":
                self = .doubleUp
            case "↑",
                 "SingleUp":
                self = .singleUp
            case "↗︎",
                 "FortyFiveUp":
                self = .fortyFiveUp
            case "→",
                 "Flat":
                self = .flat
            case "↘︎",
                 "FortyFiveDown":
                self = .fortyFiveDown
            case "↓",
                 "SingleDown":
                self = .singleDown
            case "↓↓",
                 "DoubleDown":
                self = .doubleDown
            case "↓↓↓",
                 "TripleDown":
                self = .tripleDown
            case "↔︎",
                 "NONE":
                self = .none
            case "NOT COMPUTABLE":
                self = .notComputable
            case "RATE OUT OF RANGE":
                self = .rateOutOfRange
            default:
                return nil
            }
        }
    }

    var _id: String?
    var id: String {
        _id ?? UUID().uuidString
    }

    var sgv: Int?
    var direction: Direction?
    let date: Decimal
    let dateString: Date
    let unfiltered: Decimal?
    let filtered: Decimal?
    let noise: Int?
    var glucose: Int?
    var type: String? = nil
    var activationDate: Date? = nil
    var sessionStartDate: Date? = nil
    var transmitterID: String? = nil

    var isStateValid: Bool { sgv ?? 0 >= 39 && noise ?? 1 != 4 }

    static func == (lhs: BloodGlucose, rhs: BloodGlucose) -> Bool {
        lhs.dateString == rhs.dateString
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(dateString)
    }
}

enum GlucoseUnits: String, JSON, Equatable {
    case mgdL = "mg/dL"
    case mmolL = "mmol/L"

    static let exchangeRate: Decimal = 0.0555
}

extension Int {
    var asMmolL: Decimal {
        Decimal(self) * GlucoseUnits.exchangeRate
    }
}

extension Decimal {
    var asMmolL: Decimal {
        self * GlucoseUnits.exchangeRate
    }

    var asMgdL: Decimal {
        self / GlucoseUnits.exchangeRate
    }
}

extension Double {
    var asMmolL: Decimal {
        Decimal(self) * GlucoseUnits.exchangeRate
    }

    var asMgdL: Decimal {
        Decimal(self) / GlucoseUnits.exchangeRate
    }
}

extension BloodGlucose: SavitzkyGolaySmoothable {
    var value: Double {
        get {
            Double(glucose ?? 0)
        }
        set {
            glucose = Int(newValue)
            sgv = Int(newValue)
        }
    }
}

extension BloodGlucose {
    func convertStoredGlucoseSample(device: HKDevice?) -> StoredGlucoseSample {
        StoredGlucoseSample(
            syncIdentifier: id,
            startDate: dateString.date,
            quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: Double(glucose!)),
            device: device
        )
    }
}
