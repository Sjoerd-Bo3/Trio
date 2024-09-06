import AppIntents
import Foundation

@available(iOS 16.0, *) struct CancelOverrideIntent: AppIntent {
    // Title of the action in the Shortcuts app
    static var title = LocalizedStringResource("Cancel override", table: "ShortcutsDetail")

    // Description of the action in the Shortcuts app
    static var description = IntentDescription(.init("Cancel an active override", table: "ShortcutsDetail"))

    internal var intentRequest: OverridePresetsIntentRequest

    init() {
        intentRequest = OverridePresetsIntentRequest()
    }

    @MainActor func perform() async throws -> some ProvidesDialog {
        do {
            await intentRequest.cancelOverride()
            return .result(
                dialog: IntentDialog(LocalizedStringResource("Override canceled", table: "ShortcutsDetail"))
            )
        }
    }
}
