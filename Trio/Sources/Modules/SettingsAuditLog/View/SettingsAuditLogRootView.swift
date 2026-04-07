import SwiftUI
import Swinject

extension SettingsAuditLog {
    struct RootView: BaseView {
        let resolver: Resolver
        @State var state = StateModel()

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        @State private var selectedEvent: ChangeEvent?
        @State private var noteText = ""
        @State private var debounceTask: Task<Void, Never>?
        @State private var showDeleteConfirmation = false
        @State private var showExportSheet = false
        @State private var csvFileURL: URL?

        var body: some View {
            List {
                categoryPicker

                if state.groupedEvents.isEmpty {
                    Section {
                        Text("No settings changes recorded yet.")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    }
                    .listRowBackground(Color.chart)
                }

                ForEach(state.groupedEvents, id: \.0) { day, dayEvents in
                    Section(header: Text(day)) {
                        ForEach(dayEvents) { event in
                            EventRow(event: event, units: state.units)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    noteText = event.note
                                    selectedEvent = event
                                }
                        }
                    }
                    .listRowBackground(Color.chart)
                }
            }
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle("Settings History")
            .navigationBarTitleDisplayMode(.automatic)
            .searchable(text: $state.searchText, placement: .navigationBarDrawer(displayMode: .automatic))
            .onAppear(perform: configureView)
            .onDisappear {
                // Flush any pending note save immediately before teardown
                if let task = debounceTask, let event = selectedEvent {
                    task.cancel()
                    debounceTask = nil
                    state.updateNote(forGroup: event.id, note: noteText)
                }
            }
            .sheet(item: $selectedEvent) { event in
                NavigationView {
                    EventDetailView(event: event, units: state.units, noteText: $noteText)
                }
            }
            .sheet(isPresented: $showExportSheet) {
                if let url = csvFileURL {
                    ShareSheet(activityItems: [url])
                }
            }
            .onChange(of: noteText) { _, newValue in
                guard let event = selectedEvent else { return }
                debounceTask?.cancel()
                debounceTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s debounce
                    guard !Task.isCancelled else { return }
                    state.updateNote(forGroup: event.id, note: newValue)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            exportCSV(grouped: false)
                        } label: {
                            Label("Export by Time", systemImage: "clock")
                        }
                        Button {
                            exportCSV(grouped: true)
                        } label: {
                            Label("Export by Group", systemImage: "rectangle.stack")
                        }
                        Divider()
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete All Entries", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .alert("Delete All Entries?", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    state.deleteAllEntries()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete all settings history entries. This action cannot be undone.")
            }
        }

        private func exportCSV(grouped: Bool) {
            let csv = grouped ? state.generateGroupedCSV() : state.generateCSV()
            let fileName = "SettingsHistory_\(Self.filenameDateFormatter.string(from: Date())).csv"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            do {
                try csv.write(to: tempURL, atomically: true, encoding: .utf8)
                csvFileURL = tempURL
                showExportSheet = true
            } catch {
                debug(.default, "Failed to write CSV: \(error)")
            }
        }

        private static let filenameDateFormatter: DateFormatter = {
            let df = DateFormatter()
            df.dateFormat = "yyyyMMdd_HHmmss"
            return df
        }()

        @ViewBuilder
        private var categoryPicker: some View {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(state.allCategories, id: \.self) { cat in
                            let isSelected = (state.selectedCategory ?? "All") == cat
                            Button {
                                state.selectedCategory = cat == "All" ? nil : cat
                                state.loadEntries()
                            } label: {
                                Text(cat)
                                    .font(.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.2))
                                    .foregroundColor(isSelected ? .white : .primary)
                                    .cornerRadius(12)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .listRowBackground(Color.chart)
        }
    }
}

// MARK: - EventRow

private struct EventRow: View {
    let event: SettingsAuditLog.ChangeEvent
    let units: GlucoseUnits

    private static let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.timeStyle = .short
        return df
    }()

    private var timeString: String {
        Self.timeFormatter.string(from: event.date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.summaryLabel)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(event.categories.joined(separator: ", "))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(timeString)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if !event.note.isEmpty {
                        Image(systemName: "note.text")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                    }
                }
            }

            ForEach(event.entries) { entry in
                VStack(spacing: 2) {
                    HStack(spacing: 4) {
                        Text(entry.settingName)
                            .font(.caption2)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Spacer()
                        Text(entry.displayValue(entry.oldValue, units: units))
                            .font(.caption2)
                            .foregroundColor(.red)
                            .lineLimit(1)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                        Text(entry.displayValue(entry.newValue, units: units))
                            .font(.caption2)
                            .foregroundColor(.green)
                            .lineLimit(1)
                        if let displayUnit = entry.displayUnit(units: units) {
                            Text(displayUnit)
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                    }
                    if let oldTotal = entry.dailyBasalTotal(from: entry.oldValue),
                       let newTotal = entry.dailyBasalTotal(from: entry.newValue)
                    {
                        HStack(spacing: 4) {
                            Spacer()
                            Text("Daily total:")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                            Text(oldTotal)
                                .font(.system(size: 9))
                                .foregroundColor(.red)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 7))
                                .foregroundColor(.secondary)
                            Text(newTotal)
                                .font(.system(size: 9))
                                .foregroundColor(.green)
                        }
                    }
                }
            }

            // Show note text on overview when present
            if !event.note.isEmpty {
                Text(event.note)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - EventDetailView

private struct EventDetailView: View {
    let event: SettingsAuditLog.ChangeEvent
    let units: GlucoseUnits
    @Binding var noteText: String

    @Environment(\.dismiss) var dismiss

    private static let detailFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }()

    private var formattedDate: String {
        Self.detailFormatter.string(from: event.date)
    }

    var body: some View {
        Form {
            Section("Event") {
                LabeledContent("Date", value: formattedDate)
                LabeledContent("Changes", value: "\(event.entries.count)")
                LabeledContent("Categories", value: event.categories.joined(separator: ", "))
            }
            Section("Changes") {
                ForEach(event.entries) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.settingName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        HStack(spacing: 4) {
                            Text(entry.displayValue(entry.oldValue, units: units))
                                .font(.caption)
                                .foregroundColor(.red)
                                .lineLimit(1)
                            Image(systemName: "arrow.right")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(entry.displayValue(entry.newValue, units: units))
                                .font(.caption)
                                .foregroundColor(.green)
                                .lineLimit(1)
                            if let displayUnit = entry.displayUnit(units: units) {
                                Text(displayUnit)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        if let oldTotal = entry.dailyBasalTotal(from: entry.oldValue),
                           let newTotal = entry.dailyBasalTotal(from: entry.newValue)
                        {
                            HStack(spacing: 4) {
                                Text("Daily total:")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(oldTotal)
                                    .font(.caption2)
                                    .foregroundColor(.red)
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 8))
                                    .foregroundColor(.secondary)
                                Text(newTotal)
                                    .font(.caption2)
                                    .foregroundColor(.green)
                            }
                        }
                        if !entry.subcategory.isEmpty {
                            Text(entry.subcategory)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            Section("Note") {
                TextEditor(text: $noteText)
                    .frame(minHeight: 80)
                if !noteText.isEmpty {
                    Text("Notes are saved automatically")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Change Event")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}


