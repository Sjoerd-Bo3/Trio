import Foundation
import Testing
@testable import Trio

@Suite("Onboarding Backup Restore") struct OnboardingBackupRestoreTests {
    @MainActor @Test("Next stays blocked until a choice is made and a chosen restore has been applied") func nextBlocking() {
        let state = Onboarding.StateModel()
        #expect(state.restoreBlocksNext)

        state.chooseBackupRestoreOption(.startFresh)
        #expect(!state.restoreBlocksNext)

        state.chooseBackupRestoreOption(.restore)
        #expect(state.restoreBlocksNext)

        state.backupRestoreInProgress = true
        state.appliedBackupID = UUID()
        #expect(state.restoreBlocksNext)
        state.backupRestoreInProgress = false
        #expect(!state.restoreBlocksNext)
    }

    @MainActor @Test("An applied restore cannot be undone by choosing another option") func appliedRestoreIsLocked() {
        let state = Onboarding.StateModel()
        state.chooseBackupRestoreOption(.restore)
        state.appliedBackupID = UUID()
        state.chooseBackupRestoreOption(.startFresh)
        #expect(state.backupRestoreOption == .restore)
        #expect(state.backupWasRestored)
    }

    @MainActor @Test("Starting fresh drops a chosen but unapplied backup") func startFreshClearsPending() {
        let state = Onboarding.StateModel()
        state.chooseBackupRestoreOption(.restore)
        state.pendingBackupWarnings = ["Ignored section"]
        state.chooseBackupRestoreOption(.startFresh)
        #expect(state.pendingBackup == nil)
        #expect(state.pendingBackupWarnings.isEmpty)
        #expect(state.pendingBackupOverview == nil)
    }
}
