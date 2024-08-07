import SwiftUI
import Swinject

extension AutotuneConfig {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()

        @State private var shouldDisplayHint: Bool = false
        @State var hintDetent = PresentationDetent.large
        @State var selectedVerboseHint: String?
        @State var hintLabel: String?
        @State private var decimalPlaceholder: Decimal = 0.0
        @State private var booleanPlaceholder: Bool = false

        @State var replaceAlert = false

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

        private var isfFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            return formatter
        }

        private var rateFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            return formatter
        }

        private var dateFormatter: DateFormatter {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter
        }

        var body: some View {
            Form {
                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.useAutotune,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0
                            hintLabel = "Use Autotune"
                        }
                    ),
                    type: .boolean,
                    label: "Use Autotune",
                    miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                    verboseHint: "Autotune… bla bla bla",
                    headerText: "Data-driven Adjustments"
                )

                if state.useAutotune {
                    SettingInputSection(
                        decimalValue: $decimalPlaceholder,
                        booleanValue: $state.onlyAutotuneBasals,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0
                                hintLabel = "Only Autotune Basal Insulin"
                            }
                        ),
                        type: .boolean,
                        label: "Only Autotune Basal Insulin",
                        miniHint: "Lorem ipsum dolor sit amet, consetetur sadipscing elitr.",
                        verboseHint: "Only Autotune Basal Insulin… bla bla bla"
                    )
                }

                Section(
                    header: HStack {
                        Text("Last run")
                        Spacer()
                        Text(dateFormatter.string(from: state.publishedDate))
                    },
                    content: {
                        Button {
                            state.run()
                        } label: {
                            Text("Run now")
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color(.systemBlue))
                        .tint(.white)
                    }
                )

                if let autotune = state.autotune {
                    if !state.onlyAutotuneBasals {
                Section {
                    HStack {
                        Text("Carb ratio")
                        Spacer()
                        Text(isfFormatter.string(from: autotune.carbRatio as NSNumber) ?? "0")
                        Text("g/U").foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Sensitivity")
                        Spacer()
                        if state.units == .mmolL {
                            Text(isfFormatter.string(from: autotune.sensitivity.asMmolL as NSNumber) ?? "0")
                        } else {
                            Text(isfFormatter.string(from: autotune.sensitivity as NSNumber) ?? "0")
                        }
                        Text(state.units.rawValue + "/U").foregroundColor(.secondary)
                    }
                }
                .listRowBackground(Color.chart)
                    }

                Section(header: Text("Basal profile")) {
                    ForEach(0 ..< autotune.basalProfile.count, id: \.self) { index in
                        HStack {
                            Text(autotune.basalProfile[index].start).foregroundColor(.secondary)
                            Spacer()
                            Text(rateFormatter.string(from: autotune.basalProfile[index].rate as NSNumber) ?? "0")
                            Text("U/hr").foregroundColor(.secondary)
                        }
                    }
                    HStack {
                        Text("Total")
                            .bold()
                            .foregroundColor(.primary)
                        Spacer()
                        Text(rateFormatter.string(from: autotune.basalProfile.reduce(0) { $0 + $1.rate } as NSNumber) ?? "0")
                            .foregroundColor(.primary) +
                            Text(" U/day")
                            .foregroundColor(.secondary)
                    }
                }
                .listRowBackground(Color.chart)

                Section {
                    Button {
                        Task {
                            await state.delete()
                        }
                    } label: {
                        Text("Delete Autotune Data")
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color(.loopRed))
                    .tint(.white)
                }

                Section {
                    Button {
                        replaceAlert = true
                    } label: {
                        Text("Save as Normal Basal Rates")
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color(.systemGray4))
                    .tint(.white)
                }
                }
            }
            .sheet(isPresented: $shouldDisplayHint) {
                SettingInputHintView(
                    hintDetent: $hintDetent,
                    shouldDisplayHint: $shouldDisplayHint,
                    hintLabel: hintLabel ?? "",
                    hintText: selectedVerboseHint ?? "",
                    sheetTitle: "Help"
                )
            }
            .scrollContentBackground(.hidden).background(color)
            .onAppear(perform: configureView)
            .navigationTitle("Autotune")
            .navigationBarTitleDisplayMode(.automatic)
            .alert(Text("Are you sure?"), isPresented: $replaceAlert) {
                Button("Yes", action: {
                    state.replace()
                    replaceAlert.toggle()
                })
                Button("No", action: { replaceAlert.toggle() })
            }
        }
    }
}
