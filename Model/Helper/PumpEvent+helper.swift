import CoreData
import Foundation

extension PumpEventStored {
    static func fetch(_ predicate: NSPredicate, ascending: Bool, fetchLimit: Int? = nil) -> NSFetchRequest<PumpEventStored> {
        let request = PumpEventStored.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: ascending)]
        request.resultType = .managedObjectResultType
        request.predicate = predicate
        if let fetchLimit = fetchLimit {
            request.fetchLimit = fetchLimit
        }
        return request
    }
}

public extension PumpEventStored {
    enum EventType: String, JSON {
        case bolus = "Bolus"
        case smb = "SMB"
        case isExternal = "External Insulin"
        case mealBolus = "Meal Bolus"
        case correctionBolus = "Correction Bolus"
        case snackBolus = "Snack Bolus"
        case bolusWizard = "BolusWizard"
        case tempBasal = "TempBasal"
        case tempBasalDuration = "TempBasalDuration"
        case pumpSuspend = "PumpSuspend"
        case pumpResume = "PumpResume"
        case pumpAlarm = "PumpAlarm"
        case pumpBattery = "PumpBattery"
        case rewind = "Rewind"
        case prime = "Prime"
        case journalCarbs = "JournalEntryMealMarker"

        case nsNote = "Note"
        case nsTempBasal = "Temp Basal"
        case nsCarbCorrection = "Carb Correction"
        case nsTempTarget = "Temporary Target"
        case nsInsulinChange = "Insulin Change"
        case nsSiteChange = "Site Change"
        case nsBatteryChange = "Pump Battery Change"
        case nsAnnouncement = "Announcement"
        case nsSensorChange = "Sensor Start"
        case nsExercise = "Exercise"
        case capillaryGlucose = "BG Check"
    }

    enum TempType: String, JSON {
        case absolute
        case percent
    }
}

extension NSPredicate {
    static var pumpHistoryLast1440Minutes: NSPredicate {
        let date = Date.oneDayAgoInMinutes
        return NSPredicate(format: "timestamp >= %@", date as NSDate)
    }

    static var pumpHistoryLast24h: NSPredicate {
        let date = Date.oneDayAgo
        return NSPredicate(format: "timestamp >= %@", date as NSDate)
    }

    static var recentPumpHistory: NSPredicate {
        let date = Date.twentyMinutesAgo
        return NSPredicate(format: "timestamp >= %@", date as NSDate)
    }

    static var lastPumpBolus: NSPredicate {
        let date = Date.twentyMinutesAgo
        return NSPredicate(format: "timestamp >= %@ AND bolus.isExternal == %@", date as NSDate, false as NSNumber)
    }

    static func duplicateInLastHour(_ date: Date) -> NSPredicate {
        let date60m = Date.oneHourAgo
        return NSPredicate(format: "timestamp >= %@ && timestamp == %@", date60m as NSDate, date as NSDate)
    }

    static var pumpEventsNotYetUploadedToNightscout: NSPredicate {
        let date = Date.oneDayAgo
        return NSPredicate(format: "timestamp >= %@ AND isUploadedToNS == %@", date as NSDate, false as NSNumber)
    }
}

// Declare helper structs ("data transfer objects" = DTO) to utilize parsing a flattened pump history
struct BolusDTO: Codable {
    var id: String
    var timestamp: String
    var amount: Double
    var isExternal: Bool
    var isSMB: Bool
    var duration: Int
    var _type: String = "Bolus"
}

struct TempBasalDTO: Codable {
    var id: String
    var timestamp: String
    var temp: String
    var rate: Double
    var _type: String = "TempBasal"
}

struct TempBasalDurationDTO: Codable {
    var id: String
    var timestamp: String
    var duration: Int
    var _type: String = "TempBasalDuration"

    private enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case duration = "duration (min)"
        case _type
    }
}

// Mask distinct DTO subtypes with a common enum that conforms to Encodable
enum PumpEventDTO: Encodable {
    case bolus(BolusDTO)
    case tempBasal(TempBasalDTO)
    case tempBasalDuration(TempBasalDurationDTO)

    func encode(to encoder: Encoder) throws {
        switch self {
        case let .bolus(bolus):
            try bolus.encode(to: encoder)
        case let .tempBasal(tempBasal):
            try tempBasal.encode(to: encoder)
        case let .tempBasalDuration(tempBasalDuration):
            try tempBasalDuration.encode(to: encoder)
        }
    }
}

// Extension with helper functions to map pump events to DTO objects via uniform masking enum
extension PumpEventStored {
    static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    func toBolusDTOEnum() -> PumpEventDTO? {
        guard let timestamp = timestamp, let bolus = bolus, let amount = bolus.amount else {
            return nil
        }

        let bolusDTO = BolusDTO(
            id: id ?? UUID().uuidString,
            timestamp: PumpEventStored.dateFormatter.string(from: timestamp),
            amount: amount.doubleValue,
            isExternal: bolus.isExternal,
            isSMB: bolus.isSMB,
            duration: 0
        )
        return .bolus(bolusDTO)
    }

    func toTempBasalDTOEnum() -> PumpEventDTO? {
        guard let id = id, let timestamp = timestamp, let tempBasal = tempBasal, let rate = tempBasal.rate else {
            return nil
        }

        let tempBasalDTO = TempBasalDTO(
            id: "_\(id)",
            timestamp: PumpEventStored.dateFormatter.string(from: timestamp),
            temp: tempBasal.tempType ?? "unknown",
            rate: rate.doubleValue
        )
        return .tempBasal(tempBasalDTO)
    }

    func toTempBasalDurationDTOEnum() -> PumpEventDTO? {
        guard let id = id, let timestamp = timestamp, let tempBasal = tempBasal else {
            return nil
        }

        let tempBasalDurationDTO = TempBasalDurationDTO(
            id: id,
            timestamp: PumpEventStored.dateFormatter.string(from: timestamp),
            duration: Int(tempBasal.duration)
        )
        return .tempBasalDuration(tempBasalDurationDTO)
    }
}
