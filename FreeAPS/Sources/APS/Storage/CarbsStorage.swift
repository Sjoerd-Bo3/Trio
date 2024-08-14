import CoreData
import Foundation
import SwiftDate
import Swinject

protocol CarbsObserver {
    func carbsDidUpdate(_ carbs: [CarbsEntry])
}

protocol CarbsStorage {
    func storeCarbs(_ carbs: [CarbsEntry]) async
    func syncDate() -> Date
    func recent() -> [CarbsEntry]
    func getCarbsNotYetUploadedToNightscout() async -> [NightscoutTreatment]
    func getFPUsNotYetUploadedToNightscout() async -> [NightscoutTreatment]
    func deleteCarbs(at uniqueID: String, fpuID: String, complex: Bool)
}

final class BaseCarbsStorage: CarbsStorage, Injectable {
    private let processQueue = DispatchQueue(label: "BaseCarbsStorage.processQueue")
    @Injected() private var storage: FileStorage!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var settings: SettingsManager!

    let coredataContext = CoreDataStack.shared.newTaskContext()

    init(resolver: Resolver) {
        injectServices(resolver)
    }

    func storeCarbs(_ entries: [CarbsEntry]) async {
        await saveCarbEquivalents(entries: entries)
        await saveCarbsToCoreData(entries: entries)
    }

    /**
     Calculates the duration for processing FPUs (fat and protein units) based on the FPUs and the time cap.

     - The function uses predefined rules to determine the duration based on the number of FPUs.
     - Ensures that the duration does not exceed the time cap.

     - Parameters:
       - fpus: The number of FPUs calculated from fat and protein.
       - timeCap: The maximum allowed duration.

     - Returns: The computed duration in hours.
     */
    private func calculateComputedDuration(fpus: Decimal, timeCap: Int) -> Int {
        switch fpus {
        case ..<2:
            return 3
        case 2 ..< 3:
            return 4
        case 3 ..< 4:
            return 5
        default:
            return timeCap
        }
    }

    /**
     Processes fat and protein entries to generate future carb equivalents, ensuring each equivalent is at least 1.0 grams.

     - The function calculates the equivalent carb dosage size and adjusts the interval to ensure each equivalent is at least 1.0 grams.
     - Creates future carb entries based on the adjusted carb equivalent size and interval.

     - Parameters:
       - entries: An array of `CarbsEntry` objects representing the carbohydrate entries to be processed.
       - fat: The amount of fat in the last entry.
       - protein: The amount of protein in the last entry.
       - createdAt: The creation date of the last entry.

     - Returns: A tuple containing the array of future carb entries and the total carb equivalents.
     */
    private func processFPU(
        entries _: [CarbsEntry],
        fat: Decimal,
        protein: Decimal,
        createdAt: Date,
        actualDate: Date?
    ) -> ([CarbsEntry], Decimal) {
        let interval = settings.settings.minuteInterval
        let timeCap = settings.settings.timeCap
        let adjustment = settings.settings.individualAdjustmentFactor
        let delay = settings.settings.delay

        let kcal = protein * 4 + fat * 9
        let carbEquivalents = (kcal / 10) * adjustment
        let fpus = carbEquivalents / 10
        var computedDuration = calculateComputedDuration(fpus: fpus, timeCap: timeCap)

        var carbEquivalentSize: Decimal = carbEquivalents / Decimal(computedDuration)
        carbEquivalentSize /= Decimal(60 / interval)

        if carbEquivalentSize < 1.0 {
            carbEquivalentSize = 1.0
            computedDuration = Int(carbEquivalents / carbEquivalentSize)
        }

        let roundedEquivalent: Double = round(Double(carbEquivalentSize * 10)) / 10
        carbEquivalentSize = Decimal(roundedEquivalent)
        var numberOfEquivalents = carbEquivalents / carbEquivalentSize

        var useDate = actualDate ?? createdAt
        let fpuID = UUID().uuidString
        var futureCarbArray = [CarbsEntry]()
        var firstIndex = true

        while carbEquivalents > 0, numberOfEquivalents > 0 {
            useDate = firstIndex ? useDate.addingTimeInterval(delay.minutes.timeInterval) : useDate
                .addingTimeInterval(interval.minutes.timeInterval)
            firstIndex = false

            let eachCarbEntry = CarbsEntry(
                id: UUID().uuidString,
                createdAt: createdAt,
                actualDate: useDate,
                carbs: carbEquivalentSize,
                fat: 0,
                protein: 0,
                note: nil,
                enteredBy: CarbsEntry.manual, isFPU: true,
                fpuID: fpuID
            )
            futureCarbArray.append(eachCarbEntry)
            numberOfEquivalents -= 1
        }

        return (futureCarbArray, carbEquivalents)
    }

    private func saveCarbEquivalents(entries: [CarbsEntry]) async {
        guard let lastEntry = entries.last else { return }

        if let fat = lastEntry.fat, let protein = lastEntry.protein, fat > 0 || protein > 0 {
            let (futureCarbEquivalents, carbEquivalentCount) = processFPU(
                entries: entries,
                fat: fat,
                protein: protein,
                createdAt: lastEntry.createdAt,
                actualDate: lastEntry.actualDate
            )

            if carbEquivalentCount > 0 {
                await saveFPUToCoreDataAsBatchInsert(entries: futureCarbEquivalents)
            }
        }
    }

    private func saveCarbsToCoreData(entries: [CarbsEntry]) async {
        guard let entry = entries.last, entry.carbs != 0 else { return }

        await coredataContext.perform {
            let newItem = CarbEntryStored(context: self.coredataContext)
            newItem.date = entry.actualDate ?? entry.createdAt
            newItem.carbs = Double(truncating: NSDecimalNumber(decimal: entry.carbs))
            newItem.fat = Double(truncating: NSDecimalNumber(decimal: entry.fat ?? 0))
            newItem.protein = Double(truncating: NSDecimalNumber(decimal: entry.protein ?? 0))
            newItem.id = UUID()
            newItem.isFPU = false
            newItem.isUploadedToNS = false

            do {
                guard self.coredataContext.hasChanges else { return }
                try self.coredataContext.save()
            } catch {
                print(error.localizedDescription)
            }
        }
    }

    private func saveFPUToCoreDataAsBatchInsert(entries: [CarbsEntry]) async {
        let commonFPUID =
            UUID() // all fpus should only get ONE id per batch insert to be able to delete them referencing the fpuID
        var entrySlice = ArraySlice(entries) // convert to ArraySlice
        let batchInsert = NSBatchInsertRequest(entity: CarbEntryStored.entity()) { (managedObject: NSManagedObject) -> Bool in
            guard let carbEntry = managedObject as? CarbEntryStored, let entry = entrySlice.popFirst(),
                  let entryId = entry.id
            else {
                return true // return true to stop
            }
            carbEntry.date = entry.actualDate
            carbEntry.carbs = Double(truncating: NSDecimalNumber(decimal: entry.carbs))
            carbEntry.id = UUID.init(uuidString: entryId)
            carbEntry.fpuID = commonFPUID
            carbEntry.isFPU = true
            carbEntry.isUploadedToNS = false
            return false // return false to continue
        }
        await coredataContext.perform {
            do {
                try self.coredataContext.execute(batchInsert)
                debugPrint("Carbs Storage: \(DebuggingIdentifiers.succeeded) saved fpus to core data")

                // Send notification for triggering a fetch in Home State Model to update the FPU Array
                Foundation.NotificationCenter.default.post(name: .didPerformBatchInsert, object: nil)
            } catch {
                debugPrint("Carbs Storage: \(DebuggingIdentifiers.failed) error while saving fpus to core data")
            }
        }
    }

    func syncDate() -> Date {
        Date().addingTimeInterval(-1.days.timeInterval)
    }

    func recent() -> [CarbsEntry] {
        storage.retrieve(OpenAPS.Monitor.carbHistory, as: [CarbsEntry].self)?.reversed() ?? []
    }

    func deleteCarbs(at uniqueID: String, fpuID: String, complex: Bool) {
        processQueue.sync {
            var allValues = storage.retrieve(OpenAPS.Monitor.carbHistory, as: [CarbsEntry].self) ?? []

            if fpuID != "" {
                if allValues.firstIndex(where: { $0.fpuID == fpuID }) == nil {
                    debug(.default, "Didn't find any carb equivalents to delete. ID to search for: " + fpuID.description)
                } else {
                    allValues.removeAll(where: { $0.fpuID == fpuID })
                    storage.save(allValues, as: OpenAPS.Monitor.carbHistory)
                    broadcaster.notify(CarbsObserver.self, on: processQueue) {
                        $0.carbsDidUpdate(allValues)
                    }
                }
            }

            if fpuID == "" || complex {
                if allValues.firstIndex(where: { $0.id == uniqueID }) == nil {
                    debug(.default, "Didn't find any carb entries to delete. ID to search for: " + uniqueID.description)
                } else {
                    allValues.removeAll(where: { $0.id == uniqueID })
                    storage.save(allValues, as: OpenAPS.Monitor.carbHistory)
                    broadcaster.notify(CarbsObserver.self, on: processQueue) {
                        $0.carbsDidUpdate(allValues)
                    }
                }
            }
        }
    }

    func getCarbsNotYetUploadedToNightscout() async -> [NightscoutTreatment] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: coredataContext,
            predicate: NSPredicate.carbsNotYetUploadedToNightscout,
            key: "date",
            ascending: false
        )

        guard let carbEntries = results as? [CarbEntryStored] else {
            return []
        }

        return await coredataContext.perform {
            return carbEntries.map { result in
                NightscoutTreatment(
                    duration: nil,
                    rawDuration: nil,
                    rawRate: nil,
                    absolute: nil,
                    rate: nil,
                    eventType: .nsCarbCorrection,
                    createdAt: result.date,
                    enteredBy: CarbsEntry.manual,
                    bolus: nil,
                    insulin: nil,
                    carbs: Decimal(result.carbs),
                    fat: Decimal(result.fat),
                    protein: Decimal(result.protein),
                    foodType: result.note,
                    targetTop: nil,
                    targetBottom: nil,
                    id: result.id?.uuidString
                )
            }
        }
    }

    func getFPUsNotYetUploadedToNightscout() async -> [NightscoutTreatment] {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: coredataContext,
            predicate: NSPredicate.fpusNotYetUploadedToNightscout,
            key: "date",
            ascending: false
        )

        guard let fpuEntries = results as? [CarbEntryStored] else { return [] }

        return await coredataContext.perform {
            return fpuEntries.map { result in
                NightscoutTreatment(
                    duration: nil,
                    rawDuration: nil,
                    rawRate: nil,
                    absolute: nil,
                    rate: nil,
                    eventType: .nsCarbCorrection,
                    createdAt: result.date,
                    enteredBy: CarbsEntry.manual,
                    bolus: nil,
                    insulin: nil,
                    carbs: Decimal(result.carbs),
                    fat: Decimal(result.fat),
                    protein: Decimal(result.protein),
                    foodType: result.note,
                    targetTop: nil,
                    targetBottom: nil,
                    id: result.fpuID?.uuidString
                )
            }
        }
    }
}
