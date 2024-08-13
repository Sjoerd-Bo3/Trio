import SwiftUI

struct SettingInputSection: View {
    enum SettingInputSectionType: Equatable {
        case decimal(String)
        case boolean
        case conditionalDecimal(String)

        static func == (lhs: SettingInputSectionType, rhs: SettingInputSectionType) -> Bool {
            switch (lhs, rhs) {
            case (.boolean, .boolean):
                return true
            case let (.decimal(lhsValue), .decimal(rhsValue)):
                return lhsValue == rhsValue
            case let (.conditionalDecimal(lhsValue), .conditionalDecimal(rhsValue)):
                return lhsValue == rhsValue
            default:
                return false
            }
        }
    }

    @Binding var decimalValue: Decimal
    @Binding var booleanValue: Bool
    @Binding var shouldDisplayHint: Bool
    @Binding var selectedVerboseHint: String?

    var units: GlucoseUnits
    var type: SettingInputSectionType
    var label: String
    var conditionalLabel: String?
    var miniHint: String
    var verboseHint: String
    var headerText: String?
    var footerText: String?

    // Access the shared PickerSettingsProvider instance
    @ObservedObject private var pickerSettingsProvider = PickerSettingsProvider.shared
    @State private var displayPicker: Bool = false
    @State private var displayConditionalPicker: Bool = false

    var body: some View {
        Section(
            content: {
                VStack {
                    switch type {
                    case let .decimal(key):
                        if let setting = getPickerSetting(for: key) {
                            VStack {
                                HStack {
                                    Text(label)

                                    Spacer()

                                    Group {
                                        if setting.type == PickerSetting.PickerSettingType.glucose {
                                            Text(
                                                units == .mmolL ? decimalValue.asMmolL.description : decimalValue
                                                    .description
                                            )
                                            .foregroundColor(!displayPicker ? .primary : .accentColor)
                                            Text(units == .mgdL ? " mg/dL" : " mmol/L").foregroundColor(.secondary)
                                        } else if setting.type == PickerSetting.PickerSettingType.factor {
                                            Text("\(decimalValue * 100)")
                                                .foregroundColor(!displayPicker ? .primary : .accentColor)

                                            Text(" %").foregroundColor(.secondary)
                                        } else if setting.type == PickerSetting.PickerSettingType.insulinUnit {
                                            Text("\(decimalValue)")
                                                .foregroundColor(!displayPicker ? .primary : .accentColor)

                                            Text(NSLocalizedString(" U", comment: "Insulin unit")).foregroundColor(.secondary)
                                        } else if setting.type == PickerSetting.PickerSettingType.gramms {
                                            Text("\(decimalValue)")
                                                .foregroundColor(!displayPicker ? .primary : .accentColor)

                                            Text(NSLocalizedString(" g", comment: "gram of carbs")).foregroundColor(.secondary)
                                        } else if setting.type == PickerSetting.PickerSettingType.minute {
                                            Text("\(decimalValue)")
                                                .foregroundColor(!displayPicker ? .primary : .accentColor)

                                            Text(" min").foregroundColor(.secondary)
                                        } else if setting.type == PickerSetting.PickerSettingType.hour {
                                            Text("\(decimalValue)")
                                                .foregroundColor(!displayPicker ? .primary : .accentColor)

                                            Text(" hr").foregroundColor(.secondary)
                                        }
                                    }.onTapGesture {
                                        displayPicker.toggle()
                                    }
                                }.padding(.top)

                                if displayPicker {
                                    Picker(selection: $decimalValue, label: Text("")) {
                                        ForEach(
                                            pickerSettingsProvider.generatePickerValues(from: setting),
                                            id: \.self
                                        ) { value in
                                            if setting.type == PickerSetting.PickerSettingType.glucose {
                                                let displayValue = units == .mgdL ? value : value.asMmolL
                                                Text("\(displayValue.description)").tag(value)
                                            } else if setting.type == PickerSetting.PickerSettingType.factor {
                                                let factorValue = value * 100
                                                Text("\(factorValue.description)").tag(value)
                                            } else {
                                                Text("\(value.description)").tag(value)
                                            }
                                        }
                                    }
                                    .pickerStyle(WheelPickerStyle())
                                    .frame(maxWidth: .infinity)
                                }
                            }
                        }

                    case .boolean:
                        HStack {
                            Toggle(isOn: $booleanValue) {
                                Text(label)
                            }
                        }.padding(.top)

                    case let .conditionalDecimal(key):
                        HStack {
                            Toggle(isOn: $booleanValue) {
                                Text(label)
                            }
                        }.padding(.vertical)

                        if $booleanValue.wrappedValue {
                            if let setting = getPickerSetting(for: key) {
                                VStack {
                                    HStack {
                                        Text(conditionalLabel ?? label)

                                        Spacer()

                                        Group {
                                            if setting.type == PickerSetting.PickerSettingType.glucose {
                                                Text(
                                                    units == .mmolL ? decimalValue.asMmolL.description : decimalValue
                                                        .description
                                                )
                                                .foregroundColor(!displayPicker ? .primary : .accentColor)
                                                Text(units == .mgdL ? " mg/dL" : " mmol/L").foregroundColor(.secondary)
                                            } else if setting.type == PickerSetting.PickerSettingType.factor {
                                                Text("\(decimalValue * 100)")
                                                    .foregroundColor(!displayPicker ? .primary : .accentColor)

                                                Text(" %").foregroundColor(.secondary)
                                            } else if setting.type == PickerSetting.PickerSettingType.insulinUnit {
                                                Text("\(decimalValue)")
                                                    .foregroundColor(!displayPicker ? .primary : .accentColor)

                                                Text(NSLocalizedString(" U", comment: "Insulin unit")).foregroundColor(.secondary)
                                            } else if setting.type == PickerSetting.PickerSettingType.gramms {
                                                Text("\(decimalValue)")
                                                    .foregroundColor(!displayPicker ? .primary : .accentColor)

                                                Text(NSLocalizedString(" g", comment: "gram of carbs"))
                                                    .foregroundColor(.secondary)
                                            } else if setting.type == PickerSetting.PickerSettingType.minute {
                                                Text("\(decimalValue)")
                                                    .foregroundColor(!displayPicker ? .primary : .accentColor)

                                                Text(" min").foregroundColor(.secondary)
                                            } else if setting.type == PickerSetting.PickerSettingType.hour {
                                                Text("\(decimalValue)")
                                                    .foregroundColor(!displayPicker ? .primary : .accentColor)

                                                Text(" hr").foregroundColor(.secondary)
                                            }
                                        }.onTapGesture {
                                            displayConditionalPicker.toggle()
                                        }
                                    }.padding(.top)

                                    if displayConditionalPicker {
                                        Picker(selection: $decimalValue, label: Text("")) {
                                            ForEach(
                                                pickerSettingsProvider.generatePickerValues(from: setting),
                                                id: \.self
                                            ) { value in
                                                if setting.type == PickerSetting.PickerSettingType.glucose {
                                                    let displayValue = units == .mgdL ? value : value.asMmolL
                                                    Text("\(displayValue.description) \(units.rawValue)").tag(value)
                                                } else if setting.type == PickerSetting.PickerSettingType.factor {
                                                    let factorValue = value * 100
                                                    Text("\(factorValue.description) %").tag(value)
                                                } else {
                                                    Text("\(value.description)").tag(value)
                                                }
                                            }
                                        }
                                        .pickerStyle(WheelPickerStyle())
                                        .frame(maxWidth: .infinity)
                                    }
                                }
                            }
                        }
                    }

                    HStack(alignment: .top) {
                        Text(miniHint)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(nil)
                        Spacer()
                        Button(
                            action: {
                                shouldDisplayHint.toggle()
                                selectedVerboseHint = shouldDisplayHint ? verboseHint : nil
                            },
                            label: {
                                HStack {
                                    Image(systemName: "questionmark.circle")
                                }
                            }
                        ).buttonStyle(BorderlessButtonStyle())
                    }.padding(.vertical)
                }
            },
            header: {
                if let headerText = headerText {
                    Text(headerText)
                }
            },
            footer: {
                if let footerText = footerText {
                    Text(footerText)
                }
            }
        ).listRowBackground(Color.chart)
    }

    // Helper function to retrieve PickerSetting based on key
    private func getPickerSetting(for key: String) -> PickerSetting? {
        switch key {
        case "lowGlucose":
            return pickerSettingsProvider.settings.lowGlucose
        case "highGlucose":
            return pickerSettingsProvider.settings.highGlucose
        case "carbsRequiredThreshold":
            return pickerSettingsProvider.settings.carbsRequiredThreshold
        case "individualAdjustmentFactor":
            return pickerSettingsProvider.settings.individualAdjustmentFactor
        case "delay":
            return pickerSettingsProvider.settings.delay
        case "timeCap":
            return pickerSettingsProvider.settings.timeCap
        case "minuteInterval":
            return pickerSettingsProvider.settings.minuteInterval
        case "high":
            return pickerSettingsProvider.settings.high
        case "low":
            return pickerSettingsProvider.settings.low
        case "hours":
            return pickerSettingsProvider.settings.hours
        case "maxCarbs":
            return pickerSettingsProvider.settings.maxCarbs
        case "maxFat":
            return pickerSettingsProvider.settings.maxFat
        case "maxProtein":
            return pickerSettingsProvider.settings.maxProtein
        case "overrideFactor":
            return pickerSettingsProvider.settings.overrideFactor
        case "fattyMealFactor":
            return pickerSettingsProvider.settings.fattyMealFactor
        case "sweetMealFactor":
            return pickerSettingsProvider.settings.sweetMealFactor
        case "maxIOB":
            return pickerSettingsProvider.settings.maxIOB
        case "maxDailySafetyMultiplier":
            return pickerSettingsProvider.settings.maxDailySafetyMultiplier
        case "currentBasalSafetyMultiplier":
            return pickerSettingsProvider.settings.currentBasalSafetyMultiplier
        case "autosensMax":
            return pickerSettingsProvider.settings.autosensMax
        case "autosensMin":
            return pickerSettingsProvider.settings.autosensMin
        case "smbDeliveryRatio":
            return pickerSettingsProvider.settings.smbDeliveryRatio
        case "halfBasalExerciseTarget":
            return pickerSettingsProvider.settings.halfBasalExerciseTarget
        case "maxCOB":
            return pickerSettingsProvider.settings.maxCOB
        case "min5mCarbimpact":
            return pickerSettingsProvider.settings.min5mCarbimpact
        case "autotuneISFAdjustmentFraction":
            return pickerSettingsProvider.settings.autotuneISFAdjustmentFraction
        case "remainingCarbsFraction":
            return pickerSettingsProvider.settings.remainingCarbsFraction
        case "remainingCarbsCap":
            return pickerSettingsProvider.settings.remainingCarbsCap
        case "maxSMBBasalMinutes":
            return pickerSettingsProvider.settings.maxSMBBasalMinutes
        case "maxUAMSMBBasalMinutes":
            return pickerSettingsProvider.settings.maxUAMSMBBasalMinutes
        case "smbInterval":
            return pickerSettingsProvider.settings.smbInterval
        case "bolusIncrement":
            return pickerSettingsProvider.settings.bolusIncrement
        case "insulinPeakTime":
            return pickerSettingsProvider.settings.insulinPeakTime
        case "carbsReqThreshold":
            return pickerSettingsProvider.settings.carbsReqThreshold
        case "noisyCGMTargetMultiplier":
            return pickerSettingsProvider.settings.noisyCGMTargetMultiplier
        case "maxDeltaBGthreshold":
            return pickerSettingsProvider.settings.maxDeltaBGthreshold
        case "adjustmentFactor":
            return pickerSettingsProvider.settings.adjustmentFactor
        case "adjustmentFactorSigmoid":
            return pickerSettingsProvider.settings.adjustmentFactorSigmoid
        case "weightPercentage":
            return pickerSettingsProvider.settings.weightPercentage
        case "enableSMB_high_bg_target":
            return pickerSettingsProvider.settings.enableSMB_high_bg_target
        case "threshold_setting":
            return pickerSettingsProvider.settings.threshold_setting
        case "updateInterval":
            return pickerSettingsProvider.settings.updateInterval
        case "dia":
            return pickerSettingsProvider.settings.dia
        case "maxBolus":
            return pickerSettingsProvider.settings.maxBolus
        case "maxBasal":
            return pickerSettingsProvider.settings.maxBasal
        default:
            return nil
        }
    }
}
