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

                    // Save Button
                    saveButton
                }
                .padding()
                .navigationTitle("Dynamic ISF Playground")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            isPresented = false
                        }
                    }
                }
                .alert("Settings Saved", isPresented: $showSaveConfirmation) {
                    Button("OK") {
                        isPresented = false
                    }
                } message: {
                    Text("Dynamic ISF parameters have been updated successfully.")
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
                    value: $workingParameters.logarithmicProfileISF,
                    range: 20 ... 300,
                    step: 5,
                    format: "%.0f"
                )

                parameterSlider(
                    title: "Adjustment Factor",
                    value: $workingParameters.logarithmicAdjustmentFactor,
                    range: 0.5 ... 2.0,
                    step: 0.05,
                    format: "%.2f"
                )

                parameterSlider(
                    title: "Autosens Min",
                    value: $workingParameters.logarithmicAutosensMin,
                    range: 0.5 ... 1.0,
                    step: 0.05,
                    format: "%.2f"
                )

                parameterSlider(
                    title: "Autosens Max",
                    value: $workingParameters.logarithmicAutosensMax,
                    range: 1.0 ... 2.0,
                    step: 0.05,
                    format: "%.2f"
                )
            }
        }

        private var sigmoidParametersSection: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("Sigmoid Parameters")
                    .font(.headline)
                    .foregroundColor(.red)

                parameterSlider(
                    title: "Profile ISF",
                    value: $workingParameters.sigmoidProfileISF,
                    range: 20 ... 300,
                    step: 5,
                    format: "%.0f"
                )

                parameterSlider(
                    title: "Adjustment Factor",
                    value: $workingParameters.sigmoidAdjustmentFactor,
                    range: 0.2 ... 1.0,
                    step: 0.05,
                    format: "%.2f"
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
                    range: units == .mmolL ? 3.0 ... 12.0 : 55 ... 220,
                    step: units == .mmolL ? 0.1 : 5,
                    format: units == .mmolL ? "%.1f" : "%.0f",
                    unit: units.rawValue
                )

                parameterSlider(
                    title: "Autosens Min",
                    value: $workingParameters.sigmoidAutosensMin,
                    range: 0.5 ... 1.0,
                    step: 0.05,
                    format: "%.2f"
                )

                parameterSlider(
                    title: "Autosens Max",
                    value: $workingParameters.sigmoidAutosensMax,
                    range: 1.0 ... 2.0,
                    step: 0.05,
                    format: "%.2f"
                )
            }
        }

        private var commonParametersSection: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("Common Parameters")
                    .font(.headline)
                    .foregroundColor(.secondary)

                parameterSlider(
                    title: "Insulin Peak Time",
                    value: $workingParameters.insulinPeakTime,
                    range: 30 ... 120,
                    step: 5,
                    format: "%.0f",
                    unit: "min"
                )
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

        private var saveButton: some View {
            Button(action: saveParameters) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                    Text("Save Parameters")
                        .font(.headline)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.insulin)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal)
        }

        private func saveParameters() {
            onSave(workingParameters)
            parameters = workingParameters
            showSaveConfirmation = true
        }
    }
}
