import Charts
import SwiftUI

let screenSize: CGRect = UIScreen.main.bounds
let calendar = Calendar.current

private struct BasalProfile: Hashable {
    let amount: Double
    var isOverwritten: Bool
    let startDate: Date
    let endDate: Date?
    init(amount: Double, isOverwritten: Bool, startDate: Date, endDate: Date? = nil) {
        self.amount = amount
        self.isOverwritten = isOverwritten
        self.startDate = startDate
        self.endDate = endDate
    }
}

private struct Prediction: Hashable {
    let amount: Int
    let timestamp: Date
    let type: PredictionType
}

private struct Carb: Hashable {
    let amount: Decimal
    let timestamp: Date
    let nearestGlucose: BloodGlucose
}

private struct ChartBolus: Hashable {
    let amount: Decimal
    let timestamp: Date
    let nearestGlucose: BloodGlucose
}

private enum PredictionType: Hashable {
    case iob
    case cob
    case zt
    case uam
}

struct MainChartView2: View {
    private enum Config {
        static let bolusSize: CGFloat = 4
        static let bolusScale: CGFloat = 2.5
        static let carbsSize: CGFloat = 5
        static let carbsScale: CGFloat = 0.3
        static let fpuSize: CGFloat = 5
    }

    @Binding var glucose: [BloodGlucose]
    @Binding var eventualBG: Int?
    @Binding var suggestion: Suggestion?
    @Binding var tempBasals: [PumpHistoryEvent]
    @Binding var boluses: [PumpHistoryEvent]
    @Binding var suspensions: [PumpHistoryEvent]
    @Binding var announcement: [Announcement]
    @Binding var hours: Int
    @Binding var maxBasal: Decimal
    @Binding var autotunedBasalProfile: [BasalProfileEntry]
    @Binding var basalProfile: [BasalProfileEntry]
    @Binding var tempTargets: [TempTarget]
    @Binding var carbs: [CarbsEntry]
    @Binding var smooth: Bool
    @Binding var highGlucose: Decimal
    @Binding var lowGlucose: Decimal
    @Binding var screenHours: Int16
    @Binding var displayXgridLines: Bool
    @Binding var displayYgridLines: Bool
    @Binding var thresholdLines: Bool

    @State var didAppearTrigger = false
    @State private var BasalProfiles: [BasalProfile] = []
    @State private var TempBasals: [PumpHistoryEvent] = []
    @State private var ChartTTs: [TempTarget] = []
    @State private var Predictions: [Prediction] = []
    @State private var ChartCarbs: [Carb] = []
    @State private var ChartFpus: [Carb] = []
    @State private var ChartBoluses: [ChartBolus] = []
    @State private var startMarker = Date(timeIntervalSince1970: TimeInterval(NSDate().timeIntervalSince1970 - 86400))
    @State private var endMarker = Date(timeIntervalSince1970: TimeInterval(NSDate().timeIntervalSince1970 + 10800))

    private var bolusFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumIntegerDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.decimalSeparator = "."
        return formatter
    }

    private var carbsFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        return formatter
    }

    private var fpuFormatter: NumberFormatter {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.decimalSeparator = "."
        formatter.minimumIntegerDigits = 0
        return formatter
    }

    var body: some View {
        VStack(alignment: .center, spacing: 8, content: {
            ScrollViewReader { scroller in
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack {
                        ZStack {
                            TTs()
                            MainChart()
                        }

                        BasalChart()
                            .padding(.bottom, 8)
                    }.onChange(of: screenHours) { _ in
                        scroller.scrollTo("MainChart", anchor: .trailing)
                    }.onAppear {
                        scroller.scrollTo("MainChart", anchor: .trailing)
                    }.onChange(of: glucose) { _ in
                        scroller.scrollTo("MainChart", anchor: .trailing)
                    }
                    .onChange(of: suggestion) { _ in
                        scroller.scrollTo("MainChart", anchor: .trailing)
                    }
                    .onChange(of: tempBasals) { _ in
                        scroller.scrollTo("MainChart", anchor: .trailing)
                    }
                }
            }
            Legend()
        })
    }
}

// MARK: Components

extension MainChartView2 {
    private func MainChart() -> some View {
        VStack {
            Chart {
                if thresholdLines {
                    RuleMark(y: .value("High", highGlucose)).foregroundStyle(Color.loopYellow)
                        .lineStyle(.init(lineWidth: 1, dash: [2]))
                    RuleMark(y: .value("Low", lowGlucose)).foregroundStyle(Color.loopRed)
                        .lineStyle(.init(lineWidth: 1, dash: [2]))
                }
                RuleMark(
                    x: .value(
                        "",
                        startMarker,
                        unit: .second
                    )
                ).foregroundStyle(.clear)
                RuleMark(
                    x: .value(
                        "",
                        Date(timeIntervalSince1970: TimeInterval(NSDate().timeIntervalSince1970)),
                        unit: .second
                    )
                ).lineStyle(.init(lineWidth: 1, dash: [2]))
                RuleMark(
                    x: .value(
                        "",
                        endMarker,
                        unit: .second
                    )
                ).foregroundStyle(.clear)
                ForEach(ChartCarbs, id: \.self) { carb in
                    let carbAmount = carb.amount
                    PointMark(
                        x: .value("Time", carb.timestamp, unit: .second),
                        y: .value("Value", carb.nearestGlucose.sgv ?? 120)
                    )
                    .symbolSize((Config.carbsSize + CGFloat(carbAmount) * Config.carbsScale) * 10)
                    .foregroundStyle(Color.orange)
                    .annotation(position: .top) {
                        Text(bolusFormatter.string(from: carbAmount as NSNumber)!).font(.caption2)
                    }
                }
                ForEach(ChartFpus, id: \.self) { fpu in
                    let fpuAmount = fpu.amount
                    PointMark(
                        x: .value("Time", fpu.timestamp, unit: .second),
                        y: .value("Value", fpu.nearestGlucose.sgv ?? 120)
                    )
                    .symbolSize((Config.fpuSize + CGFloat(fpuAmount) * Config.carbsScale) * 10)
                    .foregroundStyle(Color.brown)
                    .annotation(position: .top) {
                        Text(bolusFormatter.string(from: fpuAmount as NSNumber)!).font(.caption2)
                    }
                }

                ForEach(ChartBoluses, id: \.self) { bolus in
                    let bolusAmount = bolus.amount
                    PointMark(
                        x: .value("Time", bolus.timestamp, unit: .second),
                        y: .value("Value", bolus.nearestGlucose.sgv ?? 120)
                    )
                    .symbolSize((Config.bolusSize + CGFloat(bolusAmount) * Config.bolusScale) * 10)
                    .foregroundStyle(Color.insulin)
                    .annotation(position: .bottom) {
                        Text(bolusFormatter.string(from: bolusAmount as NSNumber)!).font(.caption2)
                    }
                }
                /*  ForEach(ChartTTs, id: \.self) { tt in
                     //  let bolusAmount = tt.amount
                     LineMark(
                         x: .value("Time", tt.duration),
                         y: .value("Value", tt.targetBottom)
                     )
                     .foregroundStyle(Color.insulin)
                 }*/
                /*     ForEach(ChartTTs, id: \.self) { profile in
                     LineMark(
                         x: .value("Start Date", profile.createdAt),
                         y: .value("Amount", profile.targetBottom),
                         series: .value("profile", "profile")
                     ).lineStyle(.init(lineWidth: 2, dash: [2, 3]))
                     LineMark(
                         x: .value("End Date", profile.createdAt + 3 ?? endMarker),
                         y: .value("Amount", profile.amount),
                         series: .value("profile", "profile")
                     ).lineStyle(.init(lineWidth: 2, dash: [2, 3]))
                 }*/
                ForEach(Predictions, id: \.self) { info in
                    if info.type == .uam {
                        LineMark(
                            x: .value("Time", info.timestamp, unit: .second),
                            y: .value("Value", info.amount),
                            series: .value("uam", "uam")
                        ).foregroundStyle(Color.uam).symbolSize(16)
                    }
                    if info.type == .cob {
                        LineMark(
                            x: .value("Time", info.timestamp, unit: .second),
                            y: .value("Value", info.amount),
                            series: .value("cob", "cob")
                        ).foregroundStyle(Color.orange).symbolSize(16)
                    }
                    if info.type == .iob {
                        LineMark(
                            x: .value("Time", info.timestamp, unit: .second),
                            y: .value("Value", info.amount),
                            series: .value("iob", "iob")
                        ).foregroundStyle(Color.insulin).symbolSize(16)
                    }
                    if info.type == .zt {
                        LineMark(
                            x: .value("Time", info.timestamp, unit: .second),
                            y: .value("Value", info.amount),
                            series: .value("zt", "zt")
                        ).foregroundStyle(Color.zt).symbolSize(16)
                    }
                }
                ForEach(glucose) {
                    if $0.sgv != nil {
                        PointMark(
                            x: .value("Time", $0.dateString, unit: .second),
                            y: .value("Value", $0.sgv!)
                        ).foregroundStyle(Color.green).symbolSize(16)
                        if smooth {
                            LineMark(
                                x: .value("Time", $0.dateString, unit: .second),
                                y: .value("Value", $0.sgv!),
                                series: .value("glucose", "glucose")
                            ).foregroundStyle(Color.green)
                        }
                    }
                }
            }.id("MainChart")
                .onChange(of: glucose) { _ in
                    calculatePredictions()
                }
                .onChange(of: carbs) { _ in
                    calculateCarbs()
                    calculateFpus()
                }
                .onChange(of: boluses) { _ in
                    calculateBoluses()
                }
                .onChange(of: didAppearTrigger) { _ in
                    calculatePredictions()
                }.onChange(of: suggestion) { _ in
                    calculatePredictions()
                }
                .onReceive(
                    Foundation.NotificationCenter.default
                        .publisher(for: UIApplication.willEnterForegroundNotification)
                ) { _ in
                    calculatePredictions()
                }
                .frame(
                    width: max(0, screenSize.width - 20, fullWidth(viewWidth: screenSize.width)),
                    height: min(screenSize.height, 200)
                )
//                .chartYScale(domain: 0 ... 450)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 2)) { _ in
                        if displayXgridLines {
                            AxisGridLine(stroke: .init(lineWidth: 0.5, dash: [2, 3]))
                        } else {
                            AxisGridLine(stroke: .init(lineWidth: 0, dash: [2, 3]))
                        }
                    }
                }.chartYAxis {
                    AxisMarks(position: .trailing, values: .stride(by: 100)) { value in
                        if displayYgridLines {
                            AxisGridLine(stroke: .init(lineWidth: 0.5, dash: [2, 3]))
                        } else {
                            AxisGridLine(stroke: .init(lineWidth: 0, dash: [2, 3]))
                        }
                        if let glucoseValue = value.as(Double.self), glucoseValue > 0 {
                            AxisTick(length: 4, stroke: .init(lineWidth: 4))
                                .foregroundStyle(Color.gray)
                            AxisValueLabel()
                        }
                    }
                }
        }
    }

    func BasalChart() -> some View {
        VStack {
            Chart {
                RuleMark(
                    x: .value(
                        "",
                        startMarker,
                        unit: .second
                    )
                ).foregroundStyle(.clear)
                RuleMark(
                    x: .value(
                        "",
                        Date(timeIntervalSince1970: TimeInterval(NSDate().timeIntervalSince1970)),
                        unit: .second
                    )
                ).lineStyle(.init(lineWidth: 1, dash: [2]))
                RuleMark(
                    x: .value(
                        "",
                        endMarker,
                        unit: .second
                    )
                ).foregroundStyle(.clear)
                ForEach(TempBasals) {
                    BarMark(
                        x: .value("Time", $0.timestamp),
                        y: .value("Rate", $0.rate ?? 0)
                    )
                }
                ForEach(BasalProfiles, id: \.self) { profile in
                    LineMark(
                        x: .value("Start Date", profile.startDate),
                        y: .value("Amount", profile.amount),
                        series: .value("profile", "profile")
                    ).lineStyle(.init(lineWidth: 2, dash: [2, 3]))
                    LineMark(
                        x: .value("End Date", profile.endDate ?? endMarker),
                        y: .value("Amount", profile.amount),
                        series: .value("profile", "profile")
                    ).lineStyle(.init(lineWidth: 2, dash: [2, 3]))
                }
            }.onChange(of: tempBasals) { _ in
                calculateBasals()
                calculateTempBasals()
            }
            .onChange(of: maxBasal) { _ in
                calculateBasals()
                calculateTempBasals()
            }
            .onChange(of: autotunedBasalProfile) { _ in
                calculateBasals()
                calculateTempBasals()
            }
            .onChange(of: didAppearTrigger) { _ in
                calculateBasals()
                calculateTempBasals()
            }.onChange(of: basalProfile) { _ in
                calculateBasals()
                calculateTempBasals()
            }
            .frame(height: 80)
//            .chartYScale(domain: 0 ... maxBasal)
            //            .rotationEffect(.degrees(180))
            //            .chartXAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: screenHours == 24 ? 4 : 2)) { _ in
                    if displayXgridLines {
                        AxisGridLine(stroke: .init(lineWidth: 0.5, dash: [2, 3]))
                    } else {
                        AxisGridLine(stroke: .init(lineWidth: 0, dash: [2, 3]))
                    }
                    AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .narrow)), anchor: .top)
                }
            }.chartYAxis {
                AxisMarks(position: .trailing, values: .stride(by: 1)) { _ in
                    if displayYgridLines {
                        AxisGridLine(stroke: .init(lineWidth: 0.5, dash: [2, 3]))
                    } else {
                        AxisGridLine(stroke: .init(lineWidth: 0, dash: [2, 3]))
                    }
                    AxisTick(length: 30, stroke: .init(lineWidth: 4))
                        .foregroundStyle(Color.clear)
                }
            }

            .chartPlotStyle { plotArea in
                plotArea.background(.blue.gradient.opacity(0.1))
            }
        }
    }

    private func TTs() -> some View {
        Chart(tempTargets) {
            PointMark(x: .value("Time", $0.dateString), y: .value("value", $0.value))
        }
    }

    private func Legend() -> some View {
        HStack {
            Image(systemName: "line.diagonal")
                .rotationEffect(Angle(degrees: 45))
                .foregroundColor(.green)
            Text("BG")
                .foregroundColor(.secondary)
            Spacer()
            Image(systemName: "line.diagonal")
                .rotationEffect(Angle(degrees: 45))
                .foregroundColor(.insulin)
            Text("IOB")
                .foregroundColor(.secondary)
            Spacer()
            Image(systemName: "line.diagonal")
                .rotationEffect(Angle(degrees: 45))
                .foregroundColor(.purple)
            Text("ZT")
                .foregroundColor(.secondary)
            Spacer()
            Image(systemName: "line.diagonal")
                .frame(height: 10)
                .rotationEffect(Angle(degrees: 45))
                .foregroundColor(.loopYellow)
            Text("COB")
                .foregroundColor(.secondary)
            Spacer()
            Image(systemName: "line.diagonal")
                .rotationEffect(Angle(degrees: 45))
                .foregroundColor(.orange)
            Text("UAM")
                .foregroundColor(.secondary)
            if eventualBG != nil {
                Text("⇢ " + String(eventualBG ?? 0))
            }
        }
        .font(.caption2)
        .padding(.horizontal, 40)
        .padding(.vertical, 1)
    }
}

// MARK: Calculations

extension MainChartView2 {
    private func timeToNearestGlucose(time: TimeInterval) -> BloodGlucose {
        var nextIndex = 0
        if glucose.last?.dateString.timeIntervalSince1970 ?? Date().timeIntervalSince1970 < time {
            return glucose.last ?? BloodGlucose(
                date: 0,
                dateString: Date(),
                unfiltered: nil,
                filtered: nil,
                noise: nil,
                type: nil
            )
        }
        for (index, value) in glucose.enumerated() {
            if value.dateString.timeIntervalSince1970 > time {
                nextIndex = index
                print("Break", value.dateString.timeIntervalSince1970, time)
                break
            }
        }
        return glucose[nextIndex]
    }

    private func fullWidth(viewWidth: CGFloat) -> CGFloat {
        viewWidth * CGFloat(hours) / CGFloat(min(max(screenHours, 2), 24))
    }

    private func calculateCarbs() {
        var calculatedCarbs: [Carb] = []
        carbs.forEach { carb in
            let bg = timeToNearestGlucose(time: carb.createdAt.timeIntervalSince1970)
            calculatedCarbs.append(Carb(amount: carb.carbs, timestamp: carb.createdAt, nearestGlucose: bg))
        }
        ChartCarbs = calculatedCarbs
    }

    private func calculateFpus() {
        var calculatedFpus: [Carb] = []
        let fpus = carbs.filter { $0.isFPU ?? false }
        fpus.forEach { fpu in
            let bg = timeToNearestGlucose(time: fpu.createdAt.timeIntervalSince1970)
            calculatedFpus.append(Carb(amount: fpu.carbs, timestamp: fpu.actualDate ?? Date(), nearestGlucose: bg))
        }
        ChartFpus = calculatedFpus
    }

    private func calculateBoluses() {
        var calculatedBoluses: [ChartBolus] = []
        boluses.forEach { bolus in
            let bg = timeToNearestGlucose(time: bolus.timestamp.timeIntervalSince1970)
            calculatedBoluses.append(ChartBolus(amount: bolus.amount ?? 0, timestamp: bolus.timestamp, nearestGlucose: bg))
        }
        ChartBoluses = calculatedBoluses
    }

    private func calculateTTs() {
        var calculatedTTs: [TempTarget] = []
        tempTargets.indices.forEach { index in
            calculatedTTs.append(TempTarget(
                name: tempTargets[index].name,
                createdAt: tempTargets[index].createdAt,
                targetTop: tempTargets[index].targetTop,
                targetBottom: tempTargets[index].targetBottom,
                duration: tempTargets[index].duration,
                enteredBy: tempTargets[index].enteredBy,
                reason: tempTargets[index].enteredBy
            ))
        }
        ChartTTs = calculatedTTs
    }

    /* private func calculateTTs() {
         var calculatedTTs: [TempTarget] = []
         tempTargets.forEach { tt in
             calculatedTTs
                 .append(TempTarget(
                     id: tt.id,
                     name: tt.name,
                     createdAt: tt.createdAt,
                     targetTop: tt.targetTop,
                     targetBottom: tt.targetBottom,
                     duration: tt.duration,
                     enteredBy: tt.enteredBy,
                     reason: tt.reason
                 ))
         }
         ChartTTs = calculatedTTs
     }*/

    private func calculatePredictions() {
        var calculatedPredictions: [Prediction] = []
        let uam = suggestion?.predictions?.uam ?? []
        let iob = suggestion?.predictions?.iob ?? []
        let cob = suggestion?.predictions?.cob ?? []
        let zt = suggestion?.predictions?.zt ?? []
        guard let deliveredAt = suggestion?.deliverAt else {
            return
        }
        uam.indices.forEach { index in
            let predTime = Date(
                timeIntervalSince1970: deliveredAt.timeIntervalSince1970 + TimeInterval(index) * 5.minutes
                    .timeInterval
            )
            if predTime.timeIntervalSince1970 < endMarker.timeIntervalSince1970 {
                calculatedPredictions.append(
                    Prediction(amount: uam[index], timestamp: predTime, type: .uam)
                )
            }
        }
        iob.indices.forEach { index in
            let predTime = Date(
                timeIntervalSince1970: deliveredAt.timeIntervalSince1970 + TimeInterval(index) * 5.minutes
                    .timeInterval
            )
            if predTime.timeIntervalSince1970 < endMarker.timeIntervalSince1970 {
                calculatedPredictions.append(
                    Prediction(amount: iob[index], timestamp: predTime, type: .iob)
                )
            }
        }
        cob.indices.forEach { index in
            let predTime = Date(
                timeIntervalSince1970: deliveredAt.timeIntervalSince1970 + TimeInterval(index) * 5.minutes
                    .timeInterval
            )
            if predTime.timeIntervalSince1970 < endMarker.timeIntervalSince1970 {
                calculatedPredictions.append(
                    Prediction(amount: cob[index], timestamp: predTime, type: .cob)
                )
            }
        }
        zt.indices.forEach { index in
            let predTime = Date(
                timeIntervalSince1970: deliveredAt.timeIntervalSince1970 + TimeInterval(index) * 5.minutes
                    .timeInterval
            )
            if predTime.timeIntervalSince1970 < endMarker.timeIntervalSince1970 {
                calculatedPredictions.append(
                    Prediction(amount: zt[index], timestamp: predTime, type: .zt)
                )
            }
        }
        Predictions = calculatedPredictions
    }

    private func getLastUam() -> Int {
        let uam = suggestion?.predictions?.uam ?? []
        return uam.last ?? 0
    }

    private func calculateTempBasals() {
        var basals = tempBasals
        var returnTempBasalRates: [PumpHistoryEvent] = []
        var finished: [Int: Bool] = [:]
        basals.indices.forEach { i in
            basals.indices.forEach { j in
                if basals[i].timestamp == basals[j].timestamp, i != j, !(finished[i] ?? false), !(finished[j] ?? false) {
                    let rate = basals[i].rate ?? basals[j].rate
                    let durationMin = basals[i].durationMin ?? basals[j].durationMin
                    finished[i] = true
                    if rate != 0 || durationMin != 0 {
                        returnTempBasalRates.append(
                            PumpHistoryEvent(
                                id: basals[i].id, type: FreeAPS.EventType.tempBasal,
                                timestamp: basals[i].timestamp,
                                durationMin: durationMin,
                                rate: rate
                            )
                        )
                    }
                }
            }
        }
        TempBasals = returnTempBasalRates
    }

    private func findRegularBasalPoints(
        timeBegin: TimeInterval,
        timeEnd: TimeInterval,
        autotuned: Bool
    ) -> [BasalProfile] {
        guard timeBegin < timeEnd else {
            return []
        }
        let beginDate = Date(timeIntervalSince1970: timeBegin)
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: beginDate)

        let profile = autotuned ? autotunedBasalProfile : basalProfile

        let basalNormalized = profile.map {
            (
                time: startOfDay.addingTimeInterval($0.minutes.minutes.timeInterval).timeIntervalSince1970,
                rate: $0.rate
            )
        } + profile.map {
            (
                time: startOfDay.addingTimeInterval($0.minutes.minutes.timeInterval + 1.days.timeInterval)
                    .timeIntervalSince1970,
                rate: $0.rate
            )
        } + profile.map {
            (
                time: startOfDay.addingTimeInterval($0.minutes.minutes.timeInterval + 2.days.timeInterval)
                    .timeIntervalSince1970,
                rate: $0.rate
            )
        }

        let basalTruncatedPoints = basalNormalized.windows(ofCount: 2)
            .compactMap { window -> BasalProfile? in
                let window = Array(window)
                if window[0].time < timeBegin, window[1].time < timeBegin {
                    return nil
                }

                if window[0].time < timeBegin, window[1].time >= timeBegin {
                    let startDate = Date(timeIntervalSince1970: timeBegin)
                    let rate = window[0].rate
                    return BasalProfile(amount: Double(rate), isOverwritten: false, startDate: startDate)
                }

                if window[0].time >= timeBegin, window[0].time < timeEnd {
                    let startDate = Date(timeIntervalSince1970: window[0].time)
                    let rate = window[0].rate
                    return BasalProfile(amount: Double(rate), isOverwritten: false, startDate: startDate)
                }

                return nil
            }

        return basalTruncatedPoints
    }

    private func calculateBasals() {
        let dayAgoTime = Date().addingTimeInterval(-1.days.timeInterval).timeIntervalSince1970
        let firstTempTime = (tempBasals.first?.timestamp ?? Date()).timeIntervalSince1970

        let regularPoints = findRegularBasalPoints(
            timeBegin: dayAgoTime,
            timeEnd: endMarker.timeIntervalSince1970,
            autotuned: false
        )

        let autotunedBasalPoints = findRegularBasalPoints(
            timeBegin: dayAgoTime,
            timeEnd: endMarker.timeIntervalSince1970,
            autotuned: true
        )
        var totalBasal = regularPoints + autotunedBasalPoints
        totalBasal.sort {
            $0.startDate.timeIntervalSince1970 < $1.startDate.timeIntervalSince1970
        }
        var basals: [BasalProfile] = []
        totalBasal.indices.forEach { index in
            basals.append(BasalProfile(
                amount: totalBasal[index].amount,
                isOverwritten: totalBasal[index].isOverwritten,
                startDate: totalBasal[index].startDate,
                endDate: totalBasal.count > index + 1 ? totalBasal[index + 1].startDate : endMarker
            ))
            print(
                "Basal",
                totalBasal[index].startDate,
                totalBasal.count > index + 1 ? totalBasal[index + 1].startDate : endMarker,
                totalBasal[index].amount,
                totalBasal[index].isOverwritten
            )
        }
        BasalProfiles = basals
    }
}
