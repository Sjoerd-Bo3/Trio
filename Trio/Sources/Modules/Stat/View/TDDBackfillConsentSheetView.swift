import SwiftUI

/// One-time, opt-in sheet offering to import historical daily Total Daily Dose from the user's own
/// Nightscout site. Surfaced once (gated by `tddBackfillConsentDecisionMade`) for existing users on
/// the update that introduced the 1-year insulin view; picking either option records the decision so
/// it never re-appears.
///
/// The import itself is injected as `runBackfill` so this view stays decoupled from the
/// `NightscoutManager` (resolved in `TrioApp`). The work runs against the user's server only.
struct TDDBackfillConsentSheetView: View {
    @Environment(\.dismiss) private var dismiss

    /// Runs the import. Receives a 0...1 progress handler (unused by the indeterminate UI here, but
    /// part of the manager's contract) and returns the number of days imported.
    let runBackfill: (@escaping @Sendable (Double) -> Void) async -> Int

    private enum Phase: Equatable {
        case intro
        case running
        case done(Int)
    }

    @State private var phase: Phase = .intro

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Import insulin history from Nightscout?")
                        .font(.title2)
                        .bold()

                    Text(
                        "Trio can now show your Total Daily Dose for up to a year. Days recorded on this device are already available. To fill in days from before you installed Trio — or to recover history after reinstalling on a new phone — Trio can read your daily totals back from your Nightscout site."
                    )
                    .font(.subheadline)

                    Text(
                        "This makes one small request per missing day, directly to your own Nightscout server. Nothing is shared with anyone else. If you skip, no past history is imported, but every day you record from now on is kept automatically."
                    )
                    .font(.footnote)
                    .foregroundColor(.secondary)

                    switch phase {
                    case .running:
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Importing your insulin history…")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 4)
                    case let .done(count):
                        Label(
                            count > 0
                                ? "Imported \(count) day\(count == 1 ? "" : "s") of history."
                                : "No additional history was found on Nightscout.",
                            systemImage: count > 0 ? "checkmark.circle.fill" : "info.circle"
                        )
                        .font(.subheadline)
                        .foregroundColor(count > 0 ? .green : .secondary)
                        .padding(.top, 4)
                    case .intro:
                        EmptyView()
                    }
                }
                .padding()
            }
            .safeAreaInset(edge: .bottom) {
                buttons
                    .padding()
                    .background(.ultraThinMaterial)
            }
            .navigationTitle("Insulin History")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(phase == .running)
        }
    }

    @ViewBuilder private var buttons: some View {
        switch phase {
        case .intro:
            VStack(spacing: 12) {
                Button(action: startImport) {
                    Text("Import History")
                        .bold()
                        .frame(maxWidth: .infinity, minHeight: 30, alignment: .center)
                }
                .buttonStyle(.borderedProminent)

                Button(action: decline) {
                    Text("Not Now")
                        .frame(maxWidth: .infinity, minHeight: 30, alignment: .center)
                }
                .buttonStyle(.bordered)
            }
        case .running:
            Button(action: {}) {
                Text("Importing…")
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .center)
            }
            .buttonStyle(.borderedProminent)
            .disabled(true)
        case .done:
            Button(action: { dismiss() }) {
                Text("Done")
                    .bold()
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .center)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func startImport() {
        // Record the decision immediately so the prompt never reappears, even if the import fails.
        PropertyPersistentFlags.shared.tddBackfillConsentDecisionMade = true
        phase = .running
        Task {
            let imported = await runBackfill { _ in }
            PropertyPersistentFlags.shared.tddBackfillCompletedAt = Date()
            phase = .done(imported)
        }
    }

    private func decline() {
        PropertyPersistentFlags.shared.tddBackfillConsentDecisionMade = true
        dismiss()
    }
}
