import AppIntents
import Foundation

enum StateIntentError: Error {
    case StateIntentUnknownError
    case NoBG
    case NoIOBCOB
}

@available(iOS 16, *) struct StateiAPSResults: AppEntity {
    static var defaultQuery = StateBGQuery()

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "iAPS State Result"

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(glucose)")
    }

    var id: UUID
    @Property(title: "Glucose") var glucose: String

    @Property(title: "Trend") var trend: String

    @Property(title: "Delta") var delta: String

    @Property(title: "Date") var date: Date

    @Property(title: "IOB") var iob: Double?

    @Property(title: "COB") var cob: Double?

    @Property(title: "unit") var unit: String?

    init(glucose: String, trend: String, delta: String, date: Date, iob: Double, cob: Double, unit: GlucoseUnits) {
        id = UUID()
        self.glucose = glucose
        self.trend = trend
        self.delta = delta
        self.date = date
        self.iob = iob
        self.cob = cob
        self.unit = unit.rawValue
    }
}

@available(iOS 16.0, *) struct StateBGQuery: EntityQuery {
    func entities(for _: [StateiAPSResults.ID]) async throws -> [StateiAPSResults] {
        []
    }

    func suggestedEntities() async throws -> [StateiAPSResults] {
        []
    }
}

@available(iOS 16.0, *) final class StateIntentRequest: BaseIntentsRequest {
    let moc = CoreDataStack.shared.backgroundContext
    
    func getLastGlucose() throws -> (dateGlucose: Date, glucose: String, trend: String, delta: String)  {
        do {
           let results = try moc.fetch(GlucoseStored.fetch(NSPredicate.predicateFor30MinAgo, ascending: false, fetchLimit: 2))
            debugPrint("StateIntentRequest: \(#function) \(DebuggingIdentifiers.succeeded) fetched latest glucose")
            
            guard let lastValue = results.first else { throw StateIntentError.NoBG }
            
            ///calculate delta
            let lastGlucose = lastValue.glucose
            let secondLastGlucose = results.dropFirst().first?.glucose
            let delta = results.count > 1 ? (lastGlucose - (secondLastGlucose ?? 0)) : nil
            ///formatting
            let units = settingsManager.settings.units
            let glucoseAsString = glucoseFormatter.string(from: Double(
                units == .mmolL ? Decimal(lastGlucose)
                    .asMmolL : Decimal(lastGlucose)
            ) as NSNumber)!
            
            let directionAsString = lastValue.direction ?? "none"
            
            let deltaAsString = delta
                .map {
                    self.deltaFormatter
                        .string(from: Double(
                            units == .mmolL ? Decimal($0)
                                .asMmolL : Decimal($0)
                        ) as NSNumber)!
                } ?? "--"
            debugPrint("StateIntentRequest: \(#function) \(DebuggingIdentifiers.succeeded) fetched latest 2 glucose values")
            return (lastValue.date ?? Date(), glucoseAsString, directionAsString, deltaAsString)
        } catch {
            debugPrint("StateIntentRequest: \(#function) \(DebuggingIdentifiers.failed) failed to fetch latest 2 glucose values")
            return (Date(), "", "", "")
        }
    }
    
    func getIobAndCob() throws -> (iob: Double, cob: Double) {
        do {
            let results = try moc.fetch(OrefDetermination.fetch(NSPredicate.enactedDetermination))
            let iobAsDouble = Double(truncating: (results.first?.iob ?? 0.0) as NSNumber)
            let cobAsDouble = Double(truncating: (results.first?.cob ?? 0) as NSNumber)
            debugPrint("StateIntentRequest: \(#function) \(DebuggingIdentifiers.succeeded) fetched latest cob and iob")
            
            return (iobAsDouble, cobAsDouble)
        } catch {
            debugPrint("StateIntentRequest: \(#function) \(DebuggingIdentifiers.failed) failed to fetch latest cob and iob")
            return (0.0, 0.0)
        }
    }

    private var glucoseFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        if settingsManager.settings.units == .mmolL {
            formatter.minimumFractionDigits = 1
            formatter.maximumFractionDigits = 1
        }
        formatter.roundingMode = .halfUp
        return formatter
    }

    private var deltaFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.positivePrefix = "+"
        return formatter
    }
}
