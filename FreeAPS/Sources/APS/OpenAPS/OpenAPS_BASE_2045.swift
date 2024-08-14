import Combine
import CoreData
import Foundation
import JavaScriptCore

final class OpenAPS {
    private let jsWorker = JavaScriptWorker()
    private let processQueue = DispatchQueue(label: "OpenAPS.processQueue", qos: .utility)

    private let storage: FileStorage

    let context = CoreDataStack.shared.newTaskContext()

    let jsonConverter = JSONConverter()

    init(storage: FileStorage) {
        self.storage = storage
    }

    static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    // Helper function to convert a Decimal? to NSDecimalNumber?
    func decimalToNSDecimalNumber(_ value: Decimal?) -> NSDecimalNumber? {
        guard let value = value else { return nil }
        return NSDecimalNumber(decimal: value)
    }

    // Use the helper function for cleaner code
    func processDetermination(_ determination: Determination) async {
        await context.perform {
            let newOrefDetermination = OrefDetermination(context: self.context)
            newOrefDetermination.id = UUID()
            newOrefDetermination.totalDailyDose = self.decimalToNSDecimalNumber(determination.tdd)
            newOrefDetermination.insulinSensitivity = self.decimalToNSDecimalNumber(determination.isf)
            newOrefDetermination.currentTarget = self.decimalToNSDecimalNumber(determination.current_target)
            newOrefDetermination.eventualBG = determination.eventualBG.map(NSDecimalNumber.init)
            newOrefDetermination.deliverAt = determination.deliverAt
            newOrefDetermination.insulinForManualBolus = self.decimalToNSDecimalNumber(determination.insulinForManualBolus)
            newOrefDetermination.carbRatio = self.decimalToNSDecimalNumber(determination.carbRatio)
            newOrefDetermination.glucose = self.decimalToNSDecimalNumber(determination.bg)
            newOrefDetermination.reservoir = self.decimalToNSDecimalNumber(determination.reservoir)
            newOrefDetermination.insulinReq = self.decimalToNSDecimalNumber(determination.insulinReq)
            newOrefDetermination.temp = determination.temp?.rawValue ?? "absolute"
            newOrefDetermination.rate = self.decimalToNSDecimalNumber(determination.rate)
            newOrefDetermination.reason = determination.reason
            newOrefDetermination.duration = self.decimalToNSDecimalNumber(determination.duration)
            newOrefDetermination.iob = self.decimalToNSDecimalNumber(determination.iob)
            newOrefDetermination.threshold = self.decimalToNSDecimalNumber(determination.threshold)
            newOrefDetermination.minDelta = self.decimalToNSDecimalNumber(determination.minDelta)
            newOrefDetermination.sensitivityRatio = self.decimalToNSDecimalNumber(determination.sensitivityRatio)
            newOrefDetermination.expectedDelta = self.decimalToNSDecimalNumber(determination.expectedDelta)
            newOrefDetermination.cob = Int16(Int(determination.cob ?? 0))
            newOrefDetermination.manualBolusErrorString = self.decimalToNSDecimalNumber(determination.manualBolusErrorString)
            newOrefDetermination.tempBasal = determination.insulin?.temp_basal.map { NSDecimalNumber(decimal: $0) }
            newOrefDetermination.scheduledBasal = determination.insulin?.scheduled_basal.map { NSDecimalNumber(decimal: $0) }
            newOrefDetermination.bolus = determination.insulin?.bolus.map { NSDecimalNumber(decimal: $0) }
            newOrefDetermination.smbToDeliver = determination.units.map { NSDecimalNumber(decimal: $0) }
            newOrefDetermination.carbsRequired = Int16(Int(determination.carbsReq ?? 0))
            newOrefDetermination.isUploadedToNS = false

            if let predictions = determination.predictions {
                ["iob": predictions.iob, "zt": predictions.zt, "cob": predictions.cob, "uam": predictions.uam]
                    .forEach { type, values in
                        if let values = values {
                            let forecast = Forecast(context: self.context)
                            forecast.id = UUID()
                            forecast.type = type
                            forecast.date = Date()
                            forecast.orefDetermination = newOrefDetermination

                            for (index, value) in values.enumerated() {
                                let forecastValue = ForecastValue(context: self.context)
                                forecastValue.index = Int32(index)
                                forecastValue.value = Int32(value)
                                forecast.addToForecastValues(forecastValue)
                            }
                            newOrefDetermination.addToForecasts(forecast)
                        }
                    }
            }
        }

        // First save the current Determination to Core Data
        await attemptToSaveContext()

        // After that check for changes in iob and cob and if there are any post a custom Notification
        /// this is currently used to update Live Activity so that it stays up to date and not one loop cycle behind
        await checkForCobIobUpdate(determination)
    }

    func checkForCobIobUpdate(_ determination: Determination) async {
        let previousDeterminations = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: OrefDetermination.self,
            onContext: context,
            predicate: NSPredicate.predicateFor30MinAgoForDetermination,
            key: "deliverAt",
            ascending: false,
            fetchLimit: 2
        )

        // We need to get the second last Determination for this comparison because we have saved the current Determination already to Core Data
        if let previousDetermination = previousDeterminations.dropFirst().first {
            let iobChanged = previousDetermination.iob != decimalToNSDecimalNumber(determination.iob)
            let cobChanged = previousDetermination.cob != Int16(Int(determination.cob ?? 0))

            if iobChanged || cobChanged {
                Foundation.NotificationCenter.default.post(name: .didUpdateCobIob, object: nil)
            }
        }
    }

    func attemptToSaveContext() async {
        await context.perform {
            do {
                guard self.context.hasChanges else { return }
                try self.context.save()
            } catch {
                debugPrint("\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to save Determination to Core Data")
            }
        }
    }

    // fetch glucose to pass it to the meal function and to determine basal
    private func fetchAndProcessGlucose() async -> String {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: GlucoseStored.self,
            onContext: context,
            predicate: NSPredicate.predicateForSixHoursAgo,
            key: "date",
            ascending: false,
            fetchLimit: 72,
            batchSize: 24
        )

        return await context.perform {
            // convert to json
            return self.jsonConverter.convertToJSON(results)
        }
    }

    private func fetchAndProcessCarbs() async -> String {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: CarbEntryStored.self,
            onContext: context,
            predicate: NSPredicate.predicateForOneDayAgo,
            key: "date",
            ascending: false
        )

        // convert to json
        return await context.perform {
            return self.jsonConverter.convertToJSON(results)
        }
    }

    private func fetchPumpHistoryObjectIDs() async -> [NSManagedObjectID]? {
        let results = await CoreDataStack.shared.fetchEntitiesAsync(
            ofType: PumpEventStored.self,
            onContext: context,
            predicate: NSPredicate.pumpHistoryLast24h,
            key: "timestamp",
            ascending: false,
            batchSize: 50
        )
        return await context.perform {
            return results.map(\.objectID)
        }
    }

    private func parsePumpHistory(_ pumpHistoryObjectIDs: [NSManagedObjectID]) async -> String {
        // Return an empty JSON object if the list of object IDs is empty
        guard !pumpHistoryObjectIDs.isEmpty else { return "{}" }

        // Execute all operations on the background context
        return await context.perform {
            // Load the pump events from the object IDs
            let pumpHistory: [PumpEventStored] = pumpHistoryObjectIDs
                .compactMap { self.context.object(with: $0) as? PumpEventStored }

            // Create the DTOs
            let dtos: [PumpEventDTO] = pumpHistory.flatMap { event -> [PumpEventDTO] in
                var eventDTOs: [PumpEventDTO] = []
                if let bolusDTO = event.toBolusDTOEnum() {
                    eventDTOs.append(bolusDTO)
                }
                if let tempBasalDTO = event.toTempBasalDTOEnum() {
                    eventDTOs.append(tempBasalDTO)
                }
                if let tempBasalDurationDTO = event.toTempBasalDurationDTOEnum() {
                    eventDTOs.append(tempBasalDurationDTO)
                }
                return eventDTOs
            }

            // Convert the DTOs to JSON
            return self.jsonConverter.convertToJSON(dtos)
        }
    }

    func determineBasal(currentTemp: TempBasal, clock: Date = Date()) async throws -> Determination? {
        debug(.openAPS, "Start determineBasal")

        // clock
        let dateFormatted = OpenAPS.dateFormatter.string(from: clock)
        let dateFormattedAsString = "\"\(dateFormatted)\""

        // temp_basal
        let tempBasal = currentTemp.rawJSON

        // Perform asynchronous calls in parallel
        async let pumpHistoryObjectIDs = fetchPumpHistoryObjectIDs() ?? []
        async let carbs = fetchAndProcessCarbs()
        async let glucose = fetchAndProcessGlucose()
        async let oref2 = oref2()
        async let profileAsync = loadFileFromStorageAsync(name: Settings.profile)
        async let basalAsync = loadFileFromStorageAsync(name: Settings.basalProfile)
        async let autosenseAsync = loadFileFromStorageAsync(name: Settings.autosense)
        async let reservoirAsync = loadFileFromStorageAsync(name: Monitor.reservoir)
        async let preferencesAsync = loadFileFromStorageAsync(name: Settings.preferences)

        // Await the results of asynchronous tasks
        let (
            pumpHistoryJSON,
            carbsAsJSON,
            glucoseAsJSON,
            oref2_variables,
            profile,
            basalProfile,
            autosens,
            reservoir,
            preferences
        ) = await (
            parsePumpHistory(await pumpHistoryObjectIDs),
            carbs,
            glucose,
            oref2,
            profileAsync,
            basalAsync,
            autosenseAsync,
            reservoirAsync,
            preferencesAsync
        )

        // TODO: - Save and fetch profile/basalProfile in/from UserDefaults!

        // Meal
        let meal = try await self.meal(
            pumphistory: pumpHistoryJSON,
            profile: profile,
            basalProfile: basalProfile,
            clock: dateFormattedAsString,
            carbs: carbsAsJSON,
            glucose: glucoseAsJSON
        )

        // IOB
        let iob = try await self.iob(
            pumphistory: pumpHistoryJSON,
            profile: profile,
            clock: dateFormattedAsString,
            autosens: autosens.isEmpty ? .null : autosens
        )

        // TODO: refactor this to core data
        storage.save(iob, as: Monitor.iob)

        // Determine basal
        let orefDetermination = try await determineBasal(
            glucose: glucoseAsJSON,
            currentTemp: tempBasal,
            iob: iob,
            profile: profile,
            autosens: autosens.isEmpty ? .null : autosens,
            meal: meal,
            microBolusAllowed: true,
            reservoir: reservoir,
            pumpHistory: pumpHistoryJSON,
            preferences: preferences,
            basalProfile: basalProfile,
            oref2_variables: oref2_variables
        )

        debug(.openAPS, "Determinated: \(orefDetermination)")

        if var determination = Determination(from: orefDetermination), let deliverAt = determination.deliverAt {
            // set both timestamp and deliverAt to the SAME date; this will be updated for timestamp once it is enacted
            // AAPS does it the same way! we'll follow their example!
            determination.timestamp = deliverAt

            // save to core data asynchronously
            await processDetermination(determination)

            return determination
        } else {
            return nil
        }
    }

    func oref2() async -> RawJSON {
        await context.perform {
            let preferences = self.storage.retrieve(OpenAPS.Settings.preferences, as: Preferences.self)
            var hbt_ = preferences?.halfBasalExerciseTarget ?? 160
            let wp = preferences?.weightPercentage ?? 1
            let smbMinutes = (preferences?.maxSMBBasalMinutes ?? 30) as NSDecimalNumber
            let uamMinutes = (preferences?.maxUAMSMBBasalMinutes ?? 30) as NSDecimalNumber

            let tenDaysAgo = Date().addingTimeInterval(-10.days.timeInterval)
            let twoHoursAgo = Date().addingTimeInterval(-2.hours.timeInterval)

            var uniqueEvents = [OrefDetermination]()
            let requestTDD = OrefDetermination.fetchRequest() as NSFetchRequest<OrefDetermination>
            requestTDD.predicate = NSPredicate(format: "timestamp > %@ AND totalDailyDose > 0", tenDaysAgo as NSDate)
            requestTDD.propertiesToFetch = ["timestamp", "totalDailyDose"]
            let sortTDD = NSSortDescriptor(key: "timestamp", ascending: true)
            requestTDD.sortDescriptors = [sortTDD]
            try? uniqueEvents = self.context.fetch(requestTDD)

            var sliderArray = [TempTargetsSlider]()
            let requestIsEnbled = TempTargetsSlider.fetchRequest() as NSFetchRequest<TempTargetsSlider>
            let sortIsEnabled = NSSortDescriptor(key: "date", ascending: false)
            requestIsEnbled.sortDescriptors = [sortIsEnabled]
            // requestIsEnbled.fetchLimit = 1
            try? sliderArray = self.context.fetch(requestIsEnbled)

            /// Get the last active Override as only this information is apparently used in oref2
            var overrideArray = [OverrideStored]()
            let requestOverrides = OverrideStored.fetchRequest() as NSFetchRequest<OverrideStored>
            let sortOverride = NSSortDescriptor(key: "date", ascending: false)
            requestOverrides.sortDescriptors = [sortOverride]
            requestOverrides.predicate = NSPredicate.lastActiveOverride
            requestOverrides.fetchLimit = 1
            try? overrideArray = self.context.fetch(requestOverrides)

            var tempTargetsArray = [TempTargets]()
            let requestTempTargets = TempTargets.fetchRequest() as NSFetchRequest<TempTargets>
            let sortTT = NSSortDescriptor(key: "date", ascending: false)
            requestTempTargets.sortDescriptors = [sortTT]
            requestTempTargets.fetchLimit = 1
            try? tempTargetsArray = self.context.fetch(requestTempTargets)

            let total = uniqueEvents.compactMap({ each in each.totalDailyDose as? Decimal ?? 0 }).reduce(0, +)
            var indeces = uniqueEvents.count
            // Only fetch once. Use same (previous) fetch
            let twoHoursArray = uniqueEvents.filter({ ($0.timestamp ?? Date()) >= twoHoursAgo })
            var nrOfIndeces = twoHoursArray.count
            let totalAmount = twoHoursArray.compactMap({ each in each.totalDailyDose as? Decimal ?? 0 }).reduce(0, +)

            var temptargetActive = tempTargetsArray.first?.active ?? false
            let isPercentageEnabled = sliderArray.first?.enabled ?? false

            var useOverride = overrideArray.first?.enabled ?? false
            var overridePercentage = Decimal(overrideArray.first?.percentage ?? 100)
            var unlimited = overrideArray.first?.indefinite ?? true
            var disableSMBs = overrideArray.first?.smbIsOff ?? false

            let currentTDD = (uniqueEvents.last?.totalDailyDose ?? 0) as Decimal

            if indeces == 0 {
                indeces = 1
            }
            if nrOfIndeces == 0 {
                nrOfIndeces = 1
            }

            let average2hours = totalAmount / Decimal(nrOfIndeces)
            let average14 = total / Decimal(indeces)

            let weight = wp
            let weighted_average = weight * average2hours + (1 - weight) * average14

            var duration: Decimal = 0
            var newDuration: Decimal = 0
            var overrideTarget: Decimal = 0

            if useOverride {
                duration = (overrideArray.first?.duration ?? 0) as Decimal
                overrideTarget = (overrideArray.first?.target ?? 0) as Decimal
                let advancedSettings = overrideArray.first?.advancedSettings ?? false
                let addedMinutes = Int(duration)
                let date = overrideArray.first?.date ?? Date()
                if date.addingTimeInterval(addedMinutes.minutes.timeInterval) < Date(),
                   !unlimited
                {
                    useOverride = false
                    let saveToCoreData = OverrideStored(context: self.context)
                    saveToCoreData.enabled = false
                    saveToCoreData.date = Date()
                    saveToCoreData.duration = 0
                    saveToCoreData.indefinite = false
                    saveToCoreData.percentage = 100
                    do {
                        guard self.context.hasChanges else { return "{}" }
                        try self.context.save()
                    } catch {
                        print(error.localizedDescription)
                    }
                }
            }

            if !useOverride {
                unlimited = true
                overridePercentage = 100
                duration = 0
                overrideTarget = 0
                disableSMBs = false
            }

            if temptargetActive {
                var duration_ = 0
                var hbt = Double(hbt_)
                var dd = 0.0

                if temptargetActive {
                    duration_ = Int(truncating: tempTargetsArray.first?.duration ?? 0)
                    hbt = tempTargetsArray.first?.hbt ?? Double(hbt_)
                    let startDate = tempTargetsArray.first?.startDate ?? Date()
                    let durationPlusStart = startDate.addingTimeInterval(duration_.minutes.timeInterval)
                    dd = durationPlusStart.timeIntervalSinceNow.minutes

                    if dd > 0.1 {
                        hbt_ = Decimal(hbt)
                        temptargetActive = true
                    } else {
                        temptargetActive = false
                    }
                }
            }

            if currentTDD > 0 {
                let averages = Oref2_variables(
                    average_total_data: average14,
                    weightedAverage: weighted_average,
                    past2hoursAverage: average2hours,
                    date: Date(),
                    isEnabled: temptargetActive,
                    presetActive: isPercentageEnabled,
                    overridePercentage: overridePercentage,
                    useOverride: useOverride,
                    duration: duration,
                    unlimited: unlimited,
                    hbt: hbt_,
                    overrideTarget: overrideTarget,
                    smbIsOff: disableSMBs,
                    advancedSettings: overrideArray.first?.advancedSettings ?? false,
                    isfAndCr: overrideArray.first?.isfAndCr ?? false,
                    isf: overrideArray.first?.isf ?? false,
                    cr: overrideArray.first?.cr ?? false,
                    smbMinutes: (overrideArray.first?.smbMinutes ?? smbMinutes) as Decimal,
                    uamMinutes: (overrideArray.first?.uamMinutes ?? uamMinutes) as Decimal
                )

                self.storage.save(averages, as: OpenAPS.Monitor.oref2_variables)

                return self.loadFileFromStorage(name: Monitor.oref2_variables)

            } else {
                let averages = Oref2_variables(
                    average_total_data: 0,
                    weightedAverage: 1,
                    past2hoursAverage: 0,
                    date: Date(),
                    isEnabled: temptargetActive,
                    presetActive: isPercentageEnabled,
                    overridePercentage: overridePercentage,
                    useOverride: useOverride,
                    duration: duration,
                    unlimited: unlimited,
                    hbt: hbt_,
                    overrideTarget: overrideTarget,
                    smbIsOff: disableSMBs,
                    advancedSettings: overrideArray.first?.advancedSettings ?? false,
                    isfAndCr: overrideArray.first?.isfAndCr ?? false,
                    isf: overrideArray.first?.isf ?? false,
                    cr: overrideArray.first?.cr ?? false,
                    smbMinutes: (overrideArray.first?.smbMinutes ?? smbMinutes) as Decimal,
                    uamMinutes: (overrideArray.first?.uamMinutes ?? uamMinutes) as Decimal
                )
                self.storage.save(averages, as: OpenAPS.Monitor.oref2_variables)
                return self.loadFileFromStorage(name: Monitor.oref2_variables)
            }
        }
    }

    func autosense() async throws -> Autosens? {
        debug(.openAPS, "Start autosens")

        // Perform asynchronous calls in parallel
        async let pumpHistoryObjectIDs = fetchPumpHistoryObjectIDs() ?? []
        async let carbs = fetchAndProcessCarbs()
        async let glucose = fetchAndProcessGlucose()
        async let getProfile = loadFileFromStorageAsync(name: Settings.profile)
        async let getBasalProfile = loadFileFromStorageAsync(name: Settings.basalProfile)
        async let getTempTargets = loadFileFromStorageAsync(name: Settings.tempTargets)

        // Await the results of asynchronous tasks
        let (pumpHistoryJSON, carbsAsJSON, glucoseAsJSON, profile, basalProfile, tempTargets) = await (
            parsePumpHistory(await pumpHistoryObjectIDs),
            carbs,
            glucose,
            getProfile,
            getBasalProfile,
            getTempTargets
        )

        // Autosense
        let autosenseResult = try await autosense(
            glucose: glucoseAsJSON,
            pumpHistory: pumpHistoryJSON,
            basalprofile: basalProfile,
            profile: profile,
            carbs: carbsAsJSON,
            temptargets: tempTargets
        )

        debug(.openAPS, "AUTOSENS: \(autosenseResult)")
        if var autosens = Autosens(from: autosenseResult) {
            autosens.timestamp = Date()
            storage.save(autosens, as: Settings.autosense)

            return autosens
        } else {
            return nil
        }
    }

    func autotune(categorizeUamAsBasal: Bool = false, tuneInsulinCurve: Bool = false) async -> Autotune? {
        debug(.openAPS, "Start autotune")

        // Perform asynchronous calls in parallel
        async let pumpHistoryObjectIDs = fetchPumpHistoryObjectIDs() ?? []
        async let carbs = fetchAndProcessCarbs()
        async let glucose = fetchAndProcessGlucose()
        async let getProfile = loadFileFromStorageAsync(name: Settings.profile)
        async let getPumpProfile = loadFileFromStorageAsync(name: Settings.pumpProfile)
        async let getPreviousAutotune = storage.retrieveAsync(Settings.autotune, as: RawJSON.self)

        // Await the results of asynchronous tasks
        let (pumpHistoryJSON, carbsAsJSON, glucoseAsJSON, profile, pumpProfile, previousAutotune) = await (
            parsePumpHistory(await pumpHistoryObjectIDs),
            carbs,
            glucose,
            getProfile,
            getPumpProfile,
            getPreviousAutotune
        )

        // Error need to be handled here because the function is not declared as throws
        do {
            // Autotune Prepare
            let autotunePreppedGlucose = try await autotunePrepare(
                pumphistory: pumpHistoryJSON,
                profile: profile,
                glucose: glucoseAsJSON,
                pumpprofile: pumpProfile,
                carbs: carbsAsJSON,
                categorizeUamAsBasal: categorizeUamAsBasal,
                tuneInsulinCurve: tuneInsulinCurve
            )

            debug(.openAPS, "AUTOTUNE PREP: \(autotunePreppedGlucose)")

            // Autotune Run
            let autotuneResult = try await autotuneRun(
                autotunePreparedData: autotunePreppedGlucose,
                previousAutotuneResult: previousAutotune ?? profile,
                pumpProfile: pumpProfile
            )

            debug(.openAPS, "AUTOTUNE RESULT: \(autotuneResult)")

            if let autotune = Autotune(from: autotuneResult) {
                storage.save(autotuneResult, as: Settings.autotune)

                return autotune
            } else {
                return nil
            }
        } catch {
            debug(.openAPS, "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to prepare/run Autotune")
            return nil
        }
    }

    func makeProfiles(useAutotune _: Bool) async -> Autotune? {
        debug(.openAPS, "Start makeProfiles")

        async let getPreferences = loadFileFromStorageAsync(name: Settings.preferences)
        async let getPumpSettings = loadFileFromStorageAsync(name: Settings.settings)
        async let getBGTargets = loadFileFromStorageAsync(name: Settings.bgTargets)
        async let getBasalProfile = loadFileFromStorageAsync(name: Settings.basalProfile)
        async let getISF = loadFileFromStorageAsync(name: Settings.insulinSensitivities)
        async let getCR = loadFileFromStorageAsync(name: Settings.carbRatios)
        async let getTempTargets = loadFileFromStorageAsync(name: Settings.tempTargets)
        async let getModel = loadFileFromStorageAsync(name: Settings.model)
        async let getAutotune = loadFileFromStorageAsync(name: Settings.autotune)
        async let getFreeAPS = loadFileFromStorageAsync(name: FreeAPS.settings)

        let (preferences, pumpSettings, bgTargets, basalProfile, isf, cr, tempTargets, model, autotune, freeaps) = await (
            getPreferences,
            getPumpSettings,
            getBGTargets,
            getBasalProfile,
            getISF,
            getCR,
            getTempTargets,
            getModel,
            getAutotune,
            getFreeAPS
        )

        var adjustedPreferences = preferences
        if adjustedPreferences.isEmpty {
            adjustedPreferences = Preferences().rawJSON
        }

        do {
            // Pump Profile
            let pumpProfile = try await makeProfile(
                preferences: adjustedPreferences,
                pumpSettings: pumpSettings,
                bgTargets: bgTargets,
                basalProfile: basalProfile,
                isf: isf,
                carbRatio: cr,
                tempTargets: tempTargets,
                model: model,
                autotune: RawJSON.null,
                freeaps: freeaps
            )

            // Profile
            let profile = try await makeProfile(
                preferences: adjustedPreferences,
                pumpSettings: pumpSettings,
                bgTargets: bgTargets,
                basalProfile: basalProfile,
                isf: isf,
                carbRatio: cr,
                tempTargets: tempTargets,
                model: model,
                autotune: autotune.isEmpty ? .null : autotune,
                freeaps: freeaps
            )

            await storage.saveAsync(pumpProfile, as: Settings.pumpProfile)
            await storage.saveAsync(profile, as: Settings.profile)

            if let tunedProfile = Autotune(from: profile) {
                return tunedProfile
            } else {
                return nil
            }
        } catch {
            debug(
                .apsManager,
                "\(DebuggingIdentifiers.failed) \(#file) \(#function) Failed to execute makeProfiles() to return Autoune results"
            )
            return nil
        }
    }

    // MARK: - Private

    private func iob(pumphistory: JSON, profile: JSON, clock: JSON, autosens: JSON) async throws -> RawJSON {
        await withCheckedContinuation { continuation in
            jsWorker.inCommonContext { worker in
                worker.evaluateBatch(scripts: [
                    Script(name: Prepare.log),
                    Script(name: Bundle.iob),
                    Script(name: Prepare.iob)
                ])
                let result = worker.call(function: Function.generate, with: [
                    pumphistory,
                    profile,
                    clock,
                    autosens
                ])
                continuation.resume(returning: result)
            }
        }
    }

    private func meal(
        pumphistory: JSON,
        profile: JSON,
        basalProfile: JSON,
        clock: JSON,
        carbs: JSON,
        glucose: JSON
    ) async throws -> RawJSON {
        try await withCheckedThrowingContinuation { continuation in
            jsWorker.inCommonContext { worker in
                worker.evaluateBatch(scripts: [
                    Script(name: Prepare.log),
                    Script(name: Bundle.meal),
                    Script(name: Prepare.meal)
                ])
                let result = worker.call(function: Function.generate, with: [
                    pumphistory,
                    profile,
                    clock,
                    glucose,
                    basalProfile,
                    carbs
                ])
                continuation.resume(returning: result)
            }
        }
    }

    private func autosense(
        glucose: JSON,
        pumpHistory: JSON,
        basalprofile: JSON,
        profile: JSON,
        carbs: JSON,
        temptargets: JSON
    ) async throws -> RawJSON {
        try await withCheckedThrowingContinuation { continuation in
            jsWorker.inCommonContext { worker in
                worker.evaluateBatch(scripts: [
                    Script(name: Prepare.log),
                    Script(name: Bundle.autosens),
                    Script(name: Prepare.autosens)
                ])
                let result = worker.call(function: Function.generate, with: [
                    glucose,
                    pumpHistory,
                    basalprofile,
                    profile,
                    carbs,
                    temptargets
                ])
                continuation.resume(returning: result)
            }
        }
    }

    private func autotunePrepare(
        pumphistory: JSON,
        profile: JSON,
        glucose: JSON,
        pumpprofile: JSON,
        carbs: JSON,
        categorizeUamAsBasal: Bool,
        tuneInsulinCurve: Bool
    ) async throws -> RawJSON {
        try await withCheckedThrowingContinuation { continuation in
            jsWorker.inCommonContext { worker in
                worker.evaluateBatch(scripts: [
                    Script(name: Prepare.log),
                    Script(name: Bundle.autotunePrep),
                    Script(name: Prepare.autotunePrep)
                ])
                let result = worker.call(function: Function.generate, with: [
                    pumphistory,
                    profile,
                    glucose,
                    pumpprofile,
                    carbs,
                    categorizeUamAsBasal,
                    tuneInsulinCurve
                ])
                continuation.resume(returning: result)
            }
        }
    }

    private func autotuneRun(
        autotunePreparedData: JSON,
        previousAutotuneResult: JSON,
        pumpProfile: JSON
    ) async throws -> RawJSON {
        try await withCheckedThrowingContinuation { continuation in
            jsWorker.inCommonContext { worker in
                worker.evaluateBatch(scripts: [
                    Script(name: Prepare.log),
                    Script(name: Bundle.autotuneCore),
                    Script(name: Prepare.autotuneCore)
                ])
                let result = worker.call(function: Function.generate, with: [
                    autotunePreparedData,
                    previousAutotuneResult,
                    pumpProfile
                ])
                continuation.resume(returning: result)
            }
        }
    }

    private func determineBasal(
        glucose: JSON,
        currentTemp: JSON,
        iob: JSON,
        profile: JSON,
        autosens: JSON,
        meal: JSON,
        microBolusAllowed: Bool,
        reservoir: JSON,
        pumpHistory: JSON,
        preferences: JSON,
        basalProfile: JSON,
        oref2_variables: JSON
    ) async throws -> RawJSON {
        try await withCheckedThrowingContinuation { continuation in
            jsWorker.inCommonContext { worker in
                worker.evaluateBatch(scripts: [
                    Script(name: Prepare.log),
                    Script(name: Prepare.determineBasal),
                    Script(name: Bundle.basalSetTemp),
                    Script(name: Bundle.getLastGlucose),
                    Script(name: Bundle.determineBasal)
                ])

                if let middleware = self.middlewareScript(name: OpenAPS.Middleware.determineBasal) {
                    worker.evaluate(script: middleware)
                }

                let result = worker.call(function: Function.generate, with: [
                    iob,
                    currentTemp,
                    glucose,
                    profile,
                    autosens,
                    meal,
                    microBolusAllowed,
                    reservoir,
                    Date(),
                    pumpHistory,
                    preferences,
                    basalProfile,
                    oref2_variables
                ])

                continuation.resume(returning: result)
            }
        }
    }

    private func exportDefaultPreferences() -> RawJSON {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return jsWorker.inCommonContext { worker in
            worker.evaluateBatch(scripts: [
                Script(name: Prepare.log),
                Script(name: Bundle.profile),
                Script(name: Prepare.profile)
            ])
            return worker.call(function: Function.exportDefaults, with: [])
        }
    }

    private func makeProfile(
        preferences: JSON,
        pumpSettings: JSON,
        bgTargets: JSON,
        basalProfile: JSON,
        isf: JSON,
        carbRatio: JSON,
        tempTargets: JSON,
        model: JSON,
        autotune: JSON,
        freeaps: JSON
    ) async throws -> RawJSON {
        try await withCheckedThrowingContinuation { continuation in
            jsWorker.inCommonContext { worker in
                worker.evaluateBatch(scripts: [
                    Script(name: Prepare.log),
                    Script(name: Bundle.profile),
                    Script(name: Prepare.profile)
                ])
                let result = worker.call(function: Function.generate, with: [
                    pumpSettings,
                    bgTargets,
                    isf,
                    basalProfile,
                    preferences,
                    carbRatio,
                    tempTargets,
                    model,
                    autotune,
                    freeaps
                ])
                continuation.resume(returning: result)
            }
        }
    }

    private func loadJSON(name: String) -> String {
        try! String(contentsOf: Foundation.Bundle.main.url(forResource: "json/\(name)", withExtension: "json")!)
    }

    private func loadFileFromStorage(name: String) -> RawJSON {
        storage.retrieveRaw(name) ?? OpenAPS.defaults(for: name)
    }

    private func loadFileFromStorageAsync(name: String) async -> RawJSON {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.storage.retrieveRaw(name) ?? OpenAPS.defaults(for: name)
                continuation.resume(returning: result)
            }
        }
    }

    private func middlewareScript(name: String) -> Script? {
        if let body = storage.retrieveRaw(name) {
            return Script(name: "Middleware", body: body)
        }

        if let url = Foundation.Bundle.main.url(forResource: "javascript/\(name)", withExtension: "") {
            return Script(name: "Middleware", body: try! String(contentsOf: url))
        }

        return nil
    }

    static func defaults(for file: String) -> RawJSON {
        let prefix = file.hasSuffix(".json") ? "json/defaults" : "javascript"
        guard let url = Foundation.Bundle.main.url(forResource: "\(prefix)/\(file)", withExtension: "") else {
            return ""
        }
        return (try? String(contentsOf: url)) ?? ""
    }

    func processAndSave(forecastData: [String: [Int]]) {
        let currentDate = Date()

        context.perform {
            for (type, values) in forecastData {
                self.createForecast(type: type, values: values, date: currentDate, context: self.context)
            }

            do {
                guard self.context.hasChanges else { return }
                try self.context.save()
            } catch {
                print(error.localizedDescription)
            }
        }
    }

    func createForecast(type: String, values: [Int], date: Date, context: NSManagedObjectContext) {
        let forecast = Forecast(context: context)
        forecast.id = UUID()
        forecast.date = date
        forecast.type = type

        for (index, value) in values.enumerated() {
            let forecastValue = ForecastValue(context: context)
            forecastValue.value = Int32(value)
            forecastValue.index = Int32(index)
            forecastValue.forecast = forecast
        }
    }
}
