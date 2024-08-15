import CoreData
import SwiftUI

extension ISFEditor {
    final class StateModel: BaseStateModel<Provider> {
        @Injected() var determinationStorage: DeterminationStorage!
        @Published var items: [Item] = []
        @Published var initialItems: [Item] = []
        @Published var shouldDisplaySaving: Bool = false
        private(set) var autosensISF: Decimal?
        private(set) var autosensRatio: Decimal = 0
        @Published var autotune: Autotune?
        @Published var determinationsFromPersistence: [OrefDetermination] = []

        let context = CoreDataStack.shared.newTaskContext()
        let viewContext = CoreDataStack.shared.persistentContainer.viewContext

        let timeValues = stride(from: 0.0, to: 1.days.timeInterval, by: 30.minutes.timeInterval).map { $0 }

        var rateValues: [Decimal] {
            stride(from: 9, to: 540.01, by: 1.0).map { Decimal($0) }
        }

        var canAdd: Bool {
            guard let lastItem = items.last else { return true }
            return lastItem.timeIndex < timeValues.count - 1
        }

        var hasChanges: Bool {
            initialItems != items
        }

        private(set) var units: GlucoseUnits = .mgdL

        override func subscribe() {
            units = settingsManager.settings.units

            let profile = provider.profile

            items = profile.sensitivities.map { value in
                let timeIndex = timeValues.firstIndex(of: Double(value.offset * 60)) ?? 0
                let rateIndex = rateValues.firstIndex(of: value.sensitivity) ?? 0
                return Item(rateIndex: rateIndex, timeIndex: timeIndex)
            }

            initialItems = items.map { Item(rateIndex: $0.rateIndex, timeIndex: $0.timeIndex) }

            autotune = provider.autotune

            if let newISF = provider.autosense.newisf {
                switch units {
                case .mgdL:
                    autosensISF = newISF
                case .mmolL:
                    autosensISF = newISF * GlucoseUnits.exchangeRate
                }
            }

            autosensRatio = provider.autosense.ratio
            setupDeterminationsArray()
        }

        func add() {
            var time = 0
            var rate = 0
            if let last = items.last {
                time = last.timeIndex + 1
                rate = last.rateIndex
            }

            let newItem = Item(rateIndex: rate, timeIndex: time)

            items.append(newItem)
        }

        func save() {
            guard hasChanges else { return }
            shouldDisplaySaving.toggle()

            let sensitivities = items.map { item -> InsulinSensitivityEntry in
                let fotmatter = DateFormatter()
                fotmatter.timeZone = TimeZone(secondsFromGMT: 0)
                fotmatter.dateFormat = "HH:mm:ss"
                let date = Date(timeIntervalSince1970: self.timeValues[item.timeIndex])
                let minutes = Int(date.timeIntervalSince1970 / 60)
                let rate = self.rateValues[item.rateIndex]
                return InsulinSensitivityEntry(sensitivity: rate, offset: minutes, start: fotmatter.string(from: date))
            }
            let profile = InsulinSensitivities(
                units: .mgdL,
                userPrefferedUnits: .mgdL,
                sensitivities: sensitivities
            )
            provider.saveProfile(profile)
            initialItems = items.map { Item(rateIndex: $0.rateIndex, timeIndex: $0.timeIndex) }
        }

        func validate() {
            DispatchQueue.main.async {
                DispatchQueue.main.async {
                    let uniq = Array(Set(self.items))
                    let sorted = uniq.sorted { $0.timeIndex < $1.timeIndex }
                    sorted.first?.timeIndex = 0
                    if self.items != sorted {
                        self.items = sorted
                    }
                    if self.items.isEmpty {
                        self.units = self.settingsManager.settings.units
                    }
                }
            }
        }

        private func setupDeterminationsArray() {
            Task {
                let ids = await determinationStorage.fetchLastDeterminationObjectID(
                    predicate: NSPredicate.enactedDetermination
                )
                await updateDeterminationsArray(with: ids)
            }
        }

        @MainActor private func updateDeterminationsArray(with IDs: [NSManagedObjectID]) {
            do {
                let objects = try IDs.compactMap { id in
                    try viewContext.existingObject(with: id) as? OrefDetermination
                }
                determinationsFromPersistence = objects

            } catch {
                debugPrint(
                    "Home State: \(#function) \(DebuggingIdentifiers.failed) error while updating the glucose array: \(error.localizedDescription)"
                )
            }
        }
    }
}

extension ISFEditor.StateModel: SettingsObserver {
    func settingsDidChange(_: FreeAPSSettings) {
        units = settingsManager.settings.units
    }
}
