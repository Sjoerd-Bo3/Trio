import LoopKit
import SwiftUI

/// Per-alert severity picker. Lists every device/system alert (deduped to its
/// cross-plugin `CatalogConcept`) and lets the user raise or lower its tier —
/// Critical / Time-Sensitive / Normal — overriding the catalog default. The
/// choice is read at fire time by `TrioAlertManager.issueAlert`.
///
/// Glucose alarms are configured per-alarm in the Glucose Alarms screen and
/// don't appear here.
struct AlertSeverityView: View {
    @StateObject private var store = AlertSeverityOverrideStore.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState

    private struct Row: Identifiable {
        let concept: Alert.CatalogConcept
        let defaultSeverity: DeviceAlertSeverity
        let category: String
        var id: String { concept.storableKey }
    }

    /// Concepts deduped in catalog order, grouped by their soft `category`.
    private var groups: [(category: String, rows: [Row])] {
        var seen = Set<String>()
        var rows: [Row] = []
        for entry in AlertCatalogRegistry.entries {
            let concept = entry.concept
            guard concept != .unspecified, !concept.displayTitle.isEmpty else { continue }
            guard !seen.contains(concept.storableKey) else { continue }
            guard let tier = DeviceAlertSeverity(level: entry.interruptionLevel) else { continue }
            seen.insert(concept.storableKey)
            rows.append(Row(concept: concept, defaultSeverity: tier, category: entry.category))
        }
        var order: [String] = []
        var byCategory: [String: [Row]] = [:]
        for row in rows {
            if byCategory[row.category] == nil { order.append(row.category) }
            byCategory[row.category, default: []].append(row)
        }
        return order.map { (category: $0, rows: byCategory[$0] ?? []) }
    }

    var body: some View {
        List {
            Section {
                Text(
                    "Choose how forcefully each alert interrupts you. Critical overrides Silent Mode, Do Not Disturb, and Focus. Time-Sensitive pierces banner suppression but obeys them. Normal is a standard banner."
                )
                .font(.footnote)
                .foregroundColor(.secondary)
            }.listRowBackground(Color.chart)

            ForEach(groups, id: \.category) { group in
                Section(header: Text(group.category)) {
                    ForEach(group.rows) { row in
                        pickerRow(row)
                    }
                }.listRowBackground(Color.chart)
            }

            Section {
                Text(
                    "Glucose alarms (Urgent Low, Low, High, …) are configured individually under Glucose Alarms. Critical alerts require Apple's Critical Alerts entitlement to override Silent Mode and Focus."
                )
                .font(.footnote)
                .foregroundColor(.secondary)
            }.listRowBackground(Color.chart)
        }
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
        .navigationTitle("Alert Severity")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private func pickerRow(_ row: Row) -> some View {
        let binding = Binding<DeviceAlertSeverity>(
            get: { store.severity(for: row.concept, default: row.defaultSeverity) },
            set: { store.setSeverity($0, for: row.concept, default: row.defaultSeverity) }
        )
        Picker(selection: binding) {
            ForEach(DeviceAlertSeverity.allCases) { severity in
                Label(severity.displayName, systemImage: icon(for: severity))
                    .tag(severity)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon(for: binding.wrappedValue))
                    .foregroundStyle(tint(for: binding.wrappedValue))
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.concept.displayTitle)
                    if binding.wrappedValue != row.defaultSeverity {
                        Text("Changed from \(row.defaultSeverity.displayName)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .pickerStyle(.menu)
    }

    private func icon(for severity: DeviceAlertSeverity) -> String {
        switch severity {
        case .critical: return "exclamationmark.triangle.fill"
        case .timeSensitive: return "bell.badge.fill"
        case .normal: return "bell.fill"
        }
    }

    private func tint(for severity: DeviceAlertSeverity) -> Color {
        switch severity {
        case .critical: return .red
        case .timeSensitive: return .orange
        case .normal: return .accentColor
        }
    }
}
