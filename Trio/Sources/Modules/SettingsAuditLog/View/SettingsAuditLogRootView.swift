import CoreData
import SwiftUI
import Swinject

extension SettingsAuditLog {
    struct RootView: BaseView {
        let resolver: Resolver
        @State var state = StateModel()

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        @State private var selectedEntry: SettingsChangeStored?
        @State private var showNoteEditor = false
        @State private var noteText = ""

        var body: some View {
            List {
                categoryPicker

                if state.groupedEntries.isEmpty {
                    Section {
                        Text("No settings changes recorded yet.")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    }
                    .listRowBackground(Color.chart)
                }

                ForEach(state.groupedEntries, id: \.0) { day, dayEntries in
                    Section(header: Text(day)) {
                        ForEach(dayEntries, id: \.objectID) { entry in
                            EntryRow(entry: entry)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedEntry = entry
                                    noteText = entry.note ?? ""
                                    showNoteEditor = true
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
            .sheet(isPresented: $showNoteEditor) {
                noteEditorSheet
            }
        }

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

        @ViewBuilder
        private var noteEditorSheet: some View {
            if let entry = selectedEntry {
                NavigationView {
                    EntryDetailView(entry: entry, noteText: $noteText) {
                        state.updateNote(for: entry, note: noteText)
                        showNoteEditor = false
                    }
                }
            }
        }
    }
}

// MARK: - EntryRow

private struct EntryRow: View {
    let entry: SettingsChangeStored

    private static let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.timeStyle = .short
        return df
    }()

    private var timeString: String {
        guard let date = entry.date else { return "" }
        return Self.timeFormatter.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.settingName ?? "Unknown Setting")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text(entry.subcategory ?? entry.category ?? "")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(timeString)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if entry.note?.isEmpty == false {
                        Image(systemName: "note.text")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                    }
                }
            }
            HStack(spacing: 4) {
                Text(entry.oldValue ?? "—")
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(1)
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(entry.newValue ?? "—")
                    .font(.caption)
                    .foregroundColor(.green)
                    .lineLimit(1)
                if let unit = entry.unit, !unit.isEmpty {
                    Text(unit)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - EntryDetailView

private struct EntryDetailView: View {
    let entry: SettingsChangeStored
    @Binding var noteText: String
    let onSave: () -> Void

    @Environment(\.dismiss) var dismiss

    private static let detailFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }()

    private var formattedDate: String {
        guard let date = entry.date else { return "—" }
        return Self.detailFormatter.string(from: date)
    }

    var body: some View {
        Form {
            Section("Setting") {
                LabeledContent("Name", value: entry.settingName ?? "—")
                LabeledContent("Category", value: entry.category ?? "—")
                LabeledContent("Subcategory", value: entry.subcategory ?? "—")
                LabeledContent("Date", value: formattedDate)
                LabeledContent("Source", value: entry.source ?? "—")
            }
            Section("Change") {
                LabeledContent("Old Value", value: "\(entry.oldValue ?? "—")\(entry.unit.map { " \($0)" } ?? "")")
                LabeledContent("New Value", value: "\(entry.newValue ?? "—")\(entry.unit.map { " \($0)" } ?? "")")
            }
            Section("Note") {
                TextEditor(text: $noteText)
                    .frame(minHeight: 80)
            }
        }
        .navigationTitle("Change Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { onSave() }
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }
}
