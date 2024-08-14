import CoreData
import SpriteKit
import SwiftDate
import SwiftUI
import Swinject

extension Home {
    struct RootView: BaseView {
        let resolver: Resolver

        @StateObject var state = StateModel()
        @State var isStatusPopupPresented = false
        @State var showCancelAlert = false
        @State var isMenuPresented = false
        @State var showTreatments = false
        @State var selectedTab: Int = 0
        @State private var statusTitle: String = ""

        struct Buttons: Identifiable {
            let label: String
            let number: String
            var active: Bool
            let hours: Int16
            var id: String { label }
        }

        @State var timeButtons: [Buttons] = [
            Buttons(label: "2 hours", number: "2", active: false, hours: 2),
            Buttons(label: "4 hours", number: "4", active: false, hours: 4),
            Buttons(label: "6 hours", number: "6", active: false, hours: 6),
            Buttons(label: "12 hours", number: "12", active: false, hours: 12),
            Buttons(label: "24 hours", number: "24", active: false, hours: 24)
        ]

        let buttonFont = Font.custom("TimeButtonFont", size: 14)

        @Environment(\.managedObjectContext) var moc
        @Environment(\.colorScheme) var colorScheme

        @FetchRequest(fetchRequest: OverrideStored.fetch(
            NSPredicate.lastActiveOverride,
            ascending: false,
            fetchLimit: 1
        )) var latestOverride: FetchedResults<OverrideStored>

        @FetchRequest(
            entity: TempTargets.entity(),
            sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)]
        ) var sliderTTpresets: FetchedResults<TempTargets>

        @FetchRequest(
            entity: TempTargetsSlider.entity(),
            sortDescriptors: [NSSortDescriptor(key: "date", ascending: false)]
        ) var enactedSliderTT: FetchedResults<TempTargetsSlider>

        // TODO: end todo

        var bolusProgressFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.minimum = 0
            formatter.maximumFractionDigits = state.settingsManager.preferences.bolusIncrement > 0.05 ? 1 : 2
            formatter.minimumFractionDigits = state.settingsManager.preferences.bolusIncrement > 0.05 ? 1 : 2
            formatter.allowsFloats = true
            formatter.roundingIncrement = Double(state.settingsManager.preferences.bolusIncrement) as NSNumber
            return formatter
        }

        private var numberFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            return formatter
        }

        private var fetchedTargetFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            if state.units == .mmolL {
                formatter.maximumFractionDigits = 1
            } else { formatter.maximumFractionDigits = 0 }
            return formatter
        }

        private var targetFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1
            return formatter
        }

        private var tirFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 0
            return formatter
        }

        private var dateFormatter: DateFormatter {
            let dateFormatter = DateFormatter()
            dateFormatter.timeStyle = .short
            return dateFormatter
        }

        private var spriteScene: SKScene {
            let scene = SnowScene()
            scene.scaleMode = .resizeFill
            scene.backgroundColor = .clear
            return scene
        }

        private var color: LinearGradient {
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

        private var historySFSymbol: String {
            if #available(iOS 17.0, *) {
                return "book.pages"
            } else {
                return "book"
            }
        }

        var glucoseView: some View {
            CurrentGlucoseView(
                timerDate: $state.timerDate,
                units: $state.units,
                alarm: $state.alarm,
                lowGlucose: $state.lowGlucose,
                highGlucose: $state.highGlucose,
                cgmAvailable: $state.cgmAvailable,
                glucose: state.glucoseFromPersistence,
                manualGlucose: state.manualGlucoseFromPersistence
            ).scaleEffect(0.9)
                .onTapGesture {
                    state.openCGM()
                }
                .onLongPressGesture {
                    let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
                    impactHeavy.impactOccurred()
                    state.showModal(for: .snooze)
                }
        }

        var pumpView: some View {
            PumpView(
                reservoir: $state.reservoir,
                name: $state.pumpName,
                expiresAtDate: $state.pumpExpiresAtDate,
                timerDate: $state.timerDate,
                timeZone: $state.timeZone,
                pumpStatusHighlightMessage: $state.pumpStatusHighlightMessage,
                battery: $state.batteryFromPersistence
            ).onTapGesture {
                state.setupPump = true
            }
        }

        var tempBasalString: String? {
            guard let lastTempBasal = state.tempBasals.last?.tempBasal, let tempRate = lastTempBasal.rate else {
                return nil
            }
            let rateString = numberFormatter.string(from: tempRate as NSNumber) ?? "0"
            var manualBasalString = ""

            if let apsManager = state.apsManager, apsManager.isManualTempBasal {
                manualBasalString = NSLocalizedString(
                    " - Manual Basal ⚠️",
                    comment: "Manual Temp basal"
                )
            }

            return rateString + " " + NSLocalizedString(" U/hr", comment: "Unit per hour with space") + manualBasalString
        }

        var overrideString: String? {
            guard let latestOverride = latestOverride.first else {
                return nil
            }

            let percent = latestOverride.percentage
            let percentString = percent == 100 ? "" : "\(percent.formatted(.number)) %"

            let unit = state.units
            var target = (latestOverride.target ?? 100) as Decimal
            target = unit == .mmolL ? target.asMmolL : target

            var targetString = target == 0 ? "" : (fetchedTargetFormatter.string(from: target as NSNumber) ?? "") + " " + unit
                .rawValue
            if tempTargetString != nil {
                targetString = ""
            }

            let duration = latestOverride.duration ?? 0
            let addedMinutes = Int(truncating: duration)
            let date = latestOverride.date ?? Date()
            let newDuration = max(
                Decimal(Date().distance(to: date.addingTimeInterval(addedMinutes.minutes.timeInterval)).minutes),
                0
            )
            let indefinite = latestOverride.indefinite
            var durationString = ""

            if !indefinite {
                if newDuration >= 1 {
                    durationString =
                        "\(newDuration.formatted(.number.grouping(.never).rounded().precision(.fractionLength(0)))) min"
                } else if newDuration > 0 {
                    durationString =
                        "\((newDuration * 60).formatted(.number.grouping(.never).rounded().precision(.fractionLength(0)))) s"
                } else {
                    /// Do not show the Override anymore
                    Task {
                        guard let objectID = self.latestOverride.first?.objectID else { return }
                        await state.cancelOverride(withID: objectID)
                    }
                }
            }

            let smbToggleString = latestOverride.smbIsOff ? " \u{20e0}" : ""

            let components = [percentString, targetString, durationString, smbToggleString].filter { !$0.isEmpty }
            return components.isEmpty ? nil : components.joined(separator: ", ")
        }

        var tempTargetString: String? {
            guard let tempTarget = state.tempTarget else {
                return nil
            }
            let target = tempTarget.targetBottom ?? 0
            let unitString = targetFormatter.string(from: (tempTarget.targetBottom?.asMmolL ?? 0) as NSNumber) ?? ""
            let rawString = (tirFormatter.string(from: (tempTarget.targetBottom ?? 0) as NSNumber) ?? "") + " " + state.units
                .rawValue

            var string = ""
            if sliderTTpresets.first?.active ?? false {
                let hbt = sliderTTpresets.first?.hbt ?? 0
                string = ", " + (tirFormatter.string(from: state.infoPanelTTPercentage(hbt, target) as NSNumber) ?? "") + " %"
            }

            let percentString = state
                .units == .mmolL ? (unitString + " mmol/L" + string) : (rawString + (string == "0" ? "" : string))
            return tempTarget.displayName + " " + percentString
        }

        var infoPanel: some View {
            HStack(alignment: .center) {
                if state.pumpSuspended {
                    Text("Pump suspended")
                        .font(.system(size: 15, weight: .bold)).foregroundColor(.loopGray)
                        .padding(.leading, 8)
                } else if let tempBasalString = tempBasalString {
                    Text(tempBasalString)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.insulin)
                        .padding(.leading, 8)
                }
                if state.totalInsulinDisplayType == .totalInsulinInScope {
                    Text(
                        "TINS: \(state.calculateTINS())" +
                            NSLocalizedString(" U", comment: "Unit in number of units delivered (keep the space character!)")
                    )
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.insulin)
                }

                if let tempTargetString = tempTargetString {
                    Text(tempTargetString)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if state.closedLoop, state.settingsManager.preferences.maxIOB == 0 {
                    Text("Max IOB: 0").font(.callout).foregroundColor(.orange).padding(.trailing, 20)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: 30)
        }

        var timeInterval: some View {
            HStack(alignment: .center) {
                ForEach(timeButtons) { button in
                    Text(button.active ? NSLocalizedString(button.label, comment: "") : button.number).onTapGesture {
                        state.hours = button.hours
                    }
                    .foregroundStyle(button.active ? (colorScheme == .dark ? Color.white : Color.black).opacity(0.9) : .secondary)
                    .frame(maxHeight: 30).padding(.horizontal, 8)
                    .background(
                        button.active ?
                            // RGB(30, 60, 95)
                            (
                                colorScheme == .dark ? Color(red: 0.1176470588, green: 0.2352941176, blue: 0.3725490196) :
                                    Color.white
                            ) :
                            Color
                            .clear
                    )
                    .cornerRadius(20)
                }
                Button(action: {
                    state.isLegendPresented.toggle()
                }) {
                    Image(systemName: "info")
                        .foregroundColor(colorScheme == .dark ? Color.white : Color.black).opacity(0.9)
                        .frame(width: 20, height: 20)
                        .background(
                            colorScheme == .dark ? Color(red: 0.1176470588, green: 0.2352941176, blue: 0.3725490196) :
                                Color.white
                        )
                        .clipShape(Circle())
                }
                .padding([.top, .bottom])
            }
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.75 : 0.33),
                radius: colorScheme == .dark ? 5 : 3
            )
            .font(buttonFont)
        }

        @ViewBuilder func mainChart(geo: GeometryProxy) -> some View {
            ZStack {
                MainChartView(
                    geo: geo,
                    units: $state.units,
                    announcement: $state.announcement,
                    hours: .constant(state.filteredHours),
                    maxBasal: $state.maxBasal,
                    autotunedBasalProfile: $state.autotunedBasalProfile,
                    basalProfile: $state.basalProfile,
                    tempTargets: $state.tempTargets,
                    smooth: $state.smooth,
                    highGlucose: $state.highGlucose,
                    lowGlucose: $state.lowGlucose,
                    screenHours: $state.hours,
                    displayXgridLines: $state.displayXgridLines,
                    displayYgridLines: $state.displayYgridLines,
                    thresholdLines: $state.thresholdLines,
                    isTempTargetActive: $state.isTempTargetActive,
                    state: state
                )
            }
            .padding(.bottom)
        }

        func highlightButtons() {
            for i in 0 ..< timeButtons.count {
                timeButtons[i].active = timeButtons[i].hours == state.hours
            }
        }

        @ViewBuilder func rightHeaderPanel(_: GeometryProxy) -> some View {
            VStack(alignment: .leading, spacing: 20) {
                /// Loop view at bottomLeading
                LoopView(
                    closedLoop: $state.closedLoop,
                    timerDate: $state.timerDate,
                    isLooping: $state.isLooping,
                    lastLoopDate: $state.lastLoopDate,
                    manualTempBasal: $state.manualTempBasal,
                    determination: state.determinationsFromPersistence
                ).onTapGesture {
                    state.isStatusPopupPresented = true
                    setStatusTitle()
                }.onLongPressGesture {
                    let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
                    impactHeavy.impactOccurred()
                    state.runLoop()
                }
                /// eventualBG string at bottomTrailing

                if let eventualBG = state.determinationsFromPersistence.first?.eventualBG {
                    let bg = eventualBG as Decimal
                    HStack {
                        Image(systemName: "arrow.right.circle")
                            .font(.system(size: 16, weight: .bold))
                        Text(
                            numberFormatter.string(
                                from: (
                                    state.units == .mmolL ? bg
                                        .asMmolL : bg
                                ) as NSNumber
                            )!
                        )
                        .font(.system(size: 16))
                    }
                } else {
                    HStack {
                        Image(systemName: "arrow.right.circle")
                            .font(.system(size: 16, weight: .bold))
                        Text("--")
                            .font(.system(size: 16))
                    }
                }
            }
        }

        @ViewBuilder func mealPanel(_: GeometryProxy) -> some View {
            HStack {
                HStack {
                    Image(systemName: "syringe.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Color.insulin)
                    Text(
                        (
                            numberFormatter
                                .string(from: (state.enactedAndNonEnactedDeterminations.first?.iob ?? 0) as NSNumber) ?? "0"
                        ) +
                            NSLocalizedString(" U", comment: "Insulin unit")
                    )
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                }

                Spacer()

                HStack {
                    Image(systemName: "fork.knife")
                        .font(.system(size: 16))
                        .foregroundColor(.loopYellow)
                    Text(
                        (
                            numberFormatter
                                .string(from: (state.enactedAndNonEnactedDeterminations.first?.cob ?? 0) as NSNumber) ?? "0"
                        ) +
                            NSLocalizedString(" g", comment: "gram of carbs")
                    )
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                }

                Spacer()

                HStack {
                    if state.pumpSuspended {
                        Text("Pump suspended")
                            .font(.system(size: 12, weight: .bold, design: .rounded)).foregroundColor(.loopGray)
                    } else if let tempBasalString = tempBasalString {
                        Image(systemName: "drop.circle")
                            .font(.system(size: 16))
                            .foregroundColor(.insulinTintColor)
                        Text(tempBasalString)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    } else {
                        Image(systemName: "drop.circle")
                            .font(.system(size: 16))
                            .foregroundColor(.insulinTintColor)
                        Text("No Data")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                }
                if state.totalInsulinDisplayType == .totalDailyDose {
                    Spacer()
                    Text(
                        "TDD: " +
                            (
                                numberFormatter
                                    .string(from: (state.determinationsFromPersistence.first?.totalDailyDose ?? 0) as NSNumber) ??
                                    "0"
                            ) +
                            NSLocalizedString(" U", comment: "Insulin unit")
                    )
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                } else {
                    Spacer()
                    HStack {
                        Text(
                            "TINS: \(state.roundedTotalBolus)" +
                                NSLocalizedString(" U", comment: "Unit in number of units delivered (keep the space character!)")
                        )
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .onChange(of: state.hours) { _ in
                            state.roundedTotalBolus = state.calculateTINS()
                        }
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                state.roundedTotalBolus = state.calculateTINS()
                            }
                        }
                    }
                }
            }.padding(.horizontal, 10)
        }

        @ViewBuilder func profileView(geo: GeometryProxy) -> some View {
            ZStack {
                /// rectangle as background
                RoundedRectangle(cornerRadius: 15)
                    .fill(
                        colorScheme == .dark ? Color(red: 0.03921568627, green: 0.133333333, blue: 0.2156862745) : Color.insulin
                            .opacity(0.1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 15))
                    .frame(height: geo.size.height * 0.08)
                    .shadow(
                        color: colorScheme == .dark ? Color(red: 0.02745098039, green: 0.1098039216, blue: 0.1411764706) :
                            Color.black.opacity(0.33),
                        radius: 3
                    )
                HStack {
                    /// actual profile view
                    Image(systemName: "person.fill")
                        .font(.system(size: 25))

                    Spacer()

                    if let overrideString = overrideString {
                        VStack {
                            Text(latestOverride.first?.name ?? "Custom Override")
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text("\(overrideString)")
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)

                        }.padding(.leading, 5)
                        Spacer()
                        Image(systemName: "xmark.app")
                            .font(.system(size: 25))
                    } else {
                        if tempTargetString == nil {
                            VStack {
                                Text("Normal Profile")
                                    .font(.subheadline)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text("100 %")
                                    .font(.caption)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }.padding(.leading, 5)
                            Spacer()
                            /// to ensure the same position....
                            Image(systemName: "xmark.app")
                                .font(.system(size: 25))
                                .foregroundStyle(Color.clear)
                        }
                    }
                }.padding(.horizontal, 10)
                    .alert(
                        "Return to Normal?", isPresented: $showCancelAlert,
                        actions: {
                            Button("No", role: .cancel) {}
                            Button("Yes", role: .destructive) {
                                Task {
                                    guard let objectID = latestOverride.first?.objectID else { return }
                                    await state.cancelOverride(withID: objectID)
                                }
                            }
                        }, message: { Text("This will change settings back to your normal profile.") }
                    )
                    .padding(.trailing, 8)
                    .onTapGesture {
                        if !latestOverride.isEmpty {
                            showCancelAlert = true
                        }
                    }
            }.padding(.horizontal, 10).padding(.bottom, 10)
                .overlay {
                    /// just show temp target if no profile is already active
                    if overrideString == nil, let tempTargetString = tempTargetString {
                        ZStack {
                            /// rectangle as background
                            RoundedRectangle(cornerRadius: 15)
                                .fill(
                                    colorScheme == .dark ? Color(red: 0.03921568627, green: 0.133333333, blue: 0.2156862745) :
                                        Color
                                        .insulin
                                        .opacity(0.2)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 15))
                                .frame(height: UIScreen.main.bounds.height / 18)
                                .shadow(
                                    color: colorScheme == .dark ? Color(
                                        red: 0.02745098039,
                                        green: 0.1098039216,
                                        blue: 0.1411764706
                                    ) :
                                        Color.black.opacity(0.33),
                                    radius: 3
                                )
                            HStack {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 25))
                                Spacer()
                                Text(tempTargetString)
                                    .font(.subheadline)
                                Spacer()
                            }.padding(.horizontal, 10)
                        }.padding(.horizontal, 10).padding(.bottom, 10)
                    }
                }
        }

        @ViewBuilder func bolusProgressBar(_ progress: Decimal) -> some View {
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 15)
                    .frame(height: 6)
                    .foregroundColor(.clear)
                    .background(
                        LinearGradient(colors: [
                            Color(red: 0.7215686275, green: 0.3411764706, blue: 1),
                            Color(red: 0.6235294118, green: 0.4235294118, blue: 0.9803921569),
                            Color(red: 0.4862745098, green: 0.5450980392, blue: 0.9529411765),
                            Color(red: 0.3411764706, green: 0.6666666667, blue: 0.9254901961),
                            Color(red: 0.262745098, green: 0.7333333333, blue: 0.9137254902)
                        ], startPoint: .leading, endPoint: .trailing)
                            .mask(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 15)
                                    .frame(width: geo.size.width * CGFloat(progress))
                            }
                    )
            }
        }

        @ViewBuilder func bolusView(geo: GeometryProxy, _ progress: Decimal) -> some View {
            /// ensure that state.lastPumpBolus has a value, i.e. there is a last bolus done by the pump and not an external bolus
            /// - TRUE:  show the pump bolus
            /// - FALSE:  do not show a progress bar at all
            if let bolusTotal = state.lastPumpBolus?.bolus?.amount {
                let bolusFraction = progress * (bolusTotal as Decimal)
                let bolusString =
                    (bolusProgressFormatter.string(from: bolusFraction as NSNumber) ?? "0")
                        + " of " +
                        (numberFormatter.string(from: bolusTotal as NSNumber) ?? "0")
                        + NSLocalizedString(" U", comment: "Insulin unit")

                ZStack {
                    /// rectangle as background
                    RoundedRectangle(cornerRadius: 15)
                        .fill(
                            colorScheme == .dark ? Color(red: 0.03921568627, green: 0.133333333, blue: 0.2156862745) : Color
                                .insulin
                                .opacity(0.2)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 15))
                        .frame(height: geo.size.height * 0.08)
                        .shadow(
                            color: colorScheme == .dark ? Color(red: 0.02745098039, green: 0.1098039216, blue: 0.1411764706) :
                                Color.black.opacity(0.33),
                            radius: 3
                        )

                    /// actual bolus view
                    HStack {
                        Image(systemName: "cross.vial.fill")
                            .font(.system(size: 25))

                        Spacer()

                        VStack {
                            Text("Bolusing")
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(bolusString)
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }.padding(.leading, 5)

                        Spacer()

                        Button {
                            state.showProgressView()
                            state.cancelBolus()
                        } label: {
                            Image(systemName: "xmark.app")
                                .font(.system(size: 25))
                        }
                    }.padding(.horizontal, 10)
                        .padding(.trailing, 8)

                }.padding(.horizontal, 10).padding(.bottom, 10)
                    .overlay(alignment: .bottom) {
                        bolusProgressBar(progress).padding(.horizontal, 18).offset(y: 48)
                    }.clipShape(RoundedRectangle(cornerRadius: 15))
            }
        }

        @ViewBuilder func mainView() -> some View {
            GeometryReader { geo in
                VStack(spacing: 0) {
                    ZStack {
                        /// glucose bobble
                        glucoseView

                        /// right panel with loop status and evBG
                        HStack {
                            Spacer()
                            rightHeaderPanel(geo)
                        }.padding(.trailing, 20)

                        /// left panel with pump related info
                        HStack {
                            pumpView
                            Spacer()
                        }.padding(.leading, 20)
                    }.padding(.top, 10)

                    mealPanel(geo).padding(.top, 20).padding(.bottom, 20)

                    mainChart(geo: geo)

                    // timeInterval.padding(.top, 12).padding(.bottom, 0)

                    if let progress = state.bolusProgress {
                        bolusView(geo: geo, progress).padding(.bottom, 0)
                    } else {
                        profileView(geo: geo).padding(.bottom, 0)
                    }
                }
                .background(color)
            }
            .onChange(of: state.hours) { _ in
                highlightButtons()
            }
            .onAppear {
                configureView {
                    highlightButtons()
                }
            }
            .navigationTitle("Home")
            .navigationBarHidden(true)
            .ignoresSafeArea(.keyboard)
            .popup(isPresented: state.isStatusPopupPresented, alignment: .top, direction: .top) {
                popup
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(colorScheme == .dark ? Color(
                                "Chart"
                            ) : Color(UIColor.darkGray))
                    )
                    .onTapGesture {
                        state.isStatusPopupPresented = false
                    }
                    .gesture(
                        DragGesture(minimumDistance: 10, coordinateSpace: .local)
                            .onEnded { value in
                                if value.translation.height < 0 {
                                    state.isStatusPopupPresented = false
                                }
                            }
                    )
            }
            .sheet(isPresented: $state.isLegendPresented) {
                NavigationStack {
                    Text(
                        "The oref algorithm determines insulin dosing based on a number of scenarios that it estimates with different types of forecasts."
                    )
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                    List {
                        DefinitionRow(
                            term: "IOB (Insulin on Board)",
                            definition: "Forecasts BG based on the amount of insulin still active in the body.",
                            color: .insulin
                        )
                        DefinitionRow(
                            term: "ZT (Zero-Temp)",
                            definition: "Forecasts the worst-case blood glucose (BG) scenario if no carbs are absorbed and insulin delivery is stopped until BG starts rising.",
                            color: .zt
                        )
                        DefinitionRow(
                            term: "COB (Carbs on Board)",
                            definition: "Forecasts BG changes by considering the amount of carbohydrates still being absorbed in the body.",
                            color: .loopYellow
                        )
                        DefinitionRow(
                            term: "UAM (Unannounced Meal)",
                            definition: "Forecasts BG levels and insulin dosing needs for unexpected meals or other causes of BG rises without prior notice.",
                            color: .uam
                        )
                    }
                    .padding(.trailing, 10)
                    .navigationBarTitle("Legend", displayMode: .inline)

                    Button { state.isLegendPresented.toggle() }
                    label: { Text("Got it!").frame(maxWidth: .infinity, alignment: .center) }
                        .buttonStyle(.bordered)
                        .padding(.top)
                }
                .padding()
                .presentationDetents(
                    [.fraction(0.9), .large],
                    selection: $state.legendSheetDetent
                )
            }
        }

        @State var settingsPath = NavigationPath()

        @ViewBuilder func tabBar() -> some View {
            ZStack(alignment: .bottom) {
                TabView(selection: $selectedTab) {
                    let carbsRequiredBadge: String? = {
                        guard let carbsRequired = state.determinationsFromPersistence.first?.carbsRequired as? Decimal,
                              state.showCarbsRequiredBadge
                        else { return nil }
                        if carbsRequired > state.settingsManager.settings.carbsRequiredThreshold {
                            let numberAsNSNumber = NSDecimalNumber(decimal: carbsRequired)
                            let formattedNumber = numberFormatter.string(from: numberAsNSNumber) ?? ""
                            return formattedNumber + " g"
                        } else {
                            return nil
                        }
                    }()

                    NavigationStack { mainView() }
                        .tabItem { Label("Main", systemImage: "chart.xyaxis.line") }
                        .badge(carbsRequiredBadge).tag(0)

                    NavigationStack { DataTable.RootView(resolver: resolver) }
                        .tabItem { Label("History", systemImage: historySFSymbol) }.tag(1)

                    Spacer()

                    NavigationStack { OverrideConfig.RootView(resolver: resolver) }
                        .tabItem {
                            Label(
                                "Adjustments",
                                systemImage: "slider.horizontal.2.gobackward"
                            ) }.tag(2)

                    NavigationStack(path: self.$settingsPath) {
                        Settings.RootView(resolver: resolver) }
                        .tabItem { Label(
                            "Settings",
                            systemImage: "gear"
                        ) }.tag(3)
                }
                .tint(Color.tabBar)

                Button(
                    action: {
                        state.showModal(for: .bolus) },
                    label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(Color.tabBar)
                            .padding(.bottom, 1)
                            .padding(.horizontal, 20)
                    }
                )
            }.ignoresSafeArea(.keyboard, edges: .bottom).blur(radius: state.waitForSuggestion ? 8 : 0)
                .onChange(of: selectedTab) { _ in
                    print("current path is empty: \(settingsPath.isEmpty)")
                    settingsPath = NavigationPath()
                }
        }

        var body: some View {
            ZStack(alignment: .center) {
                tabBar()

                if state.waitForSuggestion {
                    CustomProgressView(text: "Updating IOB...")
                }
            }
        }

        private var popup: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(statusTitle).font(.headline).foregroundColor(.white)
                    .padding(.bottom, 4)
                if let determination = state.determinationsFromPersistence.first {
                    if determination.glucose == 400 {
                        Text("Invalid CGM reading (HIGH).").font(.callout).bold().foregroundColor(.loopRed).padding(.top, 8)
                        Text("SMBs and High Temps Disabled.").font(.caption).foregroundColor(.white).padding(.bottom, 4)
                    } else {
                        TagCloudView(tags: determination.reasonParts).animation(.none, value: false)

                        Text(determination.reasonConclusion.capitalizingFirstLetter()).font(.caption).foregroundColor(.white)
                    }
                } else {
                    Text("No determination found").font(.body).foregroundColor(.white)
                }

                if let errorMessage = state.errorMessage, let date = state.errorDate {
                    Text(NSLocalizedString("Error at", comment: "") + " " + dateFormatter.string(from: date))
                        .foregroundColor(.white)
                        .font(.headline)
                        .padding(.bottom, 4)
                        .padding(.top, 8)
                    Text(errorMessage).font(.caption).foregroundColor(.loopRed)
                }
            }
        }

        private func setStatusTitle() {
            if let determination = state.determinationsFromPersistence.first {
                let dateFormatter = DateFormatter()
                dateFormatter.timeStyle = .short
                statusTitle = NSLocalizedString("Oref Determination enacted at", comment: "Headline in enacted pop up") +
                    " " +
                    dateFormatter
                    .string(from: determination.deliverAt ?? Date())
            } else {
                statusTitle = "No Oref determination"
                return
            }
        }
    }
}
