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
}

private struct ChartBolus: Hashable {
    let amount: Decimal
    let timestamp: Date
    let nearestGlucose: BloodGlucose
    let yPosition: Decimal
}

private struct ChartTempTarget: Hashable {
    let amount: Decimal
    let start: Date
    let end: Date
}

private enum PredictionType: Hashable {
    case iob
    case cob
    case zt
    case uam
}

struct MainChartView: View {
    private enum Config {
        static let bolusSize: CGFloat = 5
        static let bolusScale: CGFloat = 1
        static let carbsSize: CGFloat = 5
        static let carbsScale: CGFloat = 0.3
        static let fpuSize: CGFloat = 10
        static let maxGlucose = 270
        static let minGlucose = 45
    }

    @Binding var glucose: [BloodGlucose]
    @Binding var manualGlucose: [BloodGlucose]
    @Binding var units: GlucoseUnits
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
    @Binding var isTempTargetActive: Bool

    @StateObject var state = Home.StateModel()

    @State var didAppearTrigger = false
    @State private var BasalProfiles: [BasalProfile] = []
    @State private var TempBasals: [PumpHistoryEvent] = []
    @State private var ChartTempTargets: [ChartTempTarget] = []
    @State private var Predictions: [Prediction] = []
    @State private var ChartCarbs: [Carb] = []
    @State private var ChartFpus: [Carb] = []
    @State private var ChartBoluses: [ChartBolus] = []
    @State private var count: Decimal = 1
    @State private var startMarker = Date(timeIntervalSince1970: TimeInterval(NSDate().timeIntervalSince1970 - 86400))
    @State private var endMarker = Date(timeIntervalSince1970: TimeInterval(NSDate().timeIntervalSince1970 + 10800))
    @State private var glucoseUpdateCount = 0
    @State private var maxUpdateCount = 2
    @State private var minValue: Int = 45
    @State private var maxValue: Int = 270

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

    private var conversionFactor: Decimal {
        units == .mmolL ? 0.0555 : 1
    }

    private var upperLimit: Decimal {
        units == .mgdL ? 400 : 22.2
    }

    private var defaultBolusPosition: Int {
        units == .mgdL ? 120 : 7
    }

    private var bolusOffset: Decimal {
        units == .mgdL ? 30 : 1.66
    }

    var body: some View {
        VStack {
            ScrollViewReader { scroller in
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(spacing: 2) {
                        BasalChart()

                        MainChart()

                    }.onChange(of: screenHours) { _ in
                        updateStartEndMarkers()
                        scroller.scrollTo("MainChart", anchor: .trailing)
                    }.onChange(of: glucose) { _ in
                        updateStartEndMarkers()
                        scroller.scrollTo("MainChart", anchor: .trailing)
                    }
                    .onChange(of: suggestion) { _ in
                        updateStartEndMarkers()
                        scroller.scrollTo("MainChart", anchor: .trailing)
                    }
                    .onChange(of: tempBasals) { _ in
                        updateStartEndMarkers()
                        scroller.scrollTo("MainChart", anchor: .trailing)
                    }
                    .onAppear {
                        updateStartEndMarkers()
                        scroller.scrollTo("MainChart", anchor: .trailing)
                    }
                }
            }
            legendPanel.padding(.top, 8)
        }
    }
}

// MARK: Components

extension MainChartView {
    private func MainChart() -> some View {
        VStack {
            Chart {
                /// high and low treshold lines
                if thresholdLines {
                    RuleMark(y: .value("High", highGlucose * conversionFactor)).foregroundStyle(Color.loopYellow)
                        .lineStyle(.init(lineWidth: 1))
                    RuleMark(y: .value("Low", lowGlucose * conversionFactor)).foregroundStyle(Color.loopRed)
                        .lineStyle(.init(lineWidth: 1))
                }
                RuleMark(
                    x: .value(
                        "",
                        Date(timeIntervalSince1970: TimeInterval(NSDate().timeIntervalSince1970)),
                        unit: .second
                    )
                ).lineStyle(.init(lineWidth: 2, dash: [3])).foregroundStyle(Color.insulin)
                RuleMark(
                    x: .value(
                        "",
                        startMarker,
                        unit: .second
                    )
                ).foregroundStyle(Color.clear)
                RuleMark(
                    x: .value(
                        "",
                        endMarker,
                        unit: .second
                    )
                ).foregroundStyle(Color.clear)
                /// carbs
                ForEach(ChartCarbs, id: \.self) { carb in
                    let carbAmount = carb.amount
                    let yPosition = units == .mgdL ? 60 : 3.33

                    PointMark(
                        x: .value("Time", carb.timestamp, unit: .second),
                        y: .value("Value", yPosition)
                    )
                    .symbolSize((Config.carbsSize + CGFloat(carbAmount) * Config.carbsScale) * 10)
                    .foregroundStyle(Color.orange)
                    .annotation(position: .bottom) {
                        Text(carbsFormatter.string(from: carbAmount as NSNumber)!).font(.caption2).foregroundStyle(Color.orange)
                    }
                }
                /// fpus
                ForEach(ChartFpus, id: \.self) { fpu in
                    let fpuAmount = fpu.amount
                    let size = (Config.fpuSize + CGFloat(fpuAmount) * Config.carbsScale) * 1.8
                    let yPosition = units == .mgdL ? 60 : 3.33

                    PointMark(
                        x: .value("Time", fpu.timestamp, unit: .second),
                        y: .value("Value", yPosition)
                    )
                    .symbolSize(size)
                    .foregroundStyle(Color.brown)
                }
                /// smbs in triangle form
                ForEach(ChartBoluses, id: \.self) { bolus in
                    let bolusAmount = bolus.amount
                    let size = (Config.bolusSize + CGFloat(bolusAmount) * Config.bolusScale) * 1.8

                    PointMark(
                        x: .value("Time", bolus.timestamp, unit: .second),
                        y: .value("Value", bolus.yPosition)
                    )
                    .symbol {
                        Image(systemName: "arrowtriangle.down.fill").font(.system(size: size)).foregroundStyle(Color.insulin)
                    }
                    .annotation(position: .top) {
                        Text(bolusFormatter.string(from: bolusAmount as NSNumber)!).font(.caption2).foregroundStyle(Color.insulin)
                    }
                }
                /// temp targets
                ForEach(ChartTempTargets, id: \.self) { target in
                    let targetLimited = min(max(target.amount, 0), upperLimit)

                    RuleMark(
                        xStart: .value("Start", target.start),
                        xEnd: .value("End", target.end),
                        y: .value("Value", targetLimited)
                    )
                    .foregroundStyle(Color.purple.opacity(0.5)).lineStyle(.init(lineWidth: 8))
                }
                /// predictions
                ForEach(Predictions, id: \.self) { info in
                    let y = max(info.amount, 0)

                    if info.type == .uam {
                        LineMark(
                            x: .value("Time", info.timestamp, unit: .second),
                            y: .value("Value", Decimal(y) * conversionFactor),
                            series: .value("uam", "uam")
                        ).foregroundStyle(Color.uam).symbolSize(16)
                    }
                    if info.type == .cob {
                        LineMark(
                            x: .value("Time", info.timestamp, unit: .second),
                            y: .value("Value", Decimal(y) * conversionFactor),
                            series: .value("cob", "cob")
                        ).foregroundStyle(Color.orange).symbolSize(16)
                    }
                    if info.type == .iob {
                        LineMark(
                            x: .value("Time", info.timestamp, unit: .second),
                            y: .value("Value", Decimal(y) * conversionFactor),
                            series: .value("iob", "iob")
                        ).foregroundStyle(Color.insulin).symbolSize(16)
                    }
                    if info.type == .zt {
                        LineMark(
                            x: .value("Time", info.timestamp, unit: .second),
                            y: .value("Value", Decimal(y) * conversionFactor),
                            series: .value("zt", "zt")
                        ).foregroundStyle(Color.zt).symbolSize(16)
                    }
                }
                /// glucose point mark
                /// filtering for high and low bounds in settings
                ForEach(glucose) { item in
                    if let sgv = item.sgv {
                        let sgvLimited = max(sgv, 0)

                        if smooth {
                            if sgvLimited > Int(highGlucose) {
                                PointMark(
                                    x: .value("Time", item.dateString, unit: .second),
                                    y: .value("Value", Decimal(sgvLimited) * conversionFactor)
                                ).foregroundStyle(Color.orange.gradient).symbolSize(25).interpolationMethod(.cardinal)
                            } else if sgvLimited < Int(lowGlucose) {
                                PointMark(
                                    x: .value("Time", item.dateString, unit: .second),
                                    y: .value("Value", Decimal(sgvLimited) * conversionFactor)
                                ).foregroundStyle(Color.red.gradient).symbolSize(25).interpolationMethod(.cardinal)
                            } else {
                                PointMark(
                                    x: .value("Time", item.dateString, unit: .second),
                                    y: .value("Value", Decimal(sgvLimited) * conversionFactor)
                                ).foregroundStyle(Color.green.gradient).symbolSize(25).interpolationMethod(.cardinal)
                            }
                        } else {
                            if sgvLimited > Int(highGlucose) {
                                PointMark(
                                    x: .value("Time", item.dateString, unit: .second),
                                    y: .value("Value", Decimal(sgvLimited) * conversionFactor)
                                ).foregroundStyle(Color.orange.gradient).symbolSize(25)
                            } else if sgvLimited < Int(lowGlucose) {
                                PointMark(
                                    x: .value("Time", item.dateString, unit: .second),
                                    y: .value("Value", Decimal(sgvLimited) * conversionFactor)
                                ).foregroundStyle(Color.red.gradient).symbolSize(25)
                            } else {
                                PointMark(
                                    x: .value("Time", item.dateString, unit: .second),
                                    y: .value("Value", Decimal(sgvLimited) * conversionFactor)
                                ).foregroundStyle(Color.green.gradient).symbolSize(25)
                            }
                        }
                    }
                }
                /// manual glucose mark
                ForEach(manualGlucose) { item in
                    if let manualGlucose = item.glucose {
                        PointMark(
                            x: .value("Time", item.dateString, unit: .second),
                            y: .value("Value", Decimal(manualGlucose) * conversionFactor)
                        )
                        .symbol {
                            Image(systemName: "drop.fill").font(.system(size: 10)).symbolRenderingMode(.monochrome)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }.id("MainChart")
                .onChange(of: glucose) { _ in
                    calculatePredictions()
                    calculateFpus()
                }
                .onChange(of: carbs) { _ in
                    calculateCarbs()
                    calculateFpus()
                }
                .onChange(of: boluses) { _ in
                    calculateBoluses()
                    state.roundedTotalBolus = state.calculateTINS()
                }
                .onChange(of: tempTargets) { _ in
                    calculateTTs()
                }
                .onChange(of: didAppearTrigger) { _ in
                    calculatePredictions()
                    calculateTTs()
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
                    minHeight: UIScreen.main.bounds.height / 3.6
                )
                .frame(width: fullWidth(viewWidth: screenSize.width))
                .chartXScale(domain: startMarker ... endMarker)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: screenHours == 24 ? 4 : 2)) { _ in
                        if displayXgridLines {
                            AxisGridLine(stroke: .init(lineWidth: 0.5, dash: [2, 3]))
                        } else {
                            AxisGridLine(stroke: .init(lineWidth: 0, dash: [2, 3]))
                        }
                        AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .narrow)), anchor: .top)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing) { value in
                        let upperLimit = units == .mgdL ? 400 : 22.2

                        if displayXgridLines {
                            AxisGridLine(stroke: .init(lineWidth: 0.5, dash: [2, 3]))
                        } else {
                            AxisGridLine(stroke: .init(lineWidth: 0, dash: [2, 3]))
                        }

                        if let glucoseValue = value.as(Double.self), glucoseValue > 0, glucoseValue < upperLimit {
                            /// fix offset between the two charts...
                            if units == .mmolL {
                                AxisTick(length: 7, stroke: .init(lineWidth: 7)).foregroundStyle(Color.clear)
                            }
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
                        Date(timeIntervalSince1970: TimeInterval(NSDate().timeIntervalSince1970)),
                        unit: .second
                    )
                ).lineStyle(.init(lineWidth: 2, dash: [3])).foregroundStyle(Color.insulin)
                RuleMark(
                    x: .value(
                        "",
                        startMarker,
                        unit: .second
                    )
                ).foregroundStyle(Color.clear)
                RuleMark(
                    x: .value(
                        "",
                        endMarker,
                        unit: .second
                    )
                ).foregroundStyle(Color.clear)
                /// temp basal rects
                ForEach(TempBasals) { temp in
                    /// calculate end time of temp basal adding duration to start time
                    let end = temp.timestamp + (temp.durationMin ?? 0).minutes.timeInterval
                    let now = Date()

                    /// ensure that temp basals that are set cannot exceed current date -> i.e. scheduled temp basals are not shown
                    /// we could display scheduled temp basals with opacity etc... in the future
                    let maxEndTime = min(end, now)

                    /// set mark height to 0 when insulin delivery is suspended
                    let isInsulinSuspended = suspensions
                        .first(where: { $0.timestamp >= temp.timestamp && $0.timestamp <= maxEndTime }) != nil
                    let rate = (temp.rate ?? 0) * (isInsulinSuspended ? 0 : 1)

                    /// find next basal entry and if available set end of current entry to start of next entry
                    if let nextTemp = TempBasals.first(where: { $0.timestamp > temp.timestamp }) {
                        let nextTempStart = nextTemp.timestamp

                        RectangleMark(
                            xStart: .value("start", temp.timestamp),
                            xEnd: .value("end", nextTempStart),
                            yStart: .value("rate-start", 0),
                            yEnd: .value("rate-end", rate)
                        ).foregroundStyle(Color.insulin.opacity(0.2))

                        LineMark(x: .value("Start Date", temp.timestamp), y: .value("Amount", rate))
                            .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.insulin)

                        LineMark(x: .value("End Date", nextTempStart), y: .value("Amount", rate))
                            .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.insulin)
                    } else {
                        RectangleMark(
                            xStart: .value("start", temp.timestamp),
                            xEnd: .value("end", maxEndTime),
                            yStart: .value("rate-start", 0),
                            yEnd: .value("rate-end", rate)
                        ).foregroundStyle(Color.insulin.opacity(0.2))

                        LineMark(x: .value("Start Date", temp.timestamp), y: .value("Amount", rate))
                            .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.insulin)

                        LineMark(x: .value("End Date", maxEndTime), y: .value("Amount", rate))
                            .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.insulin)
                    }
                }

                /// dashed profile line
                ForEach(BasalProfiles, id: \.self) { profile in
                    LineMark(
                        x: .value("Start Date", profile.startDate),
                        y: .value("Amount", profile.amount),
                        series: .value("profile", "profile")
                    ).lineStyle(.init(lineWidth: 2, dash: [2, 4])).foregroundStyle(Color.insulin)
                    LineMark(
                        x: .value("End Date", profile.endDate ?? endMarker),
                        y: .value("Amount", profile.amount),
                        series: .value("profile", "profile")
                    ).lineStyle(.init(lineWidth: 2.5, dash: [2, 4])).foregroundStyle(Color.insulin)
                }

                /// pump suspensions
                ForEach(suspensions) { suspension in
                    let now = Date()

                    if suspension.type == EventType.pumpSuspend {
                        let suspensionStart = suspension.timestamp
                        let suspensionEnd = min(
                            suspensions
                                .first(where: { $0.timestamp > suspension.timestamp && $0.type == EventType.pumpResume })?
                                .timestamp ?? now,
                            now
                        )
                        let basalProfileDuringSuspension = BasalProfiles.first(where: { $0.startDate <= suspensionStart })
                        let suspensionMarkHeight = basalProfileDuringSuspension?.amount ?? 1

                        RectangleMark(
                            xStart: .value("start", suspensionStart),
                            xEnd: .value("end", suspensionEnd),
                            yStart: .value("suspend-start", 0),
                            yEnd: .value("suspend-end", suspensionMarkHeight)
                        )
                        .foregroundStyle(Color.loopGray)
                    }
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
                calculateTempBasals()
            }
            .frame(
                minHeight: UIScreen.main.bounds.height / 9.8
            )
            .frame(width: fullWidth(viewWidth: screenSize.width))
            .rotationEffect(.degrees(180))
            .scaleEffect(x: -1, y: 1)
            .chartXScale(domain: startMarker ... endMarker)
            .chartXAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: screenHours == 24 ? 4 : 2)) { _ in
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { _ in
                    AxisTick(length: 25, stroke: .init(lineWidth: 4))
                        .foregroundStyle(Color.clear)
                }
            }
        }
    }

    var legendPanel: some View {
        ZStack {
            HStack(alignment: .center) {
                Spacer()

                Group {
                    Circle().fill(Color.loopGreen).frame(width: 8, height: 8)
                    Text("BG")
                        .font(.system(size: 10, weight: .bold)).foregroundColor(.loopGreen)
                }
                Group {
                    Circle().fill(Color.insulin).frame(width: 8, height: 8)
                        .padding(.leading, 8)
                    Text("IOB")
                        .font(.system(size: 10, weight: .bold)).foregroundColor(.insulin)
                }
                Group {
                    Circle().fill(Color.zt).frame(width: 8, height: 8)
                        .padding(.leading, 8)
                    Text("ZT")
                        .font(.system(size: 10, weight: .bold)).foregroundColor(.zt)
                }
                Group {
                    Circle().fill(Color.loopYellow).frame(width: 8, height: 8).padding(.leading, 8)
                    Text("COB")
                        .font(.system(size: 10, weight: .bold)).foregroundColor(.loopYellow)
                }
                Group {
                    Circle().fill(Color.uam).frame(width: 8, height: 8)
                        .padding(.leading, 8)
                    Text("UAM")
                        .font(.system(size: 10, weight: .bold)).foregroundColor(.uam)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: Calculations

extension MainChartView {
    /// calculates the glucose value thats the nearest to parameter 'time'
    /// if time is later than all the arrays values return the last element of BloodGlucose
    private func timeToNearestGlucose(time: TimeInterval) -> BloodGlucose {
        /// If the glucose array is empty, return a default BloodGlucose object or handle it accordingly
        guard let lastGlucose = glucose.last else {
            return BloodGlucose(
                date: 0,
                dateString: Date(),
                unfiltered: nil,
                filtered: nil,
                noise: nil,
                type: nil
            )
        }

        /// If the last glucose entry is before the specified time, return the last entry
        if lastGlucose.dateString.timeIntervalSince1970 < time {
            return lastGlucose
        }

        /// Find the index of the first element in the array whose date is greater than the specified time
        if let nextIndex = glucose.firstIndex(where: { $0.dateString.timeIntervalSince1970 > time }) {
            return glucose[nextIndex]
        } else {
            /// If no such element is found, return the last element in the array
            return lastGlucose
        }
    }

    private func fullWidth(viewWidth: CGFloat) -> CGFloat {
        viewWidth * CGFloat(hours) / CGFloat(min(max(screenHours, 2), 24))
    }

    private func calculateCarbs() {
        var calculatedCarbs: [Carb] = []

        /// check if carbs are not fpus before adding them to the chart
        /// this solves the problem of a first CARB entry with the amount of the single fpu entries that was made at current time when adding ONLY fpus
        let realCarbs = carbs.filter { !($0.isFPU ?? false) }

        realCarbs.forEach { carb in
            calculatedCarbs.append(Carb(amount: carb.carbs, timestamp: carb.actualDate ?? carb.createdAt))
        }
        ChartCarbs = calculatedCarbs
    }

    private func calculateFpus() {
        var calculatedFpus: [Carb] = []

        /// check for only fpus
        let fpus = carbs.filter { $0.isFPU ?? false }

        fpus.forEach { fpu in
            calculatedFpus
                .append(Carb(amount: fpu.carbs, timestamp: fpu.actualDate ?? Date()))
        }
        ChartFpus = calculatedFpus
    }

    private func calculateBoluses() {
        var calculatedBoluses: [ChartBolus] = []
        boluses.forEach { bolus in
            let bg = timeToNearestGlucose(time: bolus.timestamp.timeIntervalSince1970)
            let yPosition = (Decimal(bg.sgv ?? defaultBolusPosition) * conversionFactor) + bolusOffset
            calculatedBoluses
                .append(ChartBolus(
                    amount: bolus.amount ?? 0,
                    timestamp: bolus.timestamp,
                    nearestGlucose: bg,
                    yPosition: yPosition
                ))
        }
        ChartBoluses = calculatedBoluses
    }

    /// calculations for temp target bar mark
    private func calculateTTs() {
        var groupedPackages: [[TempTarget]] = []
        var currentPackage: [TempTarget] = []
        var calculatedTTs: [ChartTempTarget] = []

        for target in tempTargets {
            if target.duration > 0 {
                if !currentPackage.isEmpty {
                    groupedPackages.append(currentPackage)
                    currentPackage = []
                }
                currentPackage.append(target)
            } else {
                if let lastNonZeroTempTarget = currentPackage.last(where: { $0.duration > 0 }) {
                    if target.createdAt >= lastNonZeroTempTarget.createdAt,
                       target.createdAt <= lastNonZeroTempTarget.createdAt
                       .addingTimeInterval(TimeInterval(lastNonZeroTempTarget.duration * 60))
                    {
                        currentPackage.append(target)
                    }
                }
            }
        }

        // appends last package, if exists
        if !currentPackage.isEmpty {
            groupedPackages.append(currentPackage)
        }

        for package in groupedPackages {
            guard let firstNonZeroTarget = package.first(where: { $0.duration > 0 }) else {
                continue
            }

            var end = firstNonZeroTarget.createdAt.addingTimeInterval(TimeInterval(firstNonZeroTarget.duration * 60))

            let earliestCancelTarget = package.filter({ $0.duration == 0 }).min(by: { $0.createdAt < $1.createdAt })

            if let earliestCancelTarget = earliestCancelTarget {
                end = min(earliestCancelTarget.createdAt, end)
            }

            let now = Date()
            isTempTargetActive = firstNonZeroTarget.createdAt <= now && now <= end

            if firstNonZeroTarget.targetTop != nil {
                calculatedTTs
                    .append(ChartTempTarget(
                        amount: (firstNonZeroTarget.targetTop ?? 0) * conversionFactor,
                        start: firstNonZeroTarget.createdAt,
                        end: end
                    ))
            }
        }

        ChartTempTargets = calculatedTTs
    }

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

    /// update start and  end marker to fix scroll update problem with x axis
    private func updateStartEndMarkers() {
        startMarker = Date(timeIntervalSince1970: TimeInterval(NSDate().timeIntervalSince1970 - 86400))
        endMarker = Date(timeIntervalSince1970: TimeInterval(NSDate().timeIntervalSince1970 + 10800))
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
