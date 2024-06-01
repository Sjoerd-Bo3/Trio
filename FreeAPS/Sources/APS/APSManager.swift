import Combine
import CoreData
import Foundation
import LoopKit
import LoopKitUI
import OmniBLE
import OmniKit
import RileyLinkKit
import SwiftDate
import Swinject

protocol APSManager {
    func heartbeat(date: Date)
    func autotune() -> AnyPublisher<Autotune?, Never>
    func enactBolus(amount: Double, isSMB: Bool) async
    var pumpManager: PumpManagerUI? { get set }
    var bluetoothManager: BluetoothStateManager? { get }
    var pumpDisplayState: CurrentValueSubject<PumpDisplayState?, Never> { get }
    var pumpName: CurrentValueSubject<String, Never> { get }
    var isLooping: CurrentValueSubject<Bool, Never> { get }
    var lastLoopDate: Date { get }
    var lastLoopDateSubject: PassthroughSubject<Date, Never> { get }
    var bolusProgress: CurrentValueSubject<Decimal?, Never> { get }
    var pumpExpiresAtDate: CurrentValueSubject<Date?, Never> { get }
    var isManualTempBasal: Bool { get }
    func enactTempBasal(rate: Double, duration: TimeInterval) async
    func makeProfiles() -> AnyPublisher<Bool, Never>
    func determineBasal() -> AnyPublisher<Bool, Never>
    func determineBasalSync()
    func roundBolus(amount: Decimal) -> Decimal
    var lastError: CurrentValueSubject<Error?, Never> { get }
    func cancelBolus() async
    func enactAnnouncement(_ announcement: Announcement)
}

enum APSError: LocalizedError {
    case pumpError(Error)
    case invalidPumpState(message: String)
    case glucoseError(message: String)
    case apsError(message: String)
    case deviceSyncError(message: String)
    case manualBasalTemp(message: String)

    var errorDescription: String? {
        switch self {
        case let .pumpError(error):
            return "Pump error: \(error.localizedDescription)"
        case let .invalidPumpState(message):
            return "Error: Invalid Pump State: \(message)"
        case let .glucoseError(message):
            return "Error: Invalid glucose: \(message)"
        case let .apsError(message):
            return "APS error: \(message)"
        case let .deviceSyncError(message):
            return "Sync error: \(message)"
        case let .manualBasalTemp(message):
            return "Manual Basal Temp : \(message)"
        }
    }
}

final class BaseAPSManager: APSManager, Injectable {
    private let processQueue = DispatchQueue(label: "BaseAPSManager.processQueue")
    @Injected() private var storage: FileStorage!
    @Injected() private var pumpHistoryStorage: PumpHistoryStorage!
    @Injected() private var alertHistoryStorage: AlertHistoryStorage!
    @Injected() private var tempTargetsStorage: TempTargetsStorage!
    @Injected() private var carbsStorage: CarbsStorage!
    @Injected() private var announcementsStorage: AnnouncementsStorage!
    @Injected() private var deviceDataManager: DeviceDataManager!
    @Injected() private var nightscout: NightscoutManager!
    @Injected() private var settingsManager: SettingsManager!
    @Injected() private var broadcaster: Broadcaster!
    @Persisted(key: "lastAutotuneDate") private var lastAutotuneDate = Date()
    @Persisted(key: "lastStartLoopDate") private var lastStartLoopDate: Date = .distantPast
    @Persisted(key: "lastLoopDate") var lastLoopDate: Date = .distantPast {
        didSet {
            lastLoopDateSubject.send(lastLoopDate)
        }
    }

    private var cleanupTimer: Timer?
    @Persisted(key: "lastHistoryCleanupDate") private var lastHistoryCleanupDate = Date.distantPast
    @Persisted(key: "lastPurgeDate") private var lastPurgeDate = Date.distantPast

    let viewContext = CoreDataStack.shared.persistentContainer.viewContext
    let privateContext = CoreDataStack.shared.newTaskContext()

    private var openAPS: OpenAPS!

    private var lifetime = Lifetime()

    private var backGroundTaskID: UIBackgroundTaskIdentifier?

    var pumpManager: PumpManagerUI? {
        get { deviceDataManager.pumpManager }
        set { deviceDataManager.pumpManager = newValue }
    }

    var bluetoothManager: BluetoothStateManager? { deviceDataManager.bluetoothManager }

    @Persisted(key: "isManualTempBasal") var isManualTempBasal: Bool = false

    let isLooping = CurrentValueSubject<Bool, Never>(false)
    let lastLoopDateSubject = PassthroughSubject<Date, Never>()
    let lastError = CurrentValueSubject<Error?, Never>(nil)

    let bolusProgress = CurrentValueSubject<Decimal?, Never>(nil)

    var pumpDisplayState: CurrentValueSubject<PumpDisplayState?, Never> {
        deviceDataManager.pumpDisplayState
    }

    var pumpName: CurrentValueSubject<String, Never> {
        deviceDataManager.pumpName
    }

    var pumpExpiresAtDate: CurrentValueSubject<Date?, Never> {
        deviceDataManager.pumpExpiresAtDate
    }

    var settings: FreeAPSSettings {
        get { settingsManager.settings }
        set { settingsManager.settings = newValue }
    }

    init(resolver: Resolver) {
        injectServices(resolver)
        openAPS = OpenAPS(storage: storage)
        subscribe()
        lastLoopDateSubject.send(lastLoopDate)

        isLooping
            .weakAssign(to: \.deviceDataManager.loopInProgress, on: self)
            .store(in: &lifetime)
        startCleanupTimer()
    }

    private func startCleanupTimer() {
        // Call the timer once every 12 hours to ensure that no clean gets missed
        cleanupTimer = Timer.scheduledTimer(withTimeInterval: 12 * 60 * 60, repeats: true) { [weak self] _ in
            self?.performCleanupIfNeeded()
        }
        RunLoop.current.add(cleanupTimer!, forMode: .common)
    }

    private func performCleanupIfNeeded() {
        let now = Date()
        let calendar = Calendar.current

        // Check if last clean is longer than one day ago
        if !calendar.isDateInToday(lastHistoryCleanupDate) {
            // Perform daily cleanup
            Task {
                await CoreDataStack.shared.cleanupPersistentHistoryTokens(before: Date.oneWeekAgo)
                // Update lastHistoryCleanupDate only if cleanup was successful
                lastHistoryCleanupDate = now
            }
        }

        // Check if last purge is longer than one week ago
        if let lastPurge = calendar.date(byAdding: .day, value: 7, to: lastPurgeDate), now >= lastPurge {
            // Perform weekly purge
            Task {
                do {
                    try await purgeOldNSManagedObjects()
                    // Update lastPurgeDate only if purge was successful
                    lastPurgeDate = now
                } catch {
                    debugPrint("Failed to purge old managed objects: \(error.localizedDescription)")
                }
            }
        }
    }

    private func purgeOldNSManagedObjects() async throws {
        try await CoreDataStack.shared.batchDeleteOlderThan(GlucoseStored.self, dateKey: "date", days: 90)
        try await CoreDataStack.shared.batchDeleteOlderThan(PumpEventStored.self, dateKey: "timestamp", days: 90)
        try await CoreDataStack.shared.batchDeleteOlderThan(OrefDetermination.self, dateKey: "deliverAt", days: 90)
        try await CoreDataStack.shared.batchDeleteOlderThan(OpenAPS_Battery.self, dateKey: "date", days: 90)
        try await CoreDataStack.shared.batchDeleteOlderThan(CarbEntryStored.self, dateKey: "date", days: 90)
        try await CoreDataStack.shared.batchDeleteOlderThan(Forecast.self, dateKey: "date", days: 90)

        // TODO: - Purge Data of other (future) entities as well
    }

    private func subscribe() {
        deviceDataManager.recommendsLoop
            .receive(on: processQueue)
            .sink { [weak self] in
                self?.loop()
            }
            .store(in: &lifetime)
        pumpManager?.addStatusObserver(self, queue: processQueue)

        deviceDataManager.errorSubject
            .receive(on: processQueue)
            .map { APSError.pumpError($0) }
            .sink {
                self.processError($0)
            }
            .store(in: &lifetime)

        deviceDataManager.bolusTrigger
            .receive(on: processQueue)
            .sink { bolusing in
                if bolusing {
                    self.createBolusReporter()
                } else {
                    self.clearBolusReporter()
                }
            }
            .store(in: &lifetime)

        // manage a manual Temp Basal from OmniPod - Force loop() after stop a temp basal or finished
        deviceDataManager.manualTempBasal
            .receive(on: processQueue)
            .sink { manualBasal in
                if manualBasal {
                    self.isManualTempBasal = true
                } else {
                    if self.isManualTempBasal {
                        self.isManualTempBasal = false
                        self.loop()
                    }
                }
            }
            .store(in: &lifetime)
    }

    func heartbeat(date: Date) {
        deviceDataManager.heartbeat(date: date)
    }

    // Loop entry point
    private func loop() {
        // check the last start of looping is more the loopInterval but the previous loop was completed
        if lastLoopDate > lastStartLoopDate {
            guard lastStartLoopDate.addingTimeInterval(Config.loopInterval) < Date() else {
                debug(.apsManager, "too close to do a loop : \(lastStartLoopDate)")
                return
            }
        }

        guard !isLooping.value else {
            warning(.apsManager, "Loop already in progress. Skip recommendation.")
            return
        }

        // start background time extension
        backGroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "Loop starting") {
            guard let backgroundTask = self.backGroundTaskID else { return }
            UIApplication.shared.endBackgroundTask(backgroundTask)
            self.backGroundTaskID = .invalid
        }

        debug(.apsManager, "Starting loop with a delay of \(UIApplication.shared.backgroundTimeRemaining.rounded())")

        lastStartLoopDate = Date()

        var previousLoop = [LoopStatRecord]()
        var interval: Double?

        viewContext.performAndWait {
            let requestStats = LoopStatRecord.fetchRequest() as NSFetchRequest<LoopStatRecord>
            let sortStats = NSSortDescriptor(key: "end", ascending: false)
            requestStats.sortDescriptors = [sortStats]
            requestStats.fetchLimit = 1
            try? previousLoop = viewContext.fetch(requestStats)

            if (previousLoop.first?.end ?? .distantFuture) < lastStartLoopDate {
                interval = roundDouble((lastStartLoopDate - (previousLoop.first?.end ?? Date())).timeInterval / 60, 1)
            }
        }

        var loopStatRecord = LoopStats(
            start: lastStartLoopDate,
            loopStatus: "Starting",
            interval: interval
        )

        isLooping.send(true)
        determineBasal()
            .replaceEmpty(with: false)
            .flatMap { [weak self] success -> AnyPublisher<Void, Error> in
                guard let self = self, success else {
                    return Fail(error: APSError.apsError(message: "Determine basal failed")).eraseToAnyPublisher()
                }

                // Open loop completed
                guard self.settings.closedLoop else {
                    self.nightscout.uploadStatus()
                    return Just(()).setFailureType(to: Error.self).eraseToAnyPublisher()
                }

                self.nightscout.uploadStatus()

                // Closed loop - enact Determination
                return Future { promise in
                    Task {
                        do {
                            try await self.enactDetermination()
                            promise(.success(()))
                        } catch {
                            promise(.failure(error))
                        }
                    }
                }.eraseToAnyPublisher()
            }
            .sink { [weak self] completion in
                guard let self = self else { return }
                loopStatRecord.end = Date()
                loopStatRecord.duration = self.roundDouble(
                    (loopStatRecord.end! - loopStatRecord.start).timeInterval / 60,
                    2
                )
                if case let .failure(error) = completion {
                    loopStatRecord.loopStatus = error.localizedDescription
                    self.loopCompleted(error: error, loopStatRecord: loopStatRecord)
                } else {
                    loopStatRecord.loopStatus = "Success"
                    self.loopCompleted(loopStatRecord: loopStatRecord)
                }
            } receiveValue: {}
            .store(in: &lifetime)
    }

    // Loop exit point
    private func loopCompleted(error: Error? = nil, loopStatRecord: LoopStats) {
        isLooping.send(false)

        if let error = error {
            warning(.apsManager, "Loop failed with error: \(error.localizedDescription)")
            if let backgroundTask = backGroundTaskID {
                UIApplication.shared.endBackgroundTask(backgroundTask)
                backGroundTaskID = .invalid
            }
            processError(error)
        } else {
            debug(.apsManager, "Loop succeeded")
            lastLoopDate = Date()
            lastError.send(nil)
        }

        loopStats(loopStatRecord: loopStatRecord)

        if settings.closedLoop {
            reportEnacted(received: error == nil)
        }

        // end of the BG tasks
        if let backgroundTask = backGroundTaskID {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backGroundTaskID = .invalid
        }
    }

    private func verifyStatus() -> Error? {
        guard let pump = pumpManager else {
            return APSError.invalidPumpState(message: "Pump not set")
        }
        let status = pump.status.pumpStatus

        guard !status.bolusing else {
            return APSError.invalidPumpState(message: "Pump is bolusing")
        }

        guard !status.suspended else {
            return APSError.invalidPumpState(message: "Pump suspended")
        }

        let reservoir = storage.retrieve(OpenAPS.Monitor.reservoir, as: Decimal.self) ?? 100
        guard reservoir >= 0 else {
            return APSError.invalidPumpState(message: "Reservoir is empty")
        }

        return nil
    }

    private func autosens() -> AnyPublisher<Bool, Never> {
        guard let autosens = storage.retrieve(OpenAPS.Settings.autosense, as: Autosens.self),
              (autosens.timestamp ?? .distantPast).addingTimeInterval(30.minutes.timeInterval) > Date()
        else {
            return openAPS.autosense()
                .map { $0 != nil }
                .eraseToAnyPublisher()
        }

        return Just(false).eraseToAnyPublisher()
    }

    func determineBasal() -> AnyPublisher<Bool, Never> {
        privateContext.performAndWait {
            debug(.apsManager, "Start determine basal")
            let glucose = fetchGlucose(predicate: NSPredicate.predicateFor30MinAgo, fetchLimit: 4)
            guard glucose.count > 2 else {
                debug(.apsManager, "Not enough glucose data")
                processError(APSError.glucoseError(message: "Not enough glucose data"))
                return Just(false).eraseToAnyPublisher()
            }

            let dateOfLastGlucose = glucose.first?.date
            guard dateOfLastGlucose ?? Date() >= Date().addingTimeInterval(-12.minutes.timeInterval) else {
                debug(.apsManager, "Glucose data is stale")
                processError(APSError.glucoseError(message: "Glucose data is stale"))
                return Just(false).eraseToAnyPublisher()
            }

            // Only let glucose be flat when 400 mg/dl
            if (glucose.first?.glucose ?? 100) != 400 {
                guard !GlucoseStored.glucoseIsFlat(glucose) else {
                    debug(.apsManager, "Glucose data is too flat")
                    processError(APSError.glucoseError(message: "Glucose data is too flat"))
                    return Just(false).eraseToAnyPublisher()
                }
            }

            let now = Date()
            let temp = fetchCurrentTempBasal(date: now)

            let mainPublisher = makeProfiles()
                .flatMap { _ in self.autosens() }
                .flatMap { _ in self.dailyAutotune() }
                .flatMap { _ in self.openAPS.determineBasal(currentTemp: temp, clock: now) }
                .map { determination -> Bool in
                    if let determination = determination {
                        DispatchQueue.main.async {
                            self.broadcaster.notify(DeterminationObserver.self, on: .main) {
                                $0.determinationDidUpdate(determination)
                            }
                        }
                    }

                    return determination != nil
                }
                .eraseToAnyPublisher()

            if temp.duration == 0,
               settings.closedLoop,
               settingsManager.preferences.unsuspendIfNoTemp,
               let pump = pumpManager,
               pump.status.pumpStatus.suspended
            {
                return pump.resumeDelivery()
                    .flatMap { _ in mainPublisher }
                    .replaceError(with: false)
                    .eraseToAnyPublisher()
            }

            return mainPublisher
        }
    }

    func determineBasalSync() {
        determineBasal().cancellable().store(in: &lifetime)
    }

    func makeProfiles() -> AnyPublisher<Bool, Never> {
        openAPS.makeProfiles(useAutotune: settings.useAutotune)
            .map { tunedProfile in
                if let basalProfile = tunedProfile?.basalProfile {
                    self.processQueue.async {
                        self.broadcaster.notify(BasalProfileObserver.self, on: self.processQueue) {
                            $0.basalProfileDidChange(basalProfile)
                        }
                    }
                }

                return tunedProfile != nil
            }
            .eraseToAnyPublisher()
    }

    func roundBolus(amount: Decimal) -> Decimal {
        guard let pump = pumpManager else { return amount }
        let rounded = Decimal(pump.roundToSupportedBolusVolume(units: Double(amount)))
        let maxBolus = Decimal(pump.roundToSupportedBolusVolume(units: Double(settingsManager.pumpSettings.maxBolus)))
        return min(rounded, maxBolus)
    }

    private var bolusReporter: DoseProgressReporter?

    func enactBolus(amount: Double, isSMB: Bool) async {
        if let error = verifyStatus() {
            processError(error)
            processQueue.async {
                self.broadcaster.notify(BolusFailureObserver.self, on: self.processQueue) {
                    $0.bolusDidFail()
                }
            }
            return
        }

        guard let pump = pumpManager else { return }

        let roundedAmount = pump.roundToSupportedBolusVolume(units: amount)

        debug(.apsManager, "Enact bolus \(roundedAmount), manual \(!isSMB)")

        do {
            try await pump.enactBolus(units: roundedAmount, automatic: isSMB)
            debug(.apsManager, "Bolus succeeded")
            if !isSMB {
//                determineBasal()
                determineBasalSync()
            }
            bolusProgress.send(0)
        } catch {
            warning(.apsManager, "Bolus failed with error: \(error.localizedDescription)")
            processError(APSError.pumpError(error))
            if !isSMB {
                processQueue.async {
                    self.broadcaster.notify(BolusFailureObserver.self, on: self.processQueue) {
                        $0.bolusDidFail()
                    }
                }
            }
        }
    }

    func cancelBolus() async {
        guard let pump = pumpManager, pump.status.pumpStatus.bolusing else { return }
        debug(.apsManager, "Cancel bolus")
        do {
            _ = try await pump.cancelBolus()
            debug(.apsManager, "Bolus cancelled")
        } catch {
            debug(.apsManager, "Bolus cancellation failed with error: \(error.localizedDescription)")
            processError(APSError.pumpError(error))
        }
        bolusReporter?.removeObserver(self)
        bolusReporter = nil
        bolusProgress.send(nil)
    }

    func enactTempBasal(rate: Double, duration: TimeInterval) async {
        if let error = verifyStatus() {
            processError(error)
            return
        }

        guard let pump = pumpManager else { return }

        // unable to do temp basal during manual temp basal 😁
        if isManualTempBasal {
            processError(APSError.manualBasalTemp(message: "Loop not possible during the manual basal temp"))
            return
        }

        debug(.apsManager, "Enact temp basal \(rate) - \(duration)")

        let roundedAmout = pump.roundToSupportedBasalRate(unitsPerHour: rate)

        do {
            try await pump.enactTempBasal(unitsPerHour: roundedAmout, for: duration)
            debug(.apsManager, "Temp Basal succeeded")
            let temp = TempBasal(duration: Int(duration / 60), rate: Decimal(rate), temp: .absolute, timestamp: Date())
            storage.save(temp, as: OpenAPS.Monitor.tempBasal)
            if rate == 0, duration == 0 {
                pumpHistoryStorage.saveCancelTempEvents()
            }
        } catch {
            debug(.apsManager, "Temp Basal failed with error: \(error.localizedDescription)")
            processError(APSError.pumpError(error))
        }
    }

//    func enactTempBasal(rate: Double, duration: TimeInterval) {
//        if let error = verifyStatus() {
//            processError(error)
//            return
//        }
//
//        guard let pump = pumpManager else { return }
//
//        // unable to do temp basal during manual temp basal 😁
//        if isManualTempBasal {
//            processError(APSError.manualBasalTemp(message: "Loop not possible during the manual basal temp"))
//            return
//        }
//
//        debug(.apsManager, "Enact temp basal \(rate) - \(duration)")
//
//        let roundedAmout = pump.roundToSupportedBasalRate(unitsPerHour: rate)
//        pump.enactTempBasal(unitsPerHour: roundedAmout, for: duration) { error in
//            if let error = error {
//                debug(.apsManager, "Temp Basal failed with error: \(error.localizedDescription)")
//                self.processError(APSError.pumpError(error))
//            } else {
//                debug(.apsManager, "Temp Basal succeeded")
//                let temp = TempBasal(duration: Int(duration / 60), rate: Decimal(rate), temp: .absolute, timestamp: Date())
//                self.storage.save(temp, as: OpenAPS.Monitor.tempBasal)
//                if rate == 0, duration == 0 {
//                    self.pumpHistoryStorage.saveCancelTempEvents()
//                }
//            }
//        }
//    }

    func dailyAutotune() -> AnyPublisher<Bool, Never> {
        guard settings.useAutotune else {
            return Just(false).eraseToAnyPublisher()
        }

        let now = Date()

        guard lastAutotuneDate.isBeforeDate(now, granularity: .day) else {
            return Just(false).eraseToAnyPublisher()
        }
        lastAutotuneDate = now

        return autotune().map { $0 != nil }.eraseToAnyPublisher()
    }

    func autotune() -> AnyPublisher<Autotune?, Never> {
        openAPS.autotune().eraseToAnyPublisher()
    }

    func enactAnnouncement(_ announcement: Announcement) {
        guard let action = announcement.action else {
            warning(.apsManager, "Invalid Announcement action")
            return
        }

        guard let pump = pumpManager else {
            warning(.apsManager, "Pump is not set")
            return
        }

        debug(.apsManager, "Start enact announcement: \(action)")

        switch action {
        case let .bolus(amount):
            if let error = verifyStatus() {
                processError(error)
                return
            }
            let roundedAmount = pump.roundToSupportedBolusVolume(units: Double(amount))
            pump.enactBolus(units: roundedAmount, activationType: .manualRecommendationAccepted) { error in
                if let error = error {
                    // warning(.apsManager, "Announcement Bolus failed with error: \(error.localizedDescription)")
                    switch error {
                    case .uncertainDelivery:
                        // Do not generate notification on uncertain delivery error
                        break
                    default:
                        // Do not generate notifications for automatic boluses that fail.
                        warning(.apsManager, "Announcement Bolus failed with error: \(error.localizedDescription)")
                    }

                } else {
                    debug(.apsManager, "Announcement Bolus succeeded")
                    self.announcementsStorage.storeAnnouncements([announcement], enacted: true)
                    self.bolusProgress.send(0)
                }
            }
        case let .pump(pumpAction):
            switch pumpAction {
            case .suspend:
                if let error = verifyStatus() {
                    processError(error)
                    return
                }
                pump.suspendDelivery { error in
                    if let error = error {
                        debug(.apsManager, "Pump not suspended by Announcement: \(error.localizedDescription)")
                    } else {
                        debug(.apsManager, "Pump suspended by Announcement")
                        self.announcementsStorage.storeAnnouncements([announcement], enacted: true)
                        self.nightscout.uploadStatus()
                    }
                }
            case .resume:
                guard pump.status.pumpStatus.suspended else {
                    return
                }
                pump.resumeDelivery { error in
                    if let error = error {
                        warning(.apsManager, "Pump not resumed by Announcement: \(error.localizedDescription)")
                    } else {
                        debug(.apsManager, "Pump resumed by Announcement")
                        self.announcementsStorage.storeAnnouncements([announcement], enacted: true)
                        self.nightscout.uploadStatus()
                    }
                }
            }
        case let .looping(closedLoop):
            settings.closedLoop = closedLoop
            debug(.apsManager, "Closed loop \(closedLoop) by Announcement")
            announcementsStorage.storeAnnouncements([announcement], enacted: true)
        case let .tempbasal(rate, duration):
            if let error = verifyStatus() {
                processError(error)
                return
            }
            // unable to do temp basal during manual temp basal 😁
            if isManualTempBasal {
                processError(APSError.manualBasalTemp(message: "Loop not possible during the manual basal temp"))
                return
            }
            guard !settings.closedLoop else {
                return
            }
            let roundedRate = pump.roundToSupportedBasalRate(unitsPerHour: Double(rate))
            pump.enactTempBasal(unitsPerHour: roundedRate, for: TimeInterval(duration) * 60) { error in
                if let error = error {
                    warning(.apsManager, "Announcement TempBasal failed with error: \(error.localizedDescription)")
                } else {
                    debug(.apsManager, "Announcement TempBasal succeeded")
                    self.announcementsStorage.storeAnnouncements([announcement], enacted: true)
                }
            }
        }
    }

    private func fetchCurrentTempBasal(date: Date) -> TempBasal {
        var fetchedTempBasal = TempBasal(duration: 0, rate: 0, temp: .absolute, timestamp: Date())

        privateContext.performAndWait {
            let results = CoreDataStack.shared.fetchEntities(
                ofType: PumpEventStored.self,
                onContext: privateContext,
                predicate: NSPredicate.recentPumpHistory,
                key: "timestamp",
                ascending: false,
                fetchLimit: 1
            )

            guard let tempBasalEvent = results.first,
                  let tempBasal = tempBasalEvent.tempBasal,
                  let eventTimestamp = tempBasalEvent.timestamp
            else {
                return
            }

            let delta = Int((date.timeIntervalSince1970 - eventTimestamp.timeIntervalSince1970) / 60)
            let duration = max(0, Int(tempBasal.duration) - delta)
            let rate = tempBasal.rate as? Decimal ?? 0
            fetchedTempBasal = TempBasal(duration: duration, rate: rate, temp: .absolute, timestamp: date)
        }

        guard let state = pumpManager?.status.basalDeliveryState else { return fetchedTempBasal }
        switch state {
        case .active:
            return TempBasal(duration: 0, rate: 0, temp: .absolute, timestamp: date)
        case let .tempBasal(dose):
            let rate = Decimal(dose.unitsPerHour)
            let durationMin = max(0, Int((dose.endDate.timeIntervalSince1970 - date.timeIntervalSince1970) / 60))
            return TempBasal(duration: durationMin, rate: rate, temp: .absolute, timestamp: date)
        default:
            return fetchedTempBasal
        }
    }

    private func fetchDetermination() -> NSManagedObjectID? {
        CoreDataStack.shared.fetchEntities(
            ofType: OrefDetermination.self,
            onContext: privateContext,
            predicate: NSPredicate.predicateFor30MinAgoForDetermination,
            key: "deliverAt",
            ascending: false,
            fetchLimit: 1
        ).first?.objectID
    }

    private func enactDetermination() async throws {
        guard let determinationID = fetchDetermination() else {
            throw APSError.apsError(message: "Determination not found")
        }

        guard let pump = pumpManager else {
            throw APSError.apsError(message: "Pump not set")
        }

        // Unable to do temp basal during manual temp basal 😁
        if isManualTempBasal {
            throw APSError.manualBasalTemp(message: "Loop not possible during the manual basal temp")
        }

        let (rateDecimal, durationInSeconds, smbToDeliver) = try await setValues(determinationID: determinationID)

        try await performBasal(pump: pump, rate: rateDecimal, duration: durationInSeconds)

        // only perform a bolus if smbToDeliver is > 0
        if smbToDeliver.compare(NSDecimalNumber(value: 0)) == .orderedDescending {
            try await performBolus(pump: pump, smbToDeliver: smbToDeliver)
        }
    }

    private func setValues(determinationID: NSManagedObjectID) async throws -> (NSDecimalNumber, TimeInterval, NSDecimalNumber) {
        return try await withCheckedThrowingContinuation { continuation in
            self.privateContext.perform {
                do {
                    let determination = try self.privateContext.existingObject(with: determinationID) as? OrefDetermination

                    /// Default values should be 0
                    /// If we would use guard here Determine Basal would fail unnecessarily often
                    let rate = (determination?.rate ?? 0) as NSDecimalNumber
                    let duration = TimeInterval((determination?.duration ?? 0) * 60)
                    let smbToDeliver = determination?.smbToDeliver ?? 0

                    continuation.resume(returning: (rate, duration, smbToDeliver))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func performBasal(pump: PumpManager, rate: NSDecimalNumber, duration: TimeInterval) async throws {
        try await pump.enactTempBasal(unitsPerHour: Double(truncating: rate), for: duration)

        let temp = TempBasal(
            duration: Int(duration / 60),
            rate: rate as Decimal,
            temp: .absolute,
            timestamp: Date()
        )
        storage.save(temp, as: OpenAPS.Monitor.tempBasal)
    }

    private func performBolus(pump: PumpManager, smbToDeliver: NSDecimalNumber) async throws {
        try await pump.enactBolus(units: Double(truncating: smbToDeliver), automatic: true)
        bolusProgress.send(0)
    }

    private func reportEnacted(received: Bool) {
        privateContext.performAndWait {
            guard let determinationID = fetchDetermination() else {
                return
            }

            if let determinationUpdated = self.privateContext.object(with: determinationID) as? OrefDetermination {
                determinationUpdated.timestamp = Date()
                determinationUpdated.received = received

                do {
                    guard privateContext.hasChanges else { return }
                    try privateContext.save()
                    debugPrint("Update successful in reportEnacted() \(DebuggingIdentifiers.succeeded)")
                } catch {
                    debugPrint(
                        "Failed  \(DebuggingIdentifiers.succeeded) to save context in reportEnacted(): \(error.localizedDescription)"
                    )
                }

                debug(.apsManager, "Determination enacted. Received: \(received)")

                nightscout.uploadStatus()
                statistics()
            } else {
                debugPrint("Failed to update OrefDetermination in reportEnacted()")
            }
        }
    }

    private func roundDecimal(_ decimal: Decimal, _ digits: Double) -> Decimal {
        let rounded = round(Double(decimal) * pow(10, digits)) / pow(10, digits)
        return Decimal(rounded)
    }

    private func roundDouble(_ double: Double, _ digits: Double) -> Double {
        let rounded = round(Double(double) * pow(10, digits)) / pow(10, digits)
        return rounded
    }

    private func medianCalculationDouble(array: [Double]) -> Double {
        guard !array.isEmpty else {
            return 0
        }
        let sorted = array.sorted()
        let length = array.count

        if length % 2 == 0 {
            return (sorted[length / 2 - 1] + sorted[length / 2]) / 2
        }
        return sorted[length / 2]
    }

    private func medianCalculation(array: [Int]) -> Double {
        guard !array.isEmpty else {
            return 0
        }
        let sorted = array.sorted()
        let length = array.count

        if length % 2 == 0 {
            return Double((sorted[length / 2 - 1] + sorted[length / 2]) / 2)
        }
        return Double(sorted[length / 2])
    }

    private func tir(_ glucose: [GlucoseStored]) -> (TIR: Double, hypos: Double, hypers: Double, normal_: Double) {
        privateContext.perform {
            let justGlucoseArray = glucose.compactMap({ each in Int(each.glucose as Int16) })
            let totalReadings = justGlucoseArray.count
            let highLimit = settingsManager.settings.high
            let lowLimit = settingsManager.settings.low
            let hyperArray = glucose.filter({ $0.glucose >= Int(highLimit) })
            let hyperReadings = hyperArray.compactMap({ each in each.glucose as Int16 }).count
            let hyperPercentage = Double(hyperReadings) / Double(totalReadings) * 100
            let hypoArray = glucose.filter({ $0.glucose <= Int(lowLimit) })
            let hypoReadings = hypoArray.compactMap({ each in each.glucose as Int16 }).count
            let hypoPercentage = Double(hypoReadings) / Double(totalReadings) * 100
            // Euglyccemic range
            let normalArray = glucose.filter({ $0.glucose >= 70 && $0.glucose <= 140 })
            let normalReadings = normalArray.compactMap({ each in each.glucose as Int16 }).count
            let normalPercentage = Double(normalReadings) / Double(totalReadings) * 100
            // TIR
            let tir = 100 - (hypoPercentage + hyperPercentage)
            return (
                roundDouble(tir, 1),
                roundDouble(hypoPercentage, 1),
                roundDouble(hyperPercentage, 1),
                roundDouble(normalPercentage, 1)
            )
        }
    }

    private func glucoseStats(_ fetchedGlucose: [GlucoseStored])
        -> (ifcc: Double, ngsp: Double, average: Double, median: Double, sd: Double, cv: Double, readings: Double)
    {
        let glucose = fetchedGlucose
        // First date
        let last = glucose.last?.date ?? Date()
        // Last date (recent)
        let first = glucose.first?.date ?? Date()
        // Total time in days
        let numberOfDays = (first - last).timeInterval / 8.64E4
        let denominator = numberOfDays < 1 ? 1 : numberOfDays
        let justGlucoseArray = glucose.compactMap({ each in Int(each.glucose as Int16) })
        let sumReadings = justGlucoseArray.reduce(0, +)
        let countReadings = justGlucoseArray.count
        let glucoseAverage = Double(sumReadings) / Double(countReadings)
        let medianGlucose = medianCalculation(array: justGlucoseArray)
        var NGSPa1CStatisticValue = 0.0
        var IFCCa1CStatisticValue = 0.0

        NGSPa1CStatisticValue = (glucoseAverage + 46.7) / 28.7 // NGSP (%)
        IFCCa1CStatisticValue = 10.929 *
            (NGSPa1CStatisticValue - 2.152) // IFCC (mmol/mol)  A1C(mmol/mol) = 10.929 * (A1C(%) - 2.15)
        var sumOfSquares = 0.0

        for array in justGlucoseArray {
            sumOfSquares += pow(Double(array) - Double(glucoseAverage), 2)
        }
        var sd = 0.0
        var cv = 0.0
        // Avoid division by zero
        if glucoseAverage > 0 {
            sd = sqrt(sumOfSquares / Double(countReadings))
            cv = sd / Double(glucoseAverage) * 100
        }
        let conversionFactor = 0.0555
        let units = settingsManager.settings.units

        var output: (ifcc: Double, ngsp: Double, average: Double, median: Double, sd: Double, cv: Double, readings: Double)
        output = (
            ifcc: IFCCa1CStatisticValue,
            ngsp: NGSPa1CStatisticValue,
            average: glucoseAverage * (units == .mmolL ? conversionFactor : 1),
            median: medianGlucose * (units == .mmolL ? conversionFactor : 1),
            sd: sd * (units == .mmolL ? conversionFactor : 1), cv: cv,
            readings: Double(countReadings) / denominator
        )
        return output
    }

    private func loops(_ fetchedLoops: [LoopStatRecord]) -> Loops {
        let loops = fetchedLoops
        // First date
        let previous = loops.last?.end ?? Date()
        // Last date (recent)
        let current = loops.first?.start ?? Date()
        // Total time in days
        let totalTime = (current - previous).timeInterval / 8.64E4
        //
        let durationArray = loops.compactMap({ each in each.duration })
        let durationArrayCount = durationArray.count
        let durationAverage = durationArray.reduce(0, +) / Double(durationArrayCount) * 60
        let medianDuration = medianCalculationDouble(array: durationArray) * 60
        let max_duration = (durationArray.max() ?? 0) * 60
        let min_duration = (durationArray.min() ?? 0) * 60
        let successsNR = loops.compactMap({ each in each.loopStatus }).filter({ each in each!.contains("Success") }).count
        let errorNR = durationArrayCount - successsNR
        let total = Double(successsNR + errorNR) == 0 ? 1 : Double(successsNR + errorNR)
        let successRate: Double? = (Double(successsNR) / total) * 100
        let loopNr = totalTime <= 1 ? total : round(total / (totalTime != 0 ? totalTime : 1))
        let intervalArray = loops.compactMap({ each in each.interval as Double })
        let count = intervalArray.count != 0 ? intervalArray.count : 1
        let median_interval = medianCalculationDouble(array: intervalArray)
        let intervalAverage = intervalArray.reduce(0, +) / Double(count)
        let maximumInterval = intervalArray.max()
        let minimumInterval = intervalArray.min()
        //
        let output = Loops(
            loops: Int(loopNr),
            errors: errorNR,
            success_rate: roundDecimal(Decimal(successRate ?? 0), 1),
            avg_interval: roundDecimal(Decimal(intervalAverage), 1),
            median_interval: roundDecimal(Decimal(median_interval), 1),
            min_interval: roundDecimal(Decimal(minimumInterval ?? 0), 1),
            max_interval: roundDecimal(Decimal(maximumInterval ?? 0), 1),
            avg_duration: roundDecimal(Decimal(durationAverage), 1),
            median_duration: roundDecimal(Decimal(medianDuration), 1),
            min_duration: roundDecimal(Decimal(min_duration), 1),
            max_duration: roundDecimal(Decimal(max_duration), 1)
        )
        return output
    }

    // fetch glucose for time interval
    func fetchGlucose(predicate: NSPredicate, fetchLimit: Int? = nil, batchSize: Int? = nil) -> [GlucoseStored] {
        CoreDataStack.shared.fetchEntities(
            ofType: GlucoseStored.self,
            onContext: privateContext,
            predicate: predicate,
            key: "date",
            ascending: false,
            fetchLimit: fetchLimit,
            batchSize: batchSize
        )
    }

    // TODO: - Refactor this whole shit here...

    // Add to statistics.JSON for upload to NS.
    private func statistics() {
        let now = Date()
        if settingsManager.settings.uploadStats {
            let hour = Calendar.current.component(.hour, from: now)
            guard hour > 20 else {
                return
            }
            privateContext.perform { [self] in
                var stats = [StatsData]()
                let requestStats = StatsData.fetchRequest() as NSFetchRequest<StatsData>
                let sortStats = NSSortDescriptor(key: "lastrun", ascending: false)
                requestStats.sortDescriptors = [sortStats]
                requestStats.fetchLimit = 1
                try? stats = privateContext.fetch(requestStats)
                // Only save and upload once per day
                guard (-1 * (stats.first?.lastrun ?? .distantPast).timeIntervalSinceNow.hours) > 22 else { return }

                let units = self.settingsManager.settings.units
                let preferences = settingsManager.preferences

                // Carbs
                var carbTotal: Decimal = 0
                let requestCarbs = CarbEntryStored.fetchRequest() as NSFetchRequest<CarbEntryStored>
                let daysAgo = Date().addingTimeInterval(-1.days.timeInterval)
                requestCarbs.predicate = NSPredicate(format: "carbs > 0 AND date > %@", daysAgo as NSDate)
                requestCarbs.sortDescriptors = [NSSortDescriptor(key: "date", ascending: true)]

                do {
                    let carbs = try privateContext.fetch(requestCarbs)
                    carbTotal = carbs.reduce(0) { sum, meal in
                        let mealCarbs = Decimal(string: "\(meal.carbs)") ?? Decimal.zero
                        return sum + mealCarbs
                    }
                    debugPrint(
                        "APSManager: statistics() -> \(CoreDataStack.identifier) \(DebuggingIdentifiers.succeeded) fetched carbs"
                    )
                } catch {
                    debugPrint(
                        "APSManager: statistics() -> \(CoreDataStack.identifier) \(DebuggingIdentifiers.failed) error while fetching carbs"
                    )
                }

                // TDD
                var tdds = [OrefDetermination]()
                var currentTDD: Decimal = 0
                var tddTotalAverage: Decimal = 0
                let requestTDD = OrefDetermination.fetchRequest() as NSFetchRequest<OrefDetermination>
                let sort = NSSortDescriptor(key: "timestamp", ascending: false)
                let daysOf14Ago = Date().addingTimeInterval(-14.days.timeInterval)
                requestTDD.predicate = NSPredicate(format: "timestamp > %@", daysOf14Ago as NSDate)
                requestTDD.sortDescriptors = [sort]
                requestTDD.propertiesToFetch = ["timestamp", "totalDailyDose"]
                try? tdds = privateContext.fetch(requestTDD)

                if !tdds.isEmpty {
                    currentTDD = tdds[0].totalDailyDose?.decimalValue ?? 0
                    let tddArray = tdds.compactMap({ insulin in insulin.totalDailyDose as? Decimal ?? 0 })
                    tddTotalAverage = tddArray.reduce(0, +) / Decimal(tddArray.count)
                }

                var algo_ = "Oref0"

                if preferences.sigmoid, preferences.enableDynamicCR {
                    algo_ = "Dynamic ISF + CR: Sigmoid"
                } else if preferences.sigmoid, !preferences.enableDynamicCR {
                    algo_ = "Dynamic ISF: Sigmoid"
                } else if preferences.useNewFormula, preferences.enableDynamicCR {
                    algo_ = "Dynamic ISF + CR: Logarithmic"
                } else if preferences.useNewFormula, !preferences.sigmoid,!preferences.enableDynamicCR {
                    algo_ = "Dynamic ISF: Logarithmic"
                }
                let af = preferences.adjustmentFactor
                let insulin_type = preferences.curve
                let buildDate = Bundle.main.buildDate
                let version = Bundle.main.releaseVersionNumber
                let build = Bundle.main.buildVersionNumber

                // Read branch information from branch.txt instead of infoDictionary
                var branch = "Unknown"
                if let branchFileURL = Bundle.main.url(forResource: "branch", withExtension: "txt"),
                   let branchFileContent = try? String(contentsOf: branchFileURL)
                {
                    let lines = branchFileContent.components(separatedBy: .newlines)
                    for line in lines {
                        let components = line.components(separatedBy: "=")
                        if components.count == 2 {
                            let key = components[0].trimmingCharacters(in: .whitespaces)
                            let value = components[1].trimmingCharacters(in: .whitespaces)

                            if key == "BRANCH" {
                                branch = value
                                break
                            }
                        }
                    }
                } else {
                    branch = "Unknown"
                }

                let copyrightNotice_ = Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String ?? ""
                let pump_ = pumpManager?.localizedTitle ?? ""
                let cgm = settingsManager.settings.cgm
                let file = OpenAPS.Monitor.statistics
                var iPa: Decimal = 75
                if preferences.useCustomPeakTime {
                    iPa = preferences.insulinPeakTime
                } else if preferences.curve.rawValue == "rapid-acting" {
                    iPa = 65
                } else if preferences.curve.rawValue == "ultra-rapid" {
                    iPa = 50
                }

                // Glucose Values
                let glucose24h = fetchGlucose(predicate: NSPredicate.predicateForOneDayAgo, fetchLimit: 288, batchSize: 50)
                let glucoseOneWeek = fetchGlucose(predicate: NSPredicate.predicateForOneWeek, fetchLimit: 288 * 7, batchSize: 250)
                let glucoseOneMonth = fetchGlucose(
                    predicate: NSPredicate.predicateForOneMonth,
                    fetchLimit: 288 * 7 * 30,
                    batchSize: 500
                )
                let glucoseThreeMonths = fetchGlucose(
                    predicate: NSPredicate.predicateForThreeMonths,
                    fetchLimit: 288 * 7 * 30 * 3,
                    batchSize: 1000
                )

                // First date
                let previous = glucoseThreeMonths.last?.date ?? Date()
                // Last date (recent)
                let current = glucoseThreeMonths.first?.date ?? Date()
                // Total time in days
                let numberOfDays = (current - previous).timeInterval / 8.64E4

                // Get glucose computations for every case
                let oneDayGlucose = glucoseStats(glucose24h)
                let sevenDaysGlucose = glucoseStats(glucoseOneWeek)
                let thirtyDaysGlucose = glucoseStats(glucoseOneMonth)
                let totalDaysGlucose = glucoseStats(glucoseThreeMonths)

                let median = Durations(
                    day: roundDecimal(Decimal(oneDayGlucose.median), 1),
                    week: roundDecimal(Decimal(sevenDaysGlucose.median), 1),
                    month: roundDecimal(Decimal(thirtyDaysGlucose.median), 1),
                    total: roundDecimal(Decimal(totalDaysGlucose.median), 1)
                )

                let overrideHbA1cUnit = settingsManager.settings.overrideHbA1cUnit

                let hbs = Durations(
                    day: ((units == .mmolL && !overrideHbA1cUnit) || (units == .mgdL && overrideHbA1cUnit)) ?
                        roundDecimal(Decimal(oneDayGlucose.ifcc), 1) : roundDecimal(Decimal(oneDayGlucose.ngsp), 1),
                    week: ((units == .mmolL && !overrideHbA1cUnit) || (units == .mgdL && overrideHbA1cUnit)) ?
                        roundDecimal(Decimal(sevenDaysGlucose.ifcc), 1) : roundDecimal(Decimal(sevenDaysGlucose.ngsp), 1),
                    month: ((units == .mmolL && !overrideHbA1cUnit) || (units == .mgdL && overrideHbA1cUnit)) ?
                        roundDecimal(Decimal(thirtyDaysGlucose.ifcc), 1) : roundDecimal(Decimal(thirtyDaysGlucose.ngsp), 1),
                    total: ((units == .mmolL && !overrideHbA1cUnit) || (units == .mgdL && overrideHbA1cUnit)) ?
                        roundDecimal(Decimal(totalDaysGlucose.ifcc), 1) : roundDecimal(Decimal(totalDaysGlucose.ngsp), 1)
                )

                var oneDay_: (TIR: Double, hypos: Double, hypers: Double, normal_: Double) = (0.0, 0.0, 0.0, 0.0)
                var sevenDays_: (TIR: Double, hypos: Double, hypers: Double, normal_: Double) = (0.0, 0.0, 0.0, 0.0)
                var thirtyDays_: (TIR: Double, hypos: Double, hypers: Double, normal_: Double) = (0.0, 0.0, 0.0, 0.0)
                var totalDays_: (TIR: Double, hypos: Double, hypers: Double, normal_: Double) = (0.0, 0.0, 0.0, 0.0)
                // Get TIR computations for every case
                oneDay_ = tir(glucose24h)
                sevenDays_ = tir(glucoseOneWeek)
                thirtyDays_ = tir(glucoseOneMonth)
                totalDays_ = tir(glucoseThreeMonths)

                let tir = Durations(
                    day: roundDecimal(Decimal(oneDay_.TIR), 1),
                    week: roundDecimal(Decimal(sevenDays_.TIR), 1),
                    month: roundDecimal(Decimal(thirtyDays_.TIR), 1),
                    total: roundDecimal(Decimal(totalDays_.TIR), 1)
                )
                let hypo = Durations(
                    day: Decimal(oneDay_.hypos),
                    week: Decimal(sevenDays_.hypos),
                    month: Decimal(thirtyDays_.hypos),
                    total: Decimal(totalDays_.hypos)
                )
                let hyper = Durations(
                    day: Decimal(oneDay_.hypers),
                    week: Decimal(sevenDays_.hypers),
                    month: Decimal(thirtyDays_.hypers),
                    total: Decimal(totalDays_.hypers)
                )
                let normal = Durations(
                    day: Decimal(oneDay_.normal_),
                    week: Decimal(sevenDays_.normal_),
                    month: Decimal(thirtyDays_.normal_),
                    total: Decimal(totalDays_.normal_)
                )
                let range = Threshold(
                    low: units == .mmolL ? roundDecimal(settingsManager.settings.low.asMmolL, 1) :
                        roundDecimal(settingsManager.settings.low, 0),
                    high: units == .mmolL ? roundDecimal(settingsManager.settings.high.asMmolL, 1) :
                        roundDecimal(settingsManager.settings.high, 0)
                )
                let TimeInRange = TIRs(
                    TIR: tir,
                    Hypos: hypo,
                    Hypers: hyper,
                    Threshold: range,
                    Euglycemic: normal
                )
                let avgs = Durations(
                    day: roundDecimal(Decimal(oneDayGlucose.average), 1),
                    week: roundDecimal(Decimal(sevenDaysGlucose.average), 1),
                    month: roundDecimal(Decimal(thirtyDaysGlucose.average), 1),
                    total: roundDecimal(Decimal(totalDaysGlucose.average), 1)
                )
                let avg = Averages(Average: avgs, Median: median)
                // Standard Deviations
                let standardDeviations = Durations(
                    day: roundDecimal(Decimal(oneDayGlucose.sd), 1),
                    week: roundDecimal(Decimal(sevenDaysGlucose.sd), 1),
                    month: roundDecimal(Decimal(thirtyDaysGlucose.sd), 1),
                    total: roundDecimal(Decimal(totalDaysGlucose.sd), 1)
                )
                // CV = standard deviation / sample mean x 100
                let cvs = Durations(
                    day: roundDecimal(Decimal(oneDayGlucose.cv), 1),
                    week: roundDecimal(Decimal(sevenDaysGlucose.cv), 1),
                    month: roundDecimal(Decimal(thirtyDaysGlucose.cv), 1),
                    total: roundDecimal(Decimal(totalDaysGlucose.cv), 1)
                )
                let variance = Variance(SD: standardDeviations, CV: cvs)

                // Loops
                var lsr = [LoopStatRecord]()
                let requestLSR = LoopStatRecord.fetchRequest() as NSFetchRequest<LoopStatRecord>
                requestLSR.predicate = NSPredicate(
                    format: "interval > 0 AND start > %@",
                    Date().addingTimeInterval(-24.hours.timeInterval) as NSDate
                )
                let sortLSR = NSSortDescriptor(key: "start", ascending: false)
                requestLSR.sortDescriptors = [sortLSR]
                try? lsr = privateContext.fetch(requestLSR)
                // Compute LoopStats for 24 hours
                let oneDayLoops = loops(lsr)
                let loopstat = LoopCycles(
                    loops: oneDayLoops.loops,
                    errors: oneDayLoops.errors,
                    readings: Int(oneDayGlucose.readings),
                    success_rate: oneDayLoops.success_rate,
                    avg_interval: oneDayLoops.avg_interval,
                    median_interval: oneDayLoops.median_interval,
                    min_interval: oneDayLoops.min_interval,
                    max_interval: oneDayLoops.max_interval,
                    avg_duration: oneDayLoops.avg_duration,
                    median_duration: oneDayLoops.median_duration,
                    min_duration: oneDayLoops.max_duration,
                    max_duration: oneDayLoops.max_duration
                )

                // Insulin
                var insulin = Ins(
                    TDD: 0,
                    bolus: 0,
                    temp_basal: 0,
                    scheduled_basal: 0,
                    total_average: 0
                )

                let hbA1cUnit = !overrideHbA1cUnit ? (units == .mmolL ? "mmol/mol" : "%") : (units == .mmolL ? "%" : "mmol/mol")

                let dailystat = Statistics(
                    created_at: Date(),
                    iPhone: UIDevice.current.getDeviceId,
                    iOS: UIDevice.current.getOSInfo,
                    Build_Version: version ?? "",
                    Build_Number: build ?? "1",
                    Branch: branch,
                    CopyRightNotice: String(copyrightNotice_.prefix(32)),
                    Build_Date: buildDate,
                    Algorithm: algo_,
                    AdjustmentFactor: af,
                    Pump: pump_,
                    CGM: cgm.rawValue,
                    insulinType: insulin_type.rawValue,
                    peakActivityTime: iPa,
                    Carbs_24h: carbTotal,
                    GlucoseStorage_Days: Decimal(roundDouble(numberOfDays, 1)),
                    Statistics: Stats(
                        Distribution: TimeInRange,
                        Glucose: avg,
                        HbA1c: hbs, Units: Units(Glucose: units.rawValue, HbA1c: hbA1cUnit),
                        LoopCycles: loopstat,
                        Insulin: insulin,
                        Variance: variance
                    )
                )
                storage.save(dailystat, as: file)
                nightscout.uploadStatistics(dailystat: dailystat)

                let saveStatsCoreData = StatsData(context: self.privateContext)
                saveStatsCoreData.lastrun = Date()

                do {
                    guard self.privateContext.hasChanges else { return }
                    try self.privateContext.save()
                } catch {
                    print(error.localizedDescription)
                }
            }
        }
    }

    private func loopStats(loopStatRecord: LoopStats) {
        privateContext.perform {
            let nLS = LoopStatRecord(context: self.privateContext)

            nLS.start = loopStatRecord.start
            nLS.end = loopStatRecord.end ?? Date()
            nLS.loopStatus = loopStatRecord.loopStatus
            nLS.duration = loopStatRecord.duration ?? 0.0
            nLS.interval = loopStatRecord.interval ?? 0.0

            do {
                guard self.privateContext.hasChanges else { return }
                try self.privateContext.save()
            } catch {
                print(error.localizedDescription)
            }
        }
    }

    private func processError(_ error: Error) {
        warning(.apsManager, "\(error.localizedDescription)")
        lastError.send(error)
    }

    private func createBolusReporter() {
        bolusReporter = pumpManager?.createBolusProgressReporter(reportingOn: processQueue)
        bolusReporter?.addObserver(self)
    }

    private func updateStatus() {
        debug(.apsManager, "force update status")
        guard let pump = pumpManager else {
            return
        }

        if let omnipod = pump as? OmnipodPumpManager {
            omnipod.getPodStatus { _ in }
        }
        if let omnipodBLE = pump as? OmniBLEPumpManager {
            omnipodBLE.getPodStatus { _ in }
        }
    }

    private func clearBolusReporter() {
        bolusReporter?.removeObserver(self)
        bolusReporter = nil
        processQueue.asyncAfter(deadline: .now() + 0.5) {
            self.bolusProgress.send(nil)
            self.updateStatus()
        }
    }
}

private extension PumpManager {
    func enactTempBasal(unitsPerHour: Double, for duration: TimeInterval) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.enactTempBasal(unitsPerHour: unitsPerHour, for: duration) { error in
                if let error = error {
                    debug(.apsManager, "Temp basal failed: \(unitsPerHour) for: \(duration)")
                    continuation.resume(throwing: error)
                } else {
                    debug(.apsManager, "Temp basal succeeded: \(unitsPerHour) for: \(duration)")
                    continuation.resume(returning: ())
                }
            }
        }
    }

    func enactBolus(units: Double, automatic: Bool) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let automaticValue = automatic ? BolusActivationType.automatic : BolusActivationType.manualRecommendationAccepted

            self.enactBolus(units: units, activationType: automaticValue) { error in
                if let error = error {
                    debug(.apsManager, "Bolus failed: \(units)")
                    continuation.resume(throwing: error)
                } else {
                    debug(.apsManager, "Bolus succeeded: \(units)")
                    continuation.resume(returning: ())
                }
            }
        }
    }

    func cancelBolus() async throws -> DoseEntry? {
        try await withCheckedThrowingContinuation { continuation in
            self.cancelBolus { result in
                switch result {
                case let .success(dose):
                    debug(.apsManager, "Cancel Bolus succeeded")
                    continuation.resume(returning: dose)
                case let .failure(error):
                    debug(.apsManager, "Cancel Bolus failed")
                    continuation.resume(throwing: APSError.pumpError(error))
                }
            }
        }
    }

    func suspendDelivery() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.suspendDelivery { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

//    func resumeDelivery() async throws {
//        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
//            self.resumeDelivery { error in
//                if let error = error {
//                    continuation.resume(throwing: error)
//                } else {
//                    continuation.resume()
//                }
//            }
//        }
//    }

    func resumeDelivery() -> AnyPublisher<Void, Error> {
        Future { promise in
            self.resumeDelivery { error in
                if let error = error {
                    promise(.failure(error))
                } else {
                    promise(.success(()))
                }
            }
        }
        .mapError { APSError.pumpError($0) }
        .eraseToAnyPublisher()
    }
}

extension BaseAPSManager: PumpManagerStatusObserver {
    func pumpManager(_: PumpManager, didUpdate status: PumpManagerStatus, oldStatus _: PumpManagerStatus) {
        let percent = Int((status.pumpBatteryChargeRemaining ?? 1) * 100)

        privateContext.perform {
            /// only update the last item with the current battery infos instead of saving a new one each time
            let fetchRequest: NSFetchRequest<OpenAPS_Battery> = OpenAPS_Battery.fetchRequest()
            fetchRequest.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
            fetchRequest.predicate = NSPredicate.predicateFor30MinAgo
            fetchRequest.fetchLimit = 1

            do {
                let results = try self.privateContext.fetch(fetchRequest)
                let batteryToStore: OpenAPS_Battery

                if let existingBattery = results.first {
                    batteryToStore = existingBattery
                } else {
                    batteryToStore = OpenAPS_Battery(context: self.privateContext)
                    batteryToStore.id = UUID()
                }

                batteryToStore.date = Date()
                batteryToStore.percent = Int16(percent)
                batteryToStore.voltage = nil
                batteryToStore.status = percent > 10 ? "normal" : "low"
                batteryToStore.display = status.pumpBatteryChargeRemaining != nil

                guard self.privateContext.hasChanges else { return }
                try self.privateContext.save()
            } catch {
                print("Failed to fetch or save battery: \(error.localizedDescription)")
            }
        }
        // TODO: - remove this after ensuring that NS still gets the same infos from Core Data
        storage.save(status.pumpStatus, as: OpenAPS.Monitor.status)
    }
}

extension BaseAPSManager: DoseProgressObserver {
    func doseProgressReporterDidUpdate(_ doseProgressReporter: DoseProgressReporter) {
        bolusProgress.send(Decimal(doseProgressReporter.progress.percentComplete))
        if doseProgressReporter.progress.isComplete {
            clearBolusReporter()
        }
    }
}

extension PumpManagerStatus {
    var pumpStatus: PumpStatus {
        let bolusing = bolusState != .noBolus
        let suspended = basalDeliveryState?.isSuspended ?? true
        let type = suspended ? StatusType.suspended : (bolusing ? .bolusing : .normal)
        return PumpStatus(status: type, bolusing: bolusing, suspended: suspended, timestamp: Date())
    }
}
