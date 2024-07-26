import SwiftUI
import Swinject

enum Screen: Identifiable, Hashable {
    case loading
    case home
    case settings
    case configEditor(file: String)
    case nighscoutConfig
    case nighscoutConfigDirect
    case pumpConfig
    case pumpConfigDirect
    case pumpSettingsEditor
    case basalProfileEditor
    case isfEditor
    case crEditor
    case targetsEditor
    case preferencesEditor
    case bolus
    case manualTempBasal
    case autotuneConfig
    case dataTable
    case cgm
    case cgmDirect
    case healthkit
    case notificationsConfig
    case fpuConfig
    case iconConfig
    case overrideConfig
    case snooze
    case statistics
    case watch
    case statisticsConfig
    case bolusCalculatorConfig
    case dynamicISF
    case calibrations
    case shortcutsConfig
    case devices
    case therapySettings
    case featureSettings
    case notificationSettings
    case serviceSettings

    var id: Int { String(reflecting: self).hashValue }
}

extension Screen {
    @ViewBuilder func view(resolver: Resolver) -> some View {
        switch self {
        case .loading:
            ProgressView()
        case .home:
            Home.RootView(resolver: resolver)
        case .settings:
            Settings.RootView(resolver: resolver)
        case let .configEditor(file):
            ConfigEditor.RootView(resolver: resolver, file: file)
        case .nighscoutConfig:
            NightscoutConfig.RootView(resolver: resolver, displayClose: false)
        case .nighscoutConfigDirect:
            NightscoutConfig.RootView(resolver: resolver, displayClose: true)
        case .pumpConfig:
            PumpConfig.RootView(resolver: resolver, displayClose: false)
        case .pumpConfigDirect:
            PumpConfig.RootView(resolver: resolver, displayClose: true)
        case .pumpSettingsEditor:
            PumpSettingsEditor.RootView(resolver: resolver)
        case .basalProfileEditor:
            BasalProfileEditor.RootView(resolver: resolver)
        case .isfEditor:
            ISFEditor.RootView(resolver: resolver)
        case .crEditor:
            CREditor.RootView(resolver: resolver)
        case .targetsEditor:
            TargetsEditor.RootView(resolver: resolver)
        case .preferencesEditor:
            PreferencesEditor.RootView(resolver: resolver)
        case .bolus:
            Bolus.RootView(resolver: resolver)
        case .manualTempBasal:
            ManualTempBasal.RootView(resolver: resolver)
        case .autotuneConfig:
            AutotuneConfig.RootView(resolver: resolver)
        case .dataTable:
            DataTable.RootView(resolver: resolver)
        case .cgm:
            CGM.RootView(resolver: resolver, displayClose: false)
        case .cgmDirect:
            CGM.RootView(resolver: resolver, displayClose: true)
        case .healthkit:
            AppleHealthKit.RootView(resolver: resolver)
        case .notificationsConfig:
            NotificationsConfig.RootView(resolver: resolver)
        case .fpuConfig:
            FPUConfig.RootView(resolver: resolver)
        case .iconConfig:
            IconConfig.RootView(resolver: resolver)
        case .overrideConfig:
            OverrideConfig.RootView(resolver: resolver)
        case .snooze:
            Snooze.RootView(resolver: resolver)
        case .watch:
            WatchConfig.RootView(resolver: resolver)
        case .statistics:
            Stat.RootView(resolver: resolver)
        case .statisticsConfig:
            StatConfig.RootView(resolver: resolver)
        case .bolusCalculatorConfig:
            BolusCalculatorConfig.RootView(resolver: resolver)
        case .dynamicISF:
            Dynamic.RootView(resolver: resolver)
        case .calibrations:
            Calibrations.RootView(resolver: resolver)
        case .shortcutsConfig:
            ShortcutsConfig.RootView(resolver: resolver)
        case .devices:
            DevicesView(resolver: resolver, state: Settings.StateModel())
        case .therapySettings:
            TherapySettingsView(resolver: resolver, state: Settings.StateModel())
        case .featureSettings:
            FeatureSettingsView(resolver: resolver, state: Settings.StateModel())
        case .notificationSettings:
            NotificationsView(resolver: resolver, state: Settings.StateModel())
        case .serviceSettings:
            ServicesView(resolver: resolver, state: Settings.StateModel())
        }
    }

    func modal(resolver: Resolver) -> Main.Modal {
        .init(screen: self, view: view(resolver: resolver).asAny())
    }
}
