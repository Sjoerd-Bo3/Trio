import Combine
import Foundation
import LoopKit

/// Persists per-alert **severity overrides** the user sets in
/// Settings → Alert Severity. Keyed by `Alert.CatalogConcept.storableKey`, so
/// all per-plugin identifiers that share a concept (e.g. every pump's
/// occlusion) move together.
///
/// An entry is present only when the user has deliberately changed a concept
/// away from its catalog default; absence means "use the catalog default".
/// `TrioAlertManager.issueAlert` reads this to rewrite an alert's
/// `interruptionLevel` at fire time.
///
/// Glucose alarms are configured per-alarm in the Glucose Alarms screen and
/// aren't catalog concepts, so they're unaffected by this store.
final class AlertSeverityOverrideStore: ObservableObject {
    static let shared = AlertSeverityOverrideStore()

    /// concept.storableKey → user-chosen severity tier.
    @Published var overrides: [String: DeviceAlertSeverity]

    private let defaults: UserDefaults
    private let key: String
    private var subscriptions = Set<AnyCancellable>()

    init(
        defaults: UserDefaults = .standard,
        key: String = "trio.alertSeverityOverrides.v1"
    ) {
        self.defaults = defaults
        self.key = key
        overrides = Self.decode([String: DeviceAlertSeverity].self, from: defaults, key: key) ?? [:]
        bind()
    }

    // MARK: - Lookup

    /// The user's override for a concept, or `nil` when they haven't changed it.
    func override(for concept: Alert.CatalogConcept) -> DeviceAlertSeverity? {
        overrides[concept.storableKey]
    }

    /// Effective tier for a concept: the override when set, else the supplied
    /// catalog default.
    func severity(for concept: Alert.CatalogConcept, default catalogDefault: DeviceAlertSeverity) -> DeviceAlertSeverity {
        overrides[concept.storableKey] ?? catalogDefault
    }

    // MARK: - Mutation

    /// Set (or, when `severity == catalogDefault`, clear) the override for a
    /// concept. Storing back to the default keeps the map small and lets the
    /// catalog default win if it ever changes in a future build.
    func setSeverity(_ severity: DeviceAlertSeverity, for concept: Alert.CatalogConcept, default catalogDefault: DeviceAlertSeverity) {
        if severity == catalogDefault {
            overrides.removeValue(forKey: concept.storableKey)
        } else {
            overrides[concept.storableKey] = severity
        }
    }

    func clear(_ concept: Alert.CatalogConcept) {
        overrides.removeValue(forKey: concept.storableKey)
    }

    // MARK: - Persistence

    private func bind() {
        $overrides
            .dropFirst()
            .removeDuplicates()
            .sink { [weak self] value in self?.encode(value) }
            .store(in: &subscriptions)
    }

    private static func decode<T: Decodable>(_: T.Type, from defaults: UserDefaults, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func encode(_ value: [String: DeviceAlertSeverity]) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
