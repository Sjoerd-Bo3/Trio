import Combine
import CoreData
import Foundation
import HealthKit
import LoopKit
import LoopKitUI
import Swinject

protocol HealthKitManager {
    /// Check all needed permissions
    /// Return false if one or more permissions are deny or not choosen
    var hasGrantedFullWritePermissions: Bool { get }
    /// Check availability to save data of BG type to Health store
    func hasGlucoseWritePermission() -> Bool
    /// Requests user to give permissions on using HealthKit
    func requestPermission() async throws -> Bool
    /// Checks whether permissions are granted for Trio to write to Health
    func checkWriteToHealthPermissions(objectTypeToHealthStore: HKObjectType) -> Bool
    /// Save blood glucose to Health store
    func uploadGlucose() async
    /// Save carbs to Health store
    func uploadCarbs() async
    /// Save Insulin to Health store
    func uploadInsulin() async
    /// Delete glucose with syncID
    func deleteGlucose(syncID: String) async
    /// delete carbs with syncID
    func deleteMealData(byID id: String, sampleType: HKSampleType) async
    /// delete insulin with syncID
    func deleteInsulin(syncID: String) async
}

public enum AppleHealthConfig {
    // unwraped HKObjects
    static var writePermissions: Set<HKSampleType> {
        Set([healthBGObject, healthCarbObject, healthFatObject, healthProteinObject, healthInsulinObject].compactMap { $0 }) }

    // link to object in HealthKit
    static let healthBGObject = HKObjectType.quantityType(forIdentifier: .bloodGlucose)
    static let healthCarbObject = HKObjectType.quantityType(forIdentifier: .dietaryCarbohydrates)
    static let healthFatObject = HKObjectType.quantityType(forIdentifier: .dietaryFatTotal)
    static let healthProteinObject = HKObjectType.quantityType(forIdentifier: .dietaryProtein)
    static let healthInsulinObject = HKObjectType.quantityType(forIdentifier: .insulinDelivery)

    // MetaDataKey of Trio data in HealthStore
    static let TrioInsulinType = "Trio Insulin Type"
}

final class BaseHealthKitManager: HealthKitManager, Injectable {
    @Injected() private var glucoseStorage: GlucoseStorage!
    @Injected() private var healthKitStore: HKHealthStore!
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var broadcaster: Broadcaster!
    @Injected() private var carbsStorage: CarbsStorage!
    @Injected() private var pumpHistoryStorage: PumpHistoryStorage!
    @Injected() private var deviceDataManager: DeviceDataManager!

    private var backgroundContext = CoreDataStack.shared.newTaskContext()

    private var coreDataPublisher: AnyPublisher<Set<NSManagedObject>, Never>?
    private var subscriptions = Set<AnyCancellable>()

    var isAvailableOnCurrentDevice: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    init(resolver: Resolver) {
        injectServices(resolver)

        coreDataPublisher =
            changedObjectsOnManagedObjectContextDidSavePublisher()
                .receive(on: DispatchQueue.global(qos: .background))
                .share()
                .eraseToAnyPublisher()

        glucoseStorage.updatePublisher
            .receive(on: DispatchQueue.global(qos: .background))
            .sink { [weak self] _ in
                guard let self = self else { return }
                Task {
                    await self.uploadGlucose()
                }
            }
            .store(in: &subscriptions)

        registerHandlers()

        guard isAvailableOnCurrentDevice,
              AppleHealthConfig.healthBGObject != nil else { return }

        debug(.service, "HealthKitManager did create")
    }

    private func registerHandlers() {
        coreDataPublisher?.filterByEntityName("PumpEventStored").sink { [weak self] _ in
            guard let self = self else { return }
            Task { [weak self] in
                guard let self = self else { return }
                await self.uploadInsulin()
            }
        }.store(in: &subscriptions)

        coreDataPublisher?.filterByEntityName("CarbEntryStored").sink { [weak self] _ in
            guard let self = self else { return }
            Task { [weak self] in
                guard let self = self else { return }
                await self.uploadCarbs()
            }
        }.store(in: &subscriptions)

        // This works only for manual Glucose
        coreDataPublisher?.filterByEntityName("GlucoseStored").sink { [weak self] _ in
            guard let self = self else { return }
            Task { [weak self] in
                guard let self = self else { return }
                await self.uploadGlucose()
            }
        }.store(in: &subscriptions)
    }

    func checkWriteToHealthPermissions(objectTypeToHealthStore: HKObjectType) -> Bool {
        healthKitStore.authorizationStatus(for: objectTypeToHealthStore) == .sharingAuthorized
    }

    var hasGrantedFullWritePermissions: Bool {
        Set(AppleHealthConfig.writePermissions.map { healthKitStore.authorizationStatus(for: $0) })
            .intersection([.sharingDenied, .notDetermined])
            .isEmpty
    }

    func hasGlucoseWritePermission() -> Bool {
        AppleHealthConfig.healthBGObject.map { checkWriteToHealthPermissions(objectTypeToHealthStore: $0) } ?? false
    }

    func requestPermission() async throws -> Bool {
        guard isAvailableOnCurrentDevice else {
            throw HKError.notAvailableOnCurrentDevice
        }

        return try await withCheckedThrowingContinuation { continuation in
            healthKitStore.requestAuthorization(
                toShare: AppleHealthConfig.writePermissions,
                read: nil
            ) { status, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: status)
                }
            }
        }
    }

    // Glucose Upload

    func uploadGlucose() async {
        await uploadGlucose(glucoseStorage.getGlucoseNotYetUploadedToHealth())
        await uploadGlucose(glucoseStorage.getManualGlucoseNotYetUploadedToHealth())
    }

    func uploadGlucose(_ glucose: [BloodGlucose]) async {
        guard settingsManager.settings.useAppleHealth,
              let sampleType = AppleHealthConfig.healthBGObject,
              checkWriteToHealthPermissions(objectTypeToHealthStore: sampleType),
              glucose.isNotEmpty
        else { return }

        do {
            // Create HealthKit samples from all the passed glucose values
            let glucoseSamples = glucose.compactMap { glucoseSample -> HKQuantitySample? in
                guard let glucoseValue = glucoseSample.glucose else { return nil }

                return HKQuantitySample(
                    type: sampleType,
                    quantity: HKQuantity(unit: .milligramsPerDeciliter, doubleValue: Double(glucoseValue)),
                    start: glucoseSample.dateString,
                    end: glucoseSample.dateString,
                    metadata: [
                        HKMetadataKeyExternalUUID: glucoseSample.id,
                        HKMetadataKeySyncIdentifier: glucoseSample.id,
                        HKMetadataKeySyncVersion: 1,
                        AppleHealthConfig.TrioInsulinType: deviceDataManager?.pumpManager?.status.insulinType?.title ?? ""
                    ]
                )
            }

            guard glucoseSamples.isNotEmpty else {
                debug(.service, "No glucose samples available for upload.")
                return
            }

            // Attempt to save the blood glucose samples to Apple Health
            try await healthKitStore.save(glucoseSamples)
            debug(.service, "Successfully stored \(glucoseSamples.count) blood glucose samples in HealthKit.")

            // After successful upload, update the isUploadedToHealth flag in Core Data
            await updateGlucoseAsUploaded(glucose)

        } catch {
            debug(.service, "Failed to upload glucose samples to HealthKit: \(error.localizedDescription)")
        }
    }

    private func updateGlucoseAsUploaded(_ glucose: [BloodGlucose]) async {
        await backgroundContext.perform {
            let ids = glucose.map(\.id) as NSArray
            let fetchRequest: NSFetchRequest<GlucoseStored> = GlucoseStored.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id IN %@", ids)

            do {
                let results = try self.backgroundContext.fetch(fetchRequest)
                for result in results {
                    result.isUploadedToHealth = true
                }

                guard self.backgroundContext.hasChanges else { return }
                try self.backgroundContext.save()
            } catch let error as NSError {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to update isUploadedToHealth: \(error.userInfo)"
                )
            }
        }
    }

    // Carbs Upload

    func uploadCarbs() async {
        await uploadCarbs(carbsStorage.getCarbsNotYetUploadedToHealth())
    }

    func uploadCarbs(_ carbs: [CarbsEntry]) async {
        guard settingsManager.settings.useAppleHealth,
              let carbSampleType = AppleHealthConfig.healthCarbObject,
              let fatSampleType = AppleHealthConfig.healthFatObject,
              let proteinSampleType = AppleHealthConfig.healthProteinObject,
              checkWriteToHealthPermissions(objectTypeToHealthStore: carbSampleType),
              carbs.isNotEmpty
        else { return }

        do {
            var samples: [HKQuantitySample] = []

            // Create HealthKit samples for carbs, fat, and protein
            for allSamples in carbs {
                guard let id = allSamples.id else { continue }
                let fpuID = allSamples.fpuID ?? id

                let startDate = allSamples.actualDate ?? Date()

                // Carbs Sample
                let carbValue = allSamples.carbs
                let carbSample = HKQuantitySample(
                    type: carbSampleType,
                    quantity: HKQuantity(unit: .gram(), doubleValue: Double(carbValue)),
                    start: startDate,
                    end: startDate,
                    metadata: [
                        HKMetadataKeyExternalUUID: id,
                        HKMetadataKeySyncIdentifier: id,
                        HKMetadataKeySyncVersion: 1
                    ]
                )
                samples.append(carbSample)

                // Fat Sample (if available)
                if let fatValue = allSamples.fat {
                    let fatSample = HKQuantitySample(
                        type: fatSampleType,
                        quantity: HKQuantity(unit: .gram(), doubleValue: Double(fatValue)),
                        start: startDate,
                        end: startDate,
                        metadata: [
                            HKMetadataKeyExternalUUID: fpuID,
                            HKMetadataKeySyncIdentifier: fpuID,
                            HKMetadataKeySyncVersion: 1
                        ]
                    )
                    samples.append(fatSample)
                }

                // Protein Sample (if available)
                if let proteinValue = allSamples.protein {
                    let proteinSample = HKQuantitySample(
                        type: proteinSampleType,
                        quantity: HKQuantity(unit: .gram(), doubleValue: Double(proteinValue)),
                        start: startDate,
                        end: startDate,
                        metadata: [
                            HKMetadataKeyExternalUUID: fpuID,
                            HKMetadataKeySyncIdentifier: fpuID,
                            HKMetadataKeySyncVersion: 1
                        ]
                    )
                    samples.append(proteinSample)
                }
            }

            // Attempt to save the samples to Apple Health
            guard samples.isNotEmpty else {
                debug(.service, "No samples available for upload.")
                return
            }

            try await healthKitStore.save(samples)
            debug(.service, "Successfully stored \(samples.count) carb samples in HealthKit.")

            // After successful upload, update the isUploadedToHealth flag in Core Data
            await updateCarbsAsUploaded(carbs)

        } catch {
            debug(.service, "Failed to upload carb samples to HealthKit: \(error.localizedDescription)")
        }
    }

    private func updateCarbsAsUploaded(_ carbs: [CarbsEntry]) async {
        await backgroundContext.perform {
            let ids = carbs.map(\.id) as NSArray
            let fetchRequest: NSFetchRequest<CarbEntryStored> = CarbEntryStored.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id IN %@", ids)

            do {
                let results = try self.backgroundContext.fetch(fetchRequest)
                for result in results {
                    result.isUploadedToHealth = true
                }

                guard self.backgroundContext.hasChanges else { return }
                try self.backgroundContext.save()
            } catch let error as NSError {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to update isUploadedToHealth: \(error.userInfo)"
                )
            }
        }
    }

    // Insulin Upload

    func uploadInsulin() async {
        await uploadInsulin(pumpHistoryStorage.getPumpHistoryNotYetUploadedToHealth())
    }

    func uploadInsulin(_ insulin: [PumpHistoryEvent]) async {
        guard settingsManager.settings.useAppleHealth,
              let sampleType = AppleHealthConfig.healthInsulinObject,
              checkWriteToHealthPermissions(objectTypeToHealthStore: sampleType),
              insulin.isNotEmpty
        else { return }

        // Fetch existing temp basal entries from Core Data for the last 24 hours
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: PumpEventStored.self,
            onContext: backgroundContext,
            predicate: NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate.pumpHistoryLast24h,
                NSPredicate(format: "tempBasal != nil")
            ]),
            key: "timestamp",
            ascending: true,
            batchSize: 50
        )

        // Initialize an array to hold the HealthKit samples to be uploaded
        var insulinSamples: [HKQuantitySample] = []

        // Perform the data processing on the background context
        await backgroundContext.perform {
            // Ensure that the fetched results are of the expected type
            guard let existingTempBasalEntries = results as? [PumpEventStored] else { return }

            // Create a mapping from timestamps to indices for quick access to existing entries
            let existingEntriesByTimestamp = Dictionary(
                uniqueKeysWithValues: existingTempBasalEntries.enumerated()
                    .map { ($0.element.timestamp, $0.offset) }
            )

            for event in insulin {
                switch event.type {
                case .bolus:
                    // For bolus events, create a HealthKit sample directly
                    if let sample = self.createSample(for: event, sampleType: sampleType) {
                        insulinSamples.append(sample)
                    }

                case .tempBasal:
                    // For temp basal events, process them and adjust overlapping durations if necessary
                    guard let duration = event.duration, let amount = event.amount else { continue }

                    // Calculate the total insulin delivered during the temp basal period
                    let value = (Decimal(duration) / 60.0) * amount

                    // Check if there's a matching existing temp basal entry
                    if let matchingEntryIndex = existingEntriesByTimestamp[event.timestamp] {
                        let predecessorIndex = matchingEntryIndex - 1
                        if predecessorIndex >= 0 {
                            // Get the predecessor entry to handle overlapping temp basal events
                            let predecessorEntry = existingTempBasalEntries[predecessorIndex]

                            // Adjust the predecessor entry if it overlaps with the current event
                            if let adjustedSample = self.processPredecessorEntry(
                                predecessorEntry,
                                nextEventTimestamp: event.timestamp,
                                sampleType: sampleType
                            ) {
                                insulinSamples.append(adjustedSample)
                            }
                        }

                        // Create a new PumpHistoryEvent with the calculated insulin value
                        let newEvent = PumpHistoryEvent(
                            id: event.id,
                            type: .tempBasal,
                            timestamp: event.timestamp,
                            amount: value,
                            duration: event.duration
                        )

                        // Create a HealthKit sample for the current temp basal event
                        if let sample = self.createSample(for: newEvent, sampleType: sampleType) {
                            insulinSamples.append(sample)
                        }
                    }

                default:
                    // Ignore other event types
                    break
                }
            }
        }

        // Save the processed insulin samples to HealthKit
        do {
            guard insulinSamples.isNotEmpty else {
                debug(.service, "No insulin samples available for upload.")
                return
            }

            // Attempt to save the samples to HealthKit
            try await healthKitStore.save(insulinSamples)
            debug(.service, "Successfully stored \(insulinSamples.count) insulin samples in HealthKit.")

            // Mark the insulin events as uploaded
            await updateInsulinAsUploaded(insulin)

        } catch {
            debug(.service, "Failed to upload insulin samples to HealthKit: \(error.localizedDescription)")
        }
    }

    // Helper function to create a HealthKit sample from a PumpHistoryEvent
    private func createSample(
        for event: PumpHistoryEvent,
        sampleType: HKQuantityType,
        isUpdate: Bool = false
    ) -> HKQuantitySample? {
        // Ensure the event has a valid insulin amount
        guard let insulinValue = event.amount else { return nil }

        // Determine the insulin delivery reason based on the event type
        let deliveryReason: HKInsulinDeliveryReason
        switch event.type {
        case .bolus:
            deliveryReason = .bolus
        case .tempBasal:
            deliveryReason = .basal
        default:
            return nil
        }

        // Calculate the end date based on the event duration
        let endDate = event.timestamp.addingTimeInterval(TimeInterval(minutes: Double(event.duration ?? 0)))

        // Create the HealthKit quantity sample with the appropriate metadata
        let sample = HKQuantitySample(
            type: sampleType,
            quantity: HKQuantity(unit: .internationalUnit(), doubleValue: Double(insulinValue)),
            start: event.timestamp,
            end: endDate,
            metadata: [
                HKMetadataKeyExternalUUID: event.id,
                HKMetadataKeySyncIdentifier: event.id,
                HKMetadataKeySyncVersion: !isUpdate ? 1 : 2,
                HKMetadataKeyInsulinDeliveryReason: deliveryReason.rawValue,
                AppleHealthConfig.TrioInsulinType: deviceDataManager?.pumpManager?.status.insulinType?.title ?? ""
            ]
        )

        return sample
    }

    // Helper function to process a predecessor temp basal entry and adjust overlapping durations
    private func processPredecessorEntry(
        _ predecessorEntry: PumpEventStored,
        nextEventTimestamp: Date,
        sampleType: HKQuantityType
    ) -> HKQuantitySample? {
        // Ensure the predecessor entry has the necessary data
        guard let predecessorTimestamp = predecessorEntry.timestamp,
              let predecessorEntryId = predecessorEntry.id else { return nil }

        // Calculate the original end date of the predecessor temp basal
        let predecessorDurationMinutes = predecessorEntry.tempBasal?.duration ?? 0
        let predecessorEndDate = predecessorTimestamp.addingTimeInterval(TimeInterval(predecessorDurationMinutes * 60))

        // Check if the predecessor temp basal overlaps with the next event
        if predecessorEndDate > nextEventTimestamp {
            // Adjust the end date to the start of the next event to prevent overlap
            let adjustedEndDate = nextEventTimestamp
            let adjustedDuration = adjustedEndDate.timeIntervalSince(predecessorTimestamp) // Precise duration in seconds

            // Calculate the insulin rate and adjusted delivered units
            let predecessorEntryRate = predecessorEntry.tempBasal?.rate?.doubleValue ?? 0
            
            // Round the rate to a supported basal rate using pumpManager's rounding function
            let roundedRate = deviceDataManager?.pumpManager?
                .roundToSupportedBasalRate(unitsPerHour: predecessorEntryRate) ?? predecessorEntryRate
            
            let adjustedDurationHours = adjustedDuration / 3600 // Precise duration in hours
            let adjustedDeliveredUnits = adjustedDurationHours * roundedRate

            // Recalculate the delivered units using the rounded rate
            let adjustedDeliveredUnitsRounded = adjustedDurationHours * adjustedDeliveredUnits

            // Create a new PumpHistoryEvent with the adjusted values
            let adjustedEvent = PumpHistoryEvent(
                id: predecessorEntryId,
                type: .tempBasal,
                timestamp: predecessorTimestamp,
                amount: Decimal(
                    deviceDataManager?.pumpManager?
                        .roundToSupportedBolusVolume(units: adjustedDeliveredUnitsRounded) ?? adjustedDeliveredUnitsRounded
                ),
                // Ensure this is a Decimal if needed
                duration: Int(
                    adjustedDuration /
                        60
                ) // Rounded to full minutes for display, but still using seconds for precise calculations
            )

            // Create and return the HealthKit sample for the adjusted event
            return createSample(for: adjustedEvent, sampleType: sampleType, isUpdate: true)
        }

        // If there is no overlap, no adjustment is needed
        return nil
    }

    private func updateInsulinAsUploaded(_ insulin: [PumpHistoryEvent]) async {
        await backgroundContext.perform {
            let ids = insulin.map(\.id) as NSArray
            let fetchRequest: NSFetchRequest<PumpEventStored> = PumpEventStored.fetchRequest()
            fetchRequest.predicate = NSPredicate(format: "id IN %@", ids)

            do {
                let results = try self.backgroundContext.fetch(fetchRequest)
                for result in results {
                    result.isUploadedToHealth = true
                }

                guard self.backgroundContext.hasChanges else { return }
                try self.backgroundContext.save()
            } catch let error as NSError {
                debugPrint(
                    "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to update isUploadedToHealth: \(error.userInfo)"
                )
            }
        }
    }

    // Delete Glucose/Carbs/Insulin

    func deleteGlucose(syncID: String) async {
        guard settingsManager.settings.useAppleHealth,
              let sampleType = AppleHealthConfig.healthBGObject,
              checkWriteToHealthPermissions(objectTypeToHealthStore: sampleType)
        else { return }

        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeySyncIdentifier,
            operatorType: .equalTo,
            value: syncID
        )

        do {
            try await deleteObjects(of: sampleType, predicate: predicate)
            debug(.service, "Successfully deleted glucose sample with syncID: \(syncID)")
        } catch {
            warning(.service, "Failed to delete glucose sample with syncID: \(syncID)", error: error)
        }
    }

    func deleteMealData(byID id: String, sampleType: HKSampleType) async {
        guard settingsManager.settings.useAppleHealth else { return }

        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeySyncIdentifier,
            operatorType: .equalTo,
            value: id
        )

        do {
            try await deleteObjects(of: sampleType, predicate: predicate)
            debug(.service, "Successfully deleted \(sampleType) with syncID: \(id)")
        } catch {
            warning(.service, "Failed to delete carbs sample with syncID: \(id)", error: error)
        }
    }

    func deleteInsulin(syncID: String) async {
        guard settingsManager.settings.useAppleHealth,
              let sampleType = AppleHealthConfig.healthInsulinObject,
              checkWriteToHealthPermissions(objectTypeToHealthStore: sampleType)
        else {
            debug(.service, "HealthKit permissions are not available for insulin deletion.")
            return
        }

        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeySyncIdentifier,
            operatorType: .equalTo,
            value: syncID
        )

        do {
            try await deleteObjects(of: sampleType, predicate: predicate)
            debug(.service, "Successfully deleted insulin sample with syncID: \(syncID)")
        } catch {
            warning(.service, "Failed to delete insulin sample with syncID: \(syncID)", error: error)
        }
    }

    private func deleteObjects(of sampleType: HKSampleType, predicate: NSPredicate) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            healthKitStore.deleteObjects(of: sampleType, predicate: predicate) { success, _, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}

enum HealthKitPermissionRequestStatus {
    case needRequest
    case didRequest
}

enum HKError: Error {
    // HealthKit work only iPhone (not on iPad)
    case notAvailableOnCurrentDevice
    // Some data can be not available on current iOS-device
    case dataNotAvailable
}

private struct InsulinBolus {
    var id: String
    var amount: Decimal
    var date: Date
}

private struct InsulinBasal {
    var id: String
    var amount: Decimal
    var startDelivery: Date
    var endDelivery: Date
}
