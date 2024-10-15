import SwiftUI
import Swinject

extension ISFEditor {
    struct RootView: BaseView {
        let resolver: Resolver
        @State var state = StateModel()
        @State private var editMode = EditMode.inactive

        @Environment(\.colorScheme) var colorScheme
        var color: LinearGradient {
            colorScheme == .dark ? LinearGradient(
                gradient: Gradient(colors: [
                    Color.bgDarkBlue,
                    Color.bgDarkerDarkBlue
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
                :
                LinearGradient(
                    gradient: Gradient(colors: [Color.gray.opacity(0.1)]),
                    startPoint: .top,
                    endPoint: .bottom
                )
        }

        private var dateFormatter: DateFormatter {
            let formatter = DateFormatter()
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.timeStyle = .short
            return formatter
        }

        private var rateFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            return formatter
        }

        var body: some View {
            Form {
                let shouldDisableButton = state.items.isEmpty || !state.hasChanges

                if let autotune = state.autotune, !state.settingsManager.settings.onlyAutotuneBasals {
                    Section(header: Text("Autotune")) {
                        HStack {
                            Text("Calculated Sensitivity")
                            Spacer()
                            if state.units == .mgdL {
                                Text(autotune.sensitivity.description)
                            } else {
                                Text(autotune.sensitivity.formattedAsMmolL)
                            }
                            Text(state.units.rawValue + "/U").foregroundColor(.secondary)
                        }
                    }.listRowBackground(Color.chart)
                }
                if let newISF = state.autosensISF {
                    Section(
                        header: !state.settingsManager.preferences
                            .useNewFormula ? Text("Autosens") : Text("Dynamic Sensitivity")
                    ) {
                        let dynamicRatio = state.determinationsFromPersistence.first?.sensitivityRatio
                        let dynamicISF = state.determinationsFromPersistence.first?.insulinSensitivity
                        HStack {
                            Text("Sensitivity Ratio")
                            Spacer()
                            Text(
                                rateFormatter
                                    .string(from: (
                                        (
                                            !state.settingsManager.preferences.useNewFormula ? state
                                                .autosensRatio as NSDecimalNumber : dynamicRatio
                                        ) ?? 1
                                    ) as NSNumber) ?? "1"
                            )
                        }
                        HStack {
                            Text("Calculated Sensitivity")
                            Spacer()
                            if state.units == .mgdL {
                                Text(
                                    !state.settingsManager.preferences
                                        .useNewFormula ? newISF.description : (dynamicISF ?? 0).description
                                )
                            } else {
                                Text((
                                    !state.settingsManager.preferences
                                        .useNewFormula ? newISF.formattedAsMmolL : dynamicISF?.decimalValue.formattedAsMmolL
                                ) ?? "0")
                            }
                            Text(state.units.rawValue + "/U").foregroundColor(.secondary)
                        }
                    }.listRowBackground(Color.chart)
                }

                Section(header: Text("Schedule")) {
                    list
                }.listRowBackground(Color.chart)

                Section {
                    HStack {
                        if state.shouldDisplaySaving {
                            ProgressView().padding(.trailing, 10)
                        }

                        Button {
                            let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
                            impactHeavy.impactOccurred()
                            state.save()

                            // deactivate saving display after 1.25 seconds
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.25) {
                                state.shouldDisplaySaving = false
                            }
                        } label: {
                            Text(state.shouldDisplaySaving ? "Saving..." : "Save")
                        }
                        .disabled(shouldDisableButton)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .tint(.white)
                    }
                }.listRowBackground(shouldDisableButton ? Color(.systemGray4) : Color(.systemBlue))
            }
            .scrollContentBackground(.hidden).background(color)
            .onAppear(perform: configureView)
            .navigationTitle("Insulin Sensitivities")
            .navigationBarTitleDisplayMode(.automatic)
            .toolbar(content: {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    addButton
                }
            })
            .environment(\.editMode, $editMode)
            .onAppear {
                state.validate()
            }
        }

        private func pickers(for index: Int) -> some View {
            Form {
                Section {
                    Picker(selection: $state.items[index].rateIndex, label: Text("Rate")) {
                        ForEach(0 ..< state.rateValues.count, id: \.self) { i in
                            Text(
                                state.units == .mgdL ? state.rateValues[i].description : state.rateValues[i]
                                    .formattedAsMmolL + " \(state.units.rawValue)/U"
                            ).tag(i)
                        }
                    }
                }.listRowBackground(Color.chart)

                Section {
                    Picker(selection: $state.items[index].timeIndex, label: Text("Time")) {
                        ForEach(0 ..< state.timeValues.count, id: \.self) { i in
                            Text(
                                self.dateFormatter
                                    .string(from: Date(
                                        timeIntervalSince1970: state
                                            .timeValues[i]
                                    ))
                            ).tag(i)
                        }
                    }
                }.listRowBackground(Color.chart)
            }
            .padding(.top)
            .scrollContentBackground(.hidden).background(color)
            .navigationTitle("Set Rate")
            .navigationBarTitleDisplayMode(.automatic)
        }

        private var list: some View {
            List {
                ForEach(state.items.indexed(), id: \.1.id) { index, item in
                    let displayValue = state.units == .mgdL ? state.rateValues[item.rateIndex].description : state
                        .rateValues[item.rateIndex].formattedAsMmolL

                    NavigationLink(destination: pickers(for: index)) {
                        HStack {
                            Text("Rate").foregroundColor(.secondary)

                            Text(
                                displayValue + " \(state.units.rawValue)/U"
                            )
                            Spacer()
                            Text("starts at").foregroundColor(.secondary)
                            Text(
                                "\(dateFormatter.string(from: Date(timeIntervalSince1970: state.timeValues[item.timeIndex])))"
                            )
                        }
                    }
                    .moveDisabled(true)
                }
                .onDelete(perform: onDelete)
            }
        }

        private var addButton: some View {
            guard state.canAdd else {
                return AnyView(EmptyView())
            }

            switch editMode {
            case .inactive:
                return AnyView(Button(action: onAdd) { Image(systemName: "plus") })
            default:
                return AnyView(EmptyView())
            }
        }

        func onAdd() {
            state.add()
        }

        private func onDelete(offsets: IndexSet) {
            state.items.remove(atOffsets: offsets)
            state.validate()
        }
    }
}
