import SwiftUI

extension DynamicSettings {
    struct PlaygroundView: View {
        @Binding var parameters: ISFParameters
        @Binding var isPresented: Bool
        let units: GlucoseUnits
        let currentGlucose: Double?
        let onSave: (ISFParameters) -> Void

        @State private var showLogarithmicCurve: Bool = true
        @State private var showSigmoidCurve: Bool = true
        @State private var workingParameters: ISFParameters
        @State private var showSaveConfirmation: Bool = false
        @State private var showSaveAlert: Bool = false
        @State private var showDebugValues: Bool = false

        // Helper functions for unit conversion and formatting
        private func displayISF(_ isfMgdL: Double) -> Double {
            if units == .mmolL {
                return isfMgdL * 0.0555 // Convert mg/dL to mmol/L
            } else {
                return isfMgdL
            }
        }

        private func isfFromDisplay(_ displayValue: Double) -> Double {
            if units == .mmolL {
                return displayValue / 0.0555 // Convert mmol/L back to mg/dL
            } else {
                return displayValue
            }
        }

        private var isfUnitLabel: String {
            units == .mmolL ? "mmol/L/U" : "mg/dL/U"
        }

        private func formatPercentage(_ ratio: Double) -> String {
            "\(Int(ratio * 100))%"
        }

        private func ratioFromPercentage(_ percentage: Double) -> Double {
            percentage / 100.0
        }

        init(
            parameters: Binding<ISFParameters>,
            isPresented: Binding<Bool>,
            units: GlucoseUnits,
            currentGlucose: Double?,
            onSave: @escaping (ISFParameters) -> Void
        ) {
            _parameters = parameters
            _isPresented = isPresented
            self.units = units
            self.currentGlucose = currentGlucose
            self.onSave = onSave
            _workingParameters = State(initialValue: parameters.wrappedValue)
        }

        var body: some View {
            NavigationView {
                VStack(spacing: 20) {
                    // Chart
                    ISFCurveView(
                        parameters: workingParameters,
                        units: units,
                        showLogarithmicCurve: showLogarithmicCurve,
                        showSigmoidCurve: showSigmoidCurve,
                        currentGlucose: currentGlucose,
                        isPlayground: true
                    )

                    // Legend
                    ISFLegendView(
                        showLogarithmicCurve: $showLogarithmicCurve,
                        showSigmoidCurve: $showSigmoidCurve,
                        activeFormula: workingParameters.activeFormula,
                        isPlayground: true
                    )

                    // Parameter Controls
                    ScrollView {
                        VStack(spacing: 24) {
                            algorithmSelectionSection
                            parameterSlidersSection
                        }
                        .padding(.horizontal)
                    }

                    Spacer()
                }
                .padding()
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            isPresented = false
                        }
                    }

                    ToolbarItem(placement: .principal) {
                        Text("Dynamic ISF Playground")
                            .font(.headline)
                            .fontWeight(.semibold)
                    }

                    ToolbarItem(placement: .navigationBarTrailing) {
                        HStack {
                            Button("Debug") {
                                showDebugValues = true
                            }
                            .font(.caption)

                            Button("Save") {
                                showSaveAlert = true
                            }
                            .fontWeight(.medium)
                        }
                    }
                }
                .alert("Save Dynamic ISF Settings?", isPresented: $showSaveAlert) {
                    Button("Cancel", role: .cancel) {}
                    Button("Save to Therapy Settings", role: .destructive) {
                        saveParameters()
                    }
                } message: {
                    Text(
                        "These Dynamic ISF parameters will be applied to your therapy settings and affect your insulin dosing calculations.\n\nAre you sure you want to continue?"
                    )
                }
                .alert("Settings Saved", isPresented: $showSaveConfirmation) {
                    Button("OK") {
                        isPresented = false
                    }
                } message: {
                    Text("Dynamic ISF parameters have been updated successfully.")
                }
                .sheet(isPresented: $showDebugValues) {
                    debugValuesSheet
                }
            }
        }

        private var algorithmSelectionSection: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text("Active Algorithm")
                    .font(.headline)
                    .foregroundColor(.primary)

                Picker("Algorithm", selection: $workingParameters.activeFormula) {
                    ForEach(DynamicSensitivityType.allCases) { formula in
                        Text(formula.displayName).tag(formula)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
            }
        }

        private var parameterSlidersSection: some View {
            VStack(spacing: 20) {
                if workingParameters.activeFormula == .logarithmic {
                    logarithmicParametersSection
                } else if workingParameters.activeFormula == .sigmoid {
                    sigmoidParametersSection
                }

                commonParametersSection
            }
        }

        private var logarithmicParametersSection: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("Logarithmic Parameters")
                    .font(.headline)
                    .foregroundColor(.blue)

                parameterSlider(
                    title: "Profile ISF",
                    value: Binding(
                        get: { displayISF(workingParameters.logarithmicProfileISF) },
                        set: { workingParameters.logarithmicProfileISF = isfFromDisplay($0) }
                    ),
                    range: units == .mmolL ? 1.0 ... 15.0 : 20 ... 300,
                    step: units == .mmolL ? 0.1 : 5,
                    format: units == .mmolL ? "%.1f" : "%.0f",
                    unit: isfUnitLabel
                )

                parameterSlider(
                    title: "Adjustment Factor",
                    value: Binding(
                        get: { workingParameters.logarithmicAdjustmentFactor * 100 },
                        set: { workingParameters.logarithmicAdjustmentFactor = $0 / 100 }
                    ),
                    range: 30 ... 150,
                    step: 5,
                    format: "%.0f",
                    unit: "%"
                )

                parameterSlider(
                    title: "Autosens Min",
                    value: Binding(
                        get: { workingParameters.logarithmicAutosensMin * 100 },
                        set: { workingParameters.logarithmicAutosensMin = $0 / 100 }
                    ),
                    range: 50 ... 100,
                    step: 5,
                    format: "%.0f",
                    unit: "%"
                )

                parameterSlider(
                    title: "Autosens Max",
                    value: Binding(
                        get: { workingParameters.logarithmicAutosensMax * 100 },
                        set: { workingParameters.logarithmicAutosensMax = $0 / 100 }
                    ),
                    range: 50 ... 200,
                    step: 5,
                    format: "%.0f",
                    unit: "%"
                )
            }
        }

        private var sigmoidParametersSection: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("Sigmoid Parameters")
                    .font(.headline)
                    .foregroundColor(.orange)

                parameterSlider(
                    title: "Profile ISF",
                    value: Binding(
                        get: { displayISF(workingParameters.sigmoidProfileISF) },
                        set: { workingParameters.sigmoidProfileISF = isfFromDisplay($0) }
                    ),
                    range: units == .mmolL ? 1.0 ... 15.0 : 20 ... 300,
                    step: units == .mmolL ? 0.1 : 5,
                    format: units == .mmolL ? "%.1f" : "%.0f",
                    unit: isfUnitLabel
                )

                parameterSlider(
                    title: "Adjustment Factor",
                    value: Binding(
                        get: { workingParameters.sigmoidAdjustmentFactor * 100 },
                        set: { workingParameters.sigmoidAdjustmentFactor = $0 / 100 }
                    ),
                    range: 20 ... 100,
                    step: 5,
                    format: "%.0f",
                    unit: "%"
                )

                parameterSlider(
                    title: "Target BG",
                    value: Binding(
                        get: {
                            units == .mmolL ?
                                workingParameters.displayGlucose(workingParameters.sigmoidTargetBG, units: units) :
                                workingParameters.sigmoidTargetBG
                        },
                        set: { newValue in
                            workingParameters.sigmoidTargetBG = units == .mmolL ?
                                Double(newValue.asMgdL) : newValue
                        }
                    ),
                    range: units == .mmolL ? 4.0 ... 10.0 : 70 ... 180,
                    step: units == .mmolL ? 0.1 : 5,
                    format: units == .mmolL ? "%.1f" : "%.0f",
                    unit: units.rawValue
                )

                parameterSlider(
                    title: "Autosens Min",
                    value: Binding(
                        get: { workingParameters.sigmoidAutosensMin * 100 },
                        set: { workingParameters.sigmoidAutosensMin = $0 / 100 }
                    ),
                    range: 50 ... 100,
                    step: 5,
                    format: "%.0f",
                    unit: "%"
                )

                parameterSlider(
                    title: "Autosens Max",
                    value: Binding(
                        get: { workingParameters.sigmoidAutosensMax * 100 },
                        set: { workingParameters.sigmoidAutosensMax = $0 / 100 }
                    ),
                    range: 50 ... 200,
                    step: 5,
                    format: "%.0f",
                    unit: "%"
                )
            }
        }

        private var commonParametersSection: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("Common Parameters")
                    .font(.headline)
                    .foregroundColor(.secondary)

                parameterSlider(
                    title: "TDD 24hr",
                    value: $workingParameters.tdd24hr,
                    range: 10 ... 150,
                    step: 1,
                    format: "%.0f",
                    unit: "U"
                )

                parameterSlider(
                    title: "TDD 2 weeks avg",
                    value: $workingParameters.tdd2weeks,
                    range: 10 ... 150,
                    step: 1,
                    format: "%.0f",
                    unit: "U"
                )

                parameterSlider(
                    title: "24hr to 2w ratio",
                    value: Binding(
                        get: { workingParameters.ratio24hTo2w * 100 },
                        set: { workingParameters.ratio24hTo2w = $0 / 100 }
                    ),
                    range: 5 ... 100,
                    step: 5,
                    format: "%.0f",
                    unit: "%"
                )

                parameterSlider(
                    title: "Insulin Peak Time",
                    value: $workingParameters.insulinPeakTime,
                    range: 35 ... 120,
                    step: 1,
                    format: "%.0f",
                    unit: "min"
                )

                // Debug: Show current insulin factor
                HStack {
                    Text("Insulin Factor")
                        .font(.subheadline)
                        .foregroundColor(.primary)

                    Spacer()

                    Text("\(String(format: "%.0f", workingParameters.insulinFactor))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
            }
        }

        private func parameterSlider(
            title: String,
            value: Binding<Double>,
            range: ClosedRange<Double>,
            step: Double,
            format: String,
            unit: String? = nil
        ) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.subheadline)
                        .foregroundColor(.primary)

                    Spacer()

                    Text("\(String(format: format, value.wrappedValue))\(unit != nil ? " \(unit!)" : "")")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }

                Slider(
                    value: value,
                    in: range,
                    step: step
                ) {
                    Text(title)
                } minimumValueLabel: {
                    Text(String(format: format, range.lowerBound))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } maximumValueLabel: {
                    Text(String(format: format, range.upperBound))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .accentColor(Color.insulin)
            }
            .padding(.vertical, 4)
        }

        private var debugValuesSheet: some View {
            NavigationView {
                debugContent
                    .navigationTitle("Debug Values")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                showDebugValues = false
                            }
                        }
                    }
            }
        }

        private var debugContent: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    parametersSection
                    referenceTestSection
                    isfValuesTable
                }
                .padding()
            }
        }

        private var parametersSection: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("Current Parameters")
                    .font(.headline)
                    .foregroundColor(.primary)

                Group {
                    Text("TDD 24h: \(String(format: "%.0f", workingParameters.tdd24hr))U")
                    Text("TDD 2w: \(String(format: "%.0f", workingParameters.tdd2weeks))U")
                    Text("Weighted TDD: \(String(format: "%.1f", workingParameters.weightedTDD))U")
                    Text("Insulin Factor: \(String(format: "%.0f", workingParameters.insulinFactor))")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }

        private var isfValuesTable: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text("ISF Values at Test Points")
                    .font(.headline)
                    .foregroundColor(.primary)

                tableHeader
                tableRows
            }
            .padding()
            .background(Color.gray.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }

        private var tableHeader: some View {
            HStack {
                Text("Glucose")
                    .font(.caption)
                    .fontWeight(.medium)
                    .frame(minWidth: 60, alignment: .leading)

                Text("Logarithmic")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.red)
                    .frame(minWidth: 80, alignment: .center)

                Text("Sigmoid")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.green)
                    .frame(minWidth: 80, alignment: .center)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.1))
        }

        private var tableRows: some View {
            LazyVStack(spacing: 0) {
                ForEach([40, 55, 70, 100, 140, 180, 250, 400], id: \.self) { glucoseMgdL in
                    tableRow(for: glucoseMgdL)
                }
            }
        }

        private func tableRow(for glucoseMgdL: Double) -> some View {
            let displayGlucose = workingParameters.displayGlucose(glucoseMgdL, units: units)
            let logISF = displayISF(workingParameters.logarithmicISF(glucose: glucoseMgdL))
            let sigISF = displayISF(workingParameters.sigmoidISF(glucose: glucoseMgdL))

            return HStack {
                Text(String(format: units == .mmolL ? "%.1f" : "%.0f", displayGlucose))
                    .font(.caption)
                    .monospacedDigit()
                    .frame(minWidth: 60, alignment: .leading)

                Text(String(format: "%.5g", logISF))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundColor(.red)
                    .frame(minWidth: 80, alignment: .center)

                Text(String(format: "%.5g", sigISF))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundColor(.green)
                    .frame(minWidth: 80, alignment: .center)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }

        private var referenceTestSection: some View {
            VStack(alignment: .leading, spacing: 12) {
                Text("Reference Test Values")
                    .font(.headline)
                    .foregroundColor(.red)

                Button("Load Reference Parameters") {
                    loadReferenceParameters()
                }
                .buttonStyle(.borderedProminent)

                Text("Expected Logarithmic ISF Values (mg/dL/U):")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.red)

                let referenceValues = [
                    (40, 112.29541), (55, 87.265375), (70, 72.810494), (100, 56.65068),
                    (140, 45.577557), (180, 39.222883), (250, 32.734629), (400, 26.004608)
                ]

                LazyVStack(spacing: 4) {
                    ForEach(referenceValues, id: \.0) { glucose, expectedISF in
                        let actualISF = workingParameters.logarithmicISF(glucose: Double(glucose))
                        let difference = abs(actualISF - expectedISF)
                        let isMatch = difference < 0.001

                        HStack {
                            Text("BG \(glucose):")
                                .font(.caption)
                                .frame(width: 60, alignment: .leading)

                            Text("Expected \(String(format: "%.5g", expectedISF))")
                                .font(.caption)
                                .frame(width: 90, alignment: .leading)

                            Text("Actual \(String(format: "%.5g", actualISF))")
                                .font(.caption)
                                .foregroundColor(isMatch ? .green : .red)
                                .frame(width: 80, alignment: .leading)

                            Text(isMatch ? "✓" : "✗")
                                .font(.caption)
                                .foregroundColor(isMatch ? .green : .red)
                        }
                    }
                }
                .font(.caption)
                .monospacedDigit()

                Divider()
                    .padding(.vertical, 8)

                Text("Expected Sigmoid ISF Values (mg/dL/U):")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.green)

                // Sigmoid reference values - exact reference implementation results
                let sigmoidReferenceValues = [
                    (40, 55.479599), (55, 54.170453), (70, 52.788814), (100, 50.0),
                    (140, 46.765034), (180, 44.501109), (250, 42.555252), (400, 41.728511)
                ]

                LazyVStack(spacing: 4) {
                    ForEach(sigmoidReferenceValues, id: \.0) { glucose, expectedISF in
                        let actualISF = workingParameters.sigmoidISF(glucose: Double(glucose))
                        let difference = abs(actualISF - expectedISF)
                        let isMatch = difference < 0.1 // Ruimere tolerantie voor sigmoid

                        HStack {
                            Text("BG \(glucose):")
                                .font(.caption)
                                .frame(width: 60, alignment: .leading)

                            Text("Expected \(String(format: "%.5g", expectedISF))")
                                .font(.caption)
                                .frame(width: 90, alignment: .leading)

                            Text("Actual \(String(format: "%.5g", actualISF))")
                                .font(.caption)
                                .foregroundColor(isMatch ? .green : .red)
                                .frame(width: 80, alignment: .leading)

                            Text(isMatch ? "✓" : "✗")
                                .font(.caption)
                                .foregroundColor(isMatch ? .green : .red)
                        }
                    }
                }
                .font(.caption)
                .monospacedDigit()
            }
            .padding()
            .background(Color.red.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }

        private func loadReferenceParameters() {
            // Load exact reference test parameters - DO NOT CHANGE!
            workingParameters.tdd24hr = 50.0
            workingParameters.tdd2weeks = 50.0
            workingParameters.ratio24hTo2w = 0.65
            workingParameters.logarithmicAdjustmentFactor = 0.75
            workingParameters.logarithmicProfileISF = 50.0 // Corrected: was 46.0, should be 50.0
            workingParameters.logarithmicAutosensMax = 1.2
            workingParameters.logarithmicAutosensMin = 0.8
            workingParameters.insulinPeakTime = 45.0

            // Sigmoid reference parameters
            workingParameters.sigmoidProfileISF = 50.0
            workingParameters.sigmoidAdjustmentFactor = 0.5
            workingParameters.sigmoidTargetBG = 100.0
            workingParameters.sigmoidAutosensMax = 1.2
            workingParameters.sigmoidAutosensMin = 0.8
        }

        private func saveParameters() {
            onSave(workingParameters)
            parameters = workingParameters
            showSaveConfirmation = true
        }
    }
}
