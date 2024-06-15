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
        await attemptToSaveContext()
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

        // Await the results of asynchronous tasks
        let pumpHistoryJSON = await parsePumpHistory(await pumpHistoryObjectIDs)
        let carbsAsJSON = await carbs
        let glucoseAsJSON = await glucose
        let oref2_variables = await oref2

        // TODO: - Save and fetch profile/basalProfile in/from UserDefaults!

        // Load files from Storage
        let profile = loadFileFromStorage(name: Settings.profile)
        let basalProfile = loadFileFromStorage(name: Settings.basalProfile)
        let autosens = loadFileFromStorage(name: Settings.autosense)
        let reservoir = loadFileFromStorage(name: Monitor.reservoir)
        let preferences = loadFileFromStorage(name: Settings.preferences)

        // Meal
        let meal: RawJSON = await withCheckedContinuation { continuation in
            self.processQueue.async {
                let result = self.meal(
                    pumphistory: pumpHistoryJSON,
                    profile: profile,
                    basalProfile: basalProfile,
                    clock: dateFormattedAsString,
                    carbs: carbsAsJSON,
                    glucose: glucoseAsJSON
                )
                continuation.resume(returning: result)
            }
        }

        // IOB
        let iob: RawJSON = await withCheckedContinuation { continuation in
            self.processQueue.async {
                let result = self.iob(
                    pumphistory: pumpHistoryJSON,
                    profile: profile,
                    clock: dateFormattedAsString,
                    autosens: autosens.isEmpty ? .null : autosens
                )
                continuation.resume(returning: result)
            }
        }

        storage.save(iob, as: Monitor.iob)

        // Determine basal
        let orefDetermination: RawJSON = await withCheckedContinuation { continuation in
            self.processQueue.async {
                let result = self.determineBasal(
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
                continuation.resume(returning: result)
            }
        }

        debug(.openAPS, "Determinated: \(orefDetermination)")

        if var determination = Determination(from: orefDetermination) {
            determination.timestamp = determination.deliverAt ?? clock

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

            var overrideArray = [Override]()
            let requestOverrides = Override.fetchRequest() as NSFetchRequest<Override>
            let sortOverride = NSSortDescriptor(key: "date", ascending: false)
            requestOverrides.sortDescriptors = [sortOverride]
            // requestOverrides.fetchLimit = 1
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
                    let saveToCoreData = Override(context: self.context)
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
                    smbIsAlwaysOff: overrideArray.first?.smbIsAlwaysOff ?? false,
                    start: (overrideArray.first?.start ?? 0) as Decimal,
                    end: (overrideArray.first?.end ?? 0) as Decimal,
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
                    smbIsAlwaysOff: overrideArray.first?.smbIsAlwaysOff ?? false,
                    start: (overrideArray.first?.start ?? 0) as Decimal,
                    end: (overrideArray.first?.end ?? 0) as Decimal,
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

        // Await the results of asynchronous tasks
        let pumpHistoryJSON = await parsePumpHistory(await pumpHistoryObjectIDs)
        let carbsAsJSON = await carbs
        let glucoseAsJSON = await glucose

        // Load files from Storage
        let profile = loadFileFromStorage(name: Settings.profile)
        let basalProfile = loadFileFromStorage(name: Settings.basalProfile)
        let tempTargets = loadFileFromStorage(name: Settings.tempTargets)

        // Autosense
        let autosenseResult: RawJSON = await withCheckedContinuation { continuation in
            self.processQueue.async {
                let result = self.autosense(
                    glucose: glucoseAsJSON,
                    pumpHistory: pumpHistoryJSON,
                    basalprofile: basalProfile,
                    profile: profile,
                    carbs: carbsAsJSON,
                    temptargets: tempTargets
                )
                continuation.resume(returning: result)
            }
        }

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

        // Await the results of asynchronous tasks
        let pumpHistoryJSON = await parsePumpHistory(await pumpHistoryObjectIDs)
        let carbsAsJSON = await carbs
        let glucoseAsJSON = await glucose

        // Load files from storage
        let profile = loadFileFromStorage(name: Settings.profile)
        let pumpProfile = loadFileFromStorage(name: Settings.pumpProfile)
        let previousAutotune = storage.retrieve(Settings.autotune, as: RawJSON.self)

        // Autotune
        let autotunePreppedGlucose: RawJSON = await withCheckedContinuation { continuation in
            self.processQueue.async {
                let result = self.autotunePrepare(
                    pumphistory: pumpHistoryJSON,
                    profile: profile,
                    glucose: glucoseAsJSON,
                    pumpprofile: pumpProfile,
                    carbs: carbsAsJSON,
                    categorizeUamAsBasal: categorizeUamAsBasal,
                    tuneInsulinCurve: tuneInsulinCurve
                )
                continuation.resume(returning: result)
            }
        }

        debug(.openAPS, "AUTOTUNE PREP: \(autotunePreppedGlucose)")

        let autotuneResult: RawJSON = await withCheckedContinuation { continuation in
            self.processQueue.async {
                let result = self.autotuneRun(
                    autotunePreparedData: autotunePreppedGlucose,
                    previousAutotuneResult: previousAutotune ?? profile,
                    pumpProfile: pumpProfile
                )
                continuation.resume(returning: result)
            }
        }

        debug(.openAPS, "AUTOTUNE RESULT: \(autotuneResult)")

        if let autotune = Autotune(from: autotuneResult) {
            storage.save(autotuneResult, as: Settings.autotune)

            return autotune
        } else {
            return nil
        }
    }

    func makeProfiles(useAutotune: Bool) async -> Autotune? {
        await withCheckedContinuation { continuation in
            debug(.openAPS, "Start makeProfiles")
            processQueue.async {
                var preferences = self.loadFileFromStorage(name: Settings.preferences)
                if preferences.isEmpty {
                    preferences = Preferences().rawJSON
                }
                let pumpSettings = self.loadFileFromStorage(name: Settings.settings)
                let bgTargets = self.loadFileFromStorage(name: Settings.bgTargets)
                let basalProfile = self.loadFileFromStorage(name: Settings.basalProfile)
                let isf = self.loadFileFromStorage(name: Settings.insulinSensitivities)
                let cr = self.loadFileFromStorage(name: Settings.carbRatios)
                let tempTargets = self.loadFileFromStorage(name: Settings.tempTargets)
                let model = self.loadFileFromStorage(name: Settings.model)
                let autotune = useAutotune ? self.loadFileFromStorage(name: Settings.autotune) : .empty
                let freeaps = self.loadFileFromStorage(name: FreeAPS.settings)

                let pumpProfile = self.makeProfile(
                    preferences: preferences,
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

                let profile = self.makeProfile(
                    preferences: preferences,
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

                self.storage.save(pumpProfile, as: Settings.pumpProfile)
                self.storage.save(profile, as: Settings.profile)

                if let tunedProfile = Autotune(from: profile) {
                    continuation.resume(returning: tunedProfile)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - Private

    private func iob(pumphistory: JSON, profile: JSON, clock: JSON, autosens: JSON) -> RawJSON {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return jsWorker.inCommonContext { worker in
            worker.evaluateBatch(scripts: [
                Script(name: Prepare.log),
                Script(name: Bundle.iob),
                Script(name: Prepare.iob)
            ])
            return worker.call(function: Function.generate, with: [
                pumphistory,
                profile,
                clock,
                autosens
            ])
        }
    }

    private func meal(pumphistory: JSON, profile: JSON, basalProfile: JSON, clock: JSON, carbs: JSON, glucose: JSON) -> RawJSON {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return jsWorker.inCommonContext { worker in
            worker.evaluateBatch(scripts: [
                Script(name: Prepare.log),
                Script(name: Bundle.meal),
                Script(name: Prepare.meal)
            ])
            return worker.call(function: Function.generate, with: [
                pumphistory,
                profile,
                clock,
                glucose,
                basalProfile,
                carbs
            ])
        }
    }

    private func autosense(
        glucose: JSON,
        pumpHistory: JSON,
        basalprofile: JSON,
        profile: JSON,
        carbs: JSON,
        temptargets: JSON
    ) -> RawJSON {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return jsWorker.inCommonContext { worker in
            worker.evaluateBatch(scripts: [
                Script(name: Prepare.log),
                Script(name: Bundle.autosens),
                Script(name: Prepare.autosens)
            ])
            return worker.call(function: Function.generate, with: [
                glucose,
                pumpHistory,
                basalprofile,
                profile,
                carbs,
                temptargets
            ])
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
    ) -> RawJSON {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return jsWorker.inCommonContext { worker in
            worker.evaluateBatch(scripts: [
                Script(name: Prepare.log),
                Script(name: Bundle.autotunePrep),
                Script(name: Prepare.autotunePrep)
            ])
            return worker.call(function: Function.generate, with: [
                pumphistory,
                profile,
                glucose,
                pumpprofile,
                carbs,
                categorizeUamAsBasal,
                tuneInsulinCurve
            ])
        }
    }

    private func autotuneRun(autotunePreparedData: JSON, previousAutotuneResult: JSON, pumpProfile: JSON) -> RawJSON {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return jsWorker.inCommonContext { worker in
            worker.evaluateBatch(scripts: [
                Script(name: Prepare.log),
                Script(name: Bundle.autotuneCore),
                Script(name: Prepare.autotuneCore)
            ])
            return worker.call(function: Function.generate, with: [
                autotunePreparedData,
                previousAutotuneResult,
                pumpProfile
            ])
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
    ) -> RawJSON {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return jsWorker.inCommonContext { worker in
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

            return worker.call(function: Function.generate, with: [
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
    ) -> RawJSON {
        dispatchPrecondition(condition: .onQueue(processQueue))
        return jsWorker.inCommonContext { worker in
            worker.evaluateBatch(scripts: [
                Script(name: Prepare.log),
                Script(name: Bundle.profile),
                Script(name: Prepare.profile)
            ])
            return worker.call(function: Function.generate, with: [
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
        }
    }

    private func loadJSON(name: String) -> String {
        try! String(contentsOf: Foundation.Bundle.main.url(forResource: "json/\(name)", withExtension: "json")!)
    }

    private func loadFileFromStorage(name: String) -> RawJSON {
        storage.retrieveRaw(name) ?? OpenAPS.defaults(for: name)
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
