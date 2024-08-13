import SwiftUI
import Swinject

extension TargetsEditor {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()
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
            return formatter
        }

        var body: some View {
            Form {
                Section(header: Text("Schedule")) {
                    list
                }.listRowBackground(Color.chart)

                Section {
                    Button {
                        let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
                        impactHeavy.impactOccurred()
                        state.save()
                    } label: {
                        Text("Save")
                    }
                    .disabled(state.items.isEmpty)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .tint(.white)

                }.listRowBackground(state.items.isEmpty ? Color(.systemGray4) : Color(.systemBlue))
            }
            .scrollContentBackground(.hidden).background(color)
            .onAppear(perform: configureView)
            .navigationTitle("Target Glucose")
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
                    Picker(
                        selection: $state.items[index].lowIndex,
                        label: Text("Target ")
                    ) {
                        ForEach(0 ..< state.rateValues.count, id: \.self) { i in
                            Text(
                                (
                                    self.rateFormatter
                                        .string(
                                            from: state.units == .mgdL ? state.rateValues[i] as NSNumber : state.rateValues[i]
                                                .asMmolL as NSNumber
                                        ) ?? ""
                                )
                                    + " \(state.units.rawValue)"

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
            .navigationTitle("Set Target")
            .navigationBarTitleDisplayMode(.automatic)
        }

        private var list: some View {
            List {
                ForEach(state.items.indexed(), id: \.1.id) { index, item in
                    NavigationLink(destination: pickers(for: index)) {
                        HStack {
                            Text(
                                "\(rateFormatter.string(from: state.units == .mgdL ? state.rateValues[item.lowIndex] as NSNumber : state.rateValues[item.lowIndex].asMmolL as NSNumber) ?? "0")"
                            )
                            Text("\(state.units.rawValue)").foregroundColor(.secondary)
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
