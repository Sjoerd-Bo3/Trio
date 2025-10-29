import SwiftUI

/// Observable object that manages hint display state for settings views
class SettingsHintManager: ObservableObject {
    @Published var shouldDisplayHint: Bool = false
    @Published var hintDetent: PresentationDetent = .large
    @Published var selectedVerboseHint: AnyView?
    @Published var hintLabel: String?
    @Published var decimalPlaceholder: Decimal = 0.0
    @Published var booleanPlaceholder: Bool = false
    
    /// Creates a binding for selectedVerboseHint with a label setter
    func verboseHintBinding(label: String) -> Binding<(any View)?> {
        Binding(
            get: { self.selectedVerboseHint },
            set: {
                self.selectedVerboseHint = $0.map { AnyView($0) }
                self.hintLabel = label
            }
        )
    }
}

/// View modifier that provides hint display functionality for settings views
struct SettingsHintModifier: ViewModifier {
    @ObservedObject var hintManager: SettingsHintManager
    
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $hintManager.shouldDisplayHint) {
                SettingInputHintView(
                    hintDetent: $hintManager.hintDetent,
                    shouldDisplayHint: $hintManager.shouldDisplayHint,
                    hintLabel: hintManager.hintLabel ?? "",
                    hintText: hintManager.selectedVerboseHint ?? AnyView(EmptyView()),
                    sheetTitle: String(localized: "Help", comment: "Help sheet title")
                )
            }
    }
}

extension View {
    /// Adds settings hint display functionality to a view
    func settingsHint(manager: SettingsHintManager) -> some View {
        modifier(SettingsHintModifier(hintManager: manager))
    }
}
