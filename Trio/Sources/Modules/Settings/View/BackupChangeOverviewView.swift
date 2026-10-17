import SwiftUI

/// Lists, per settings category, what restoring a backup changes: current value to backed-up value.
struct BackupChangeOverviewView: View {
    let changeSet: ImportChangeSet
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    private var categories: [SettingsBackupCategory] {
        SettingsBackupCategory.allCases.filter { changeSet.changeCount(for: $0) > 0 }
    }

    var body: some View {
        List {
            if categories.isEmpty {
                Section {
                    Text("This backup matches your current settings.").foregroundStyle(.secondary)
                }.listRowBackground(Color.chart)
            }
            Section {
                ForEach(categories) { category in
                    NavigationLink {
                        BackupCategoryChangesView(category: category, changeSet: changeSet)
                    } label: {
                        LabeledContent(category.displayName, value: "\(changeSet.changeCount(for: category))")
                    }
                }
            }.listRowBackground(Color.chart)
        }
        .listSectionSpacing(sectionSpacing)
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
        .navigationTitle("Changes")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct BackupCategoryChangesView: View {
    let category: SettingsBackupCategory
    let changeSet: ImportChangeSet
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        List {
            if let changes = changeSet.settingChanges[category], changes.isNotEmpty {
                Section {
                    ForEach(changes) { change in changeRow(change) }
                }.listRowBackground(Color.chart)
            }
            if category == .therapy {
                ForEach(changeSet.therapyChanges) { schedule in
                    Section(schedule.label) {
                        ForEach(schedule.entryChanges) { change in changeRow(change) }
                    }.listRowBackground(Color.chart)
                }
            }
            if let presets = changeSet.presetChanges[category]?.filter({ $0.kind != .keptExisting }), presets.isNotEmpty {
                Section {
                    ForEach(presets) { preset in
                        LabeledContent(preset.name, value: preset.kind.displayName)
                    }
                }.listRowBackground(Color.chart)
            }
        }
        .listSectionSpacing(sectionSpacing)
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
        .navigationTitle(category.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func changeRow(_ change: ImportChange) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(change.label)
            HStack(spacing: 6) {
                Text(change.oldDisplay).foregroundStyle(.secondary)
                Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
                Text(change.newDisplay).foregroundStyle(Color.accentColor)
            }
            .font(.footnote)
        }
    }
}
