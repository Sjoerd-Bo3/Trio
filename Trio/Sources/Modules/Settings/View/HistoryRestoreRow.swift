import SwiftUI

/// Opt-in restore of the treatment history a backup carries. Entries the phone already has are skipped.
struct HistoryRestoreRow: View {
    let backup: TrioSettingsBackup
    @Bindable var model: SensitiveRestoreModel
    @State private var counts: [SettingsBackupHistory.HistoryCount]?

    static func isRelevant(_ backup: TrioSettingsBackup) -> Bool { backup.treatmentHistory != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Restore Treatment History", isOn: $model.restoreHistory)
            if let counts {
                ForEach(counts) { item in
                    LabeledContent(item.label, value: "\(item.count)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Text("Readings and entries this phone already has are skipped, so restoring twice adds nothing.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .task {
            // Decoding months of history takes a moment; do it once, off the body.
            counts = (try? backup.historyTier()).map { SettingsBackupHistory.previewCounts($0) }
        }
    }
}
