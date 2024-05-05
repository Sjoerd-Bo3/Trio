import Foundation
import LoopKit
import SwiftDate
import Swinject

protocol PumpHistoryObserver {
    func pumpHistoryDidUpdate(_ events: [PumpHistoryEvent])
}

protocol PumpHistoryStorage {
    func storePumpEvents(_ events: [NewPumpEvent])
    func storeEvents(_ events: [PumpHistoryEvent])
    func storeJournalCarbs(_ carbs: Int)
    func recent() -> [PumpHistoryEvent]
    func nightscoutTretmentsNotUploaded() -> [NigtscoutTreatment]
    func saveCancelTempEvents()
    func deleteInsulin(at date: Date)
}

final class BasePumpHistoryStorage: PumpHistoryStorage, Injectable {
    private let processQueue = DispatchQueue(label: "BasePumpHistoryStorage.processQueue")
    @Injected() private var storage: FileStorage!
    @Injected() private var broadcaster: Broadcaster!

    init(resolver: Resolver) {
        injectServices(resolver)
    }

    typealias PumpEvent = PumpEventStored.EventType
    typealias TempType = PumpEventStored.TempType

    private let context = CoreDataStack.shared.backgroundContext

    func storePumpEvents(_ events: [NewPumpEvent]) {
        processQueue.async {
            let eventsToStore = events.flatMap { event -> [PumpHistoryEvent] in
                let id = event.raw.md5String
                switch event.type {
                case .bolus:
                    guard let dose = event.dose else { return [] }
                    let amount = Decimal(string: dose.unitsInDeliverableIncrements.description)
                    let minutes = Int((dose.endDate - dose.startDate).timeInterval / 60)

                    self.context.perform {
                        // create pump event
                        let newPumpEvent = PumpEventStored(context: self.context)
                        newPumpEvent.id = id
                        newPumpEvent.timestamp = event.date
                        newPumpEvent.type = PumpEvent.bolus.rawValue

                        // create bolus entry and specify relationship to pump event
                        let newBolusEntry = BolusStored(context: self.context)
                        newBolusEntry.pumpEvent = newPumpEvent
                        newBolusEntry.amount = amount as? NSDecimalNumber
                        newBolusEntry.isExternal = dose.manuallyEntered
                        newBolusEntry.isSMB = dose.automatic ?? true
                        // TODO: - do we need duration here?

                        if self.context.hasChanges {
                            do {
                                try self.context.save()
                                debugPrint(
                                    "Pump History storage: \(#function) \(CoreDataStack.identifier) \(DebuggingIdentifiers.succeeded) saved smbs to core data"
                                )
                            } catch {
                                debugPrint(
                                    "Pump History storage: \(#function) \(CoreDataStack.identifier) \(DebuggingIdentifiers.failed) failed to save smbs to core data"
                                )
                            }
                        }
                    }

                    return [PumpHistoryEvent(
                        id: id,
                        type: .bolus,
                        timestamp: event.date,
                        amount: amount,
                        duration: minutes,
                        durationMin: nil,
                        rate: nil,
                        temp: nil,
                        carbInput: nil,
                        isSMB: dose.automatic,
                        isExternal: dose.manuallyEntered
                    )]
                case .tempBasal:
                    guard let dose = event.dose else { return [] }

                    let rate = Decimal(dose.unitsPerHour)
                    let minutes = (dose.endDate - dose.startDate).timeInterval / 60
                    let delivered = dose.deliveredUnits
                    let date = event.date

                    let isCancel = delivered != nil //! event.isMutable && delivered != nil
                    guard !isCancel else { return [] }

                    self.context.perform {
                        // create pump event
                        let newPumpEvent = PumpEventStored(context: self.context)
                        newPumpEvent.id = id
                        newPumpEvent.timestamp = date
                        newPumpEvent.type = PumpEvent.tempBasal.rawValue

                        // create temp basal and specify relationship
                        let newTempBasal = TempBasalStored(context: self.context)
                        newTempBasal.pumpEvent = newPumpEvent
                        newTempBasal.duration = Int16(round(minutes))
                        newTempBasal.rate = rate as NSDecimalNumber
                        newTempBasal.tempType = TempType.absolute.rawValue

                        if self.context.hasChanges {
                            do {
                                try self.context.save()
                                debugPrint(
                                    "Pump History storage: \(#function) \(CoreDataStack.identifier) \(DebuggingIdentifiers.succeeded) saved temp basal to core data"
                                )
                            } catch {
                                debugPrint(
                                    "Pump History storage: \(#function) \(CoreDataStack.identifier) \(DebuggingIdentifiers.failed) failed to save temp basal to core data"
                                )
                            }
                        }
                    }

                    return [
                        PumpHistoryEvent(
                            id: id,
                            type: .tempBasalDuration,
                            timestamp: date,
                            amount: nil,
                            duration: nil,
                            durationMin: Int(round(minutes)),
                            rate: nil,
                            temp: nil,
                            carbInput: nil
                        ),
                        PumpHistoryEvent(
                            id: "_" + id,
                            type: .tempBasal,
                            timestamp: date,
                            amount: nil,
                            duration: nil,
                            durationMin: nil,
                            rate: rate,
                            temp: .absolute,
                            carbInput: nil
                        )
                    ]
                case .suspend:
                    self.context.perform {
                        // create pump event
                        let newPumpEvent = PumpEventStored(context: self.context)
                        newPumpEvent.id = id
                        newPumpEvent.timestamp = event.date
                        newPumpEvent.type = PumpEvent.pumpSuspend.rawValue

                        if self.context.hasChanges {
                            do {
                                try self.context.save()
                                debugPrint(
                                    "Pump History storage: \(#function) \(CoreDataStack.identifier) \(DebuggingIdentifiers.succeeded) saved suspension to core data"
                                )
                            } catch {
                                debugPrint(
                                    "Pump History storage: \(#function) \(CoreDataStack.identifier) \(DebuggingIdentifiers.failed) failed to save suspension to core data"
                                )
                            }
                        }
                    }
                    return [
                        PumpHistoryEvent(
                            id: id,
                            type: .pumpSuspend,
                            timestamp: event.date,
                            amount: nil,
                            duration: nil,
                            durationMin: nil,
                            rate: nil,
                            temp: nil,
                            carbInput: nil
                        )
                    ]
                case .resume:
                    return [
                        PumpHistoryEvent(
                            id: id,
                            type: .pumpResume,
                            timestamp: event.date,
                            amount: nil,
                            duration: nil,
                            durationMin: nil,
                            rate: nil,
                            temp: nil,
                            carbInput: nil
                        )
                    ]
                case .rewind:
                    return [
                        PumpHistoryEvent(
                            id: id,
                            type: .rewind,
                            timestamp: event.date,
                            amount: nil,
                            duration: nil,
                            durationMin: nil,
                            rate: nil,
                            temp: nil,
                            carbInput: nil
                        )
                    ]
                case .prime:
                    return [
                        PumpHistoryEvent(
                            id: id,
                            type: .prime,
                            timestamp: event.date,
                            amount: nil,
                            duration: nil,
                            durationMin: nil,
                            rate: nil,
                            temp: nil,
                            carbInput: nil
                        )
                    ]
                case .alarm:
                    return [
                        PumpHistoryEvent(
                            id: id,
                            type: .pumpAlarm,
                            timestamp: event.date,
                            note: event.title
                        )
                    ]
                default:
                    return []
                }
            }

            self.storeEvents(eventsToStore)
        }
    }

    func storeJournalCarbs(_ carbs: Int) {
        processQueue.async {
            let eventsToStore = [
                PumpHistoryEvent(
                    id: UUID().uuidString,
                    type: .journalCarbs,
                    timestamp: Date(),
                    amount: nil,
                    duration: nil,
                    durationMin: nil,
                    rate: nil,
                    temp: nil,
                    carbInput: carbs
                )
            ]
            self.storeEvents(eventsToStore)
        }
    }

    func storeEvents(_ events: [PumpHistoryEvent]) {
        processQueue.async {
            let file = OpenAPS.Monitor.pumpHistory
            var uniqEvents: [PumpHistoryEvent] = []
            self.storage.transaction { storage in
                storage.append(events, to: file, uniqBy: \.id)
                uniqEvents = storage.retrieve(file, as: [PumpHistoryEvent].self)?
                    .filter { $0.timestamp.addingTimeInterval(1.days.timeInterval) > Date() }
                    .sorted { $0.timestamp > $1.timestamp } ?? []
                storage.save(Array(uniqEvents), as: file)
            }
            self.broadcaster.notify(PumpHistoryObserver.self, on: self.processQueue) {
                $0.pumpHistoryDidUpdate(uniqEvents)
            }
        }
    }

    func recent() -> [PumpHistoryEvent] {
        storage.retrieve(OpenAPS.Monitor.pumpHistory, as: [PumpHistoryEvent].self)?.reversed() ?? []
    }

    func deleteInsulin(at date: Date) {
        processQueue.sync {
            var allValues = storage.retrieve(OpenAPS.Monitor.pumpHistory, as: [PumpHistoryEvent].self) ?? []
            guard let entryIndex = allValues.firstIndex(where: { $0.timestamp == date }) else {
                return
            }
            allValues.remove(at: entryIndex)
            storage.save(allValues, as: OpenAPS.Monitor.pumpHistory)
            broadcaster.notify(PumpHistoryObserver.self, on: processQueue) {
                $0.pumpHistoryDidUpdate(allValues)
            }
        }
    }

    func determineBolusEventType(for event: PumpHistoryEvent) -> EventType {
        if event.isSMB ?? false {
            return .smb
        }
        if event.isExternal ?? false {
            return .isExternal
        }
        return event.type
    }

    func nightscoutTretmentsNotUploaded() -> [NigtscoutTreatment] {
        let events = recent()
        guard !events.isEmpty else { return [] }

        let temps: [NigtscoutTreatment] = events.reduce([]) { result, event in
            var result = result
            switch event.type {
            case .tempBasal:
                result.append(NigtscoutTreatment(
                    duration: nil,
                    rawDuration: nil,
                    rawRate: event,
                    absolute: event.rate,
                    rate: event.rate,
                    eventType: .nsTempBasal,
                    createdAt: event.timestamp,
                    enteredBy: NigtscoutTreatment.local,
                    bolus: nil,
                    insulin: nil,
                    notes: nil,
                    carbs: nil,
                    fat: nil,
                    protein: nil,
                    targetTop: nil,
                    targetBottom: nil
                ))
            case .tempBasalDuration:
                if var last = result.popLast(), last.eventType == .nsTempBasal, last.createdAt == event.timestamp {
                    last.duration = event.durationMin
                    last.rawDuration = event
                    result.append(last)
                }
            default: break
            }
            return result
        }

        let bolusesAndCarbs = events.compactMap { event -> NigtscoutTreatment? in
            switch event.type {
            case .bolus:
                let eventType = determineBolusEventType(for: event)
                return NigtscoutTreatment(
                    duration: event.duration,
                    rawDuration: nil,
                    rawRate: nil,
                    absolute: nil,
                    rate: nil,
                    eventType: eventType,
                    createdAt: event.timestamp,
                    enteredBy: NigtscoutTreatment.local,
                    bolus: event,
                    insulin: event.amount,
                    notes: nil,
                    carbs: nil,
                    fat: nil,
                    protein: nil,
                    targetTop: nil,
                    targetBottom: nil
                )
            case .journalCarbs:
                return NigtscoutTreatment(
                    duration: nil,
                    rawDuration: nil,
                    rawRate: nil,
                    absolute: nil,
                    rate: nil,
                    eventType: .nsCarbCorrection,
                    createdAt: event.timestamp,
                    enteredBy: NigtscoutTreatment.local,
                    bolus: nil,
                    insulin: nil,
                    notes: nil,
                    carbs: Decimal(event.carbInput ?? 0),
                    fat: nil,
                    protein: nil,
                    targetTop: nil,
                    targetBottom: nil
                )
            default: return nil
            }
        }

        let misc = events.compactMap { event -> NigtscoutTreatment? in
            switch event.type {
            case .prime:
                return NigtscoutTreatment(
                    duration: event.duration,
                    rawDuration: nil,
                    rawRate: nil,
                    absolute: nil,
                    rate: nil,
                    eventType: .nsSiteChange,
                    createdAt: event.timestamp,
                    enteredBy: NigtscoutTreatment.local,
                    bolus: event,
                    insulin: nil,
                    notes: nil,
                    carbs: nil,
                    fat: nil,
                    protein: nil,
                    targetTop: nil,
                    targetBottom: nil
                )
            case .rewind:
                return NigtscoutTreatment(
                    duration: nil,
                    rawDuration: nil,
                    rawRate: nil,
                    absolute: nil,
                    rate: nil,
                    eventType: .nsInsulinChange,
                    createdAt: event.timestamp,
                    enteredBy: NigtscoutTreatment.local,
                    bolus: nil,
                    insulin: nil,
                    notes: nil,
                    carbs: nil,
                    fat: nil,
                    protein: nil,
                    targetTop: nil,
                    targetBottom: nil
                )
            case .pumpAlarm:
                return NigtscoutTreatment(
                    duration: 30, // minutes
                    rawDuration: nil,
                    rawRate: nil,
                    absolute: nil,
                    rate: nil,
                    eventType: .nsAnnouncement,
                    createdAt: event.timestamp,
                    enteredBy: NigtscoutTreatment.local,
                    bolus: nil,
                    insulin: nil,
                    notes: "Alarm \(String(describing: event.note)) \(event.type)",
                    carbs: nil,
                    fat: nil,
                    protein: nil,
                    targetTop: nil,
                    targetBottom: nil
                )
            default: return nil
            }
        }

        let uploaded = storage.retrieve(OpenAPS.Nightscout.uploadedPumphistory, as: [NigtscoutTreatment].self) ?? []

        let treatments = Array(Set([bolusesAndCarbs, temps, misc].flatMap { $0 }).subtracting(Set(uploaded)))

        return treatments.sorted { $0.createdAt! > $1.createdAt! }
    }

    func saveCancelTempEvents() {
        let basalID = UUID().uuidString
        let date = Date()

        let events = [
            PumpHistoryEvent(
                id: basalID,
                type: .tempBasalDuration,
                timestamp: date,
                amount: nil,
                duration: nil,
                durationMin: 0,
                rate: nil,
                temp: nil,
                carbInput: nil
            ),
            PumpHistoryEvent(
                id: "_" + basalID,
                type: .tempBasal,
                timestamp: date,
                amount: nil,
                duration: nil,
                durationMin: nil,
                rate: 0,
                temp: .absolute,
                carbInput: nil
            )
        ]

        storeEvents(events)
    }
}
