import Foundation
import Testing
@testable import Trio

@Suite("OpenAPS Settings File Loading") struct OpenAPSSettingsFileTests {
    @Test("A file that does not exist yet falls back to the bundled defaults") func missingFileUsesDefaults() throws {
        let result = try OpenAPS.loadRawOrDefaults(
            name: OpenAPS.Settings.basalProfile,
            retrieveRaw: { _ in nil },
            fileExists: { _ in false }
        )
        #expect(result == OpenAPS.defaults(for: OpenAPS.Settings.basalProfile))
    }

    @Test("A file that exists but cannot be read stops the cycle instead of using defaults") func unreadableFileThrows() {
        #expect(throws: OpenAPSError.settingsFileUnreadable(OpenAPS.Settings.basalProfile)) {
            _ = try OpenAPS.loadRawOrDefaults(
                name: OpenAPS.Settings.basalProfile,
                retrieveRaw: { _ in nil },
                fileExists: { _ in true }
            )
        }
    }

    @Test("A readable file is returned as saved") func readableFileIsReturned() throws {
        let result = try OpenAPS.loadRawOrDefaults(
            name: OpenAPS.Settings.basalProfile,
            retrieveRaw: { _ in "[{\"rate\":1}]" },
            fileExists: { _ in true }
        )
        #expect(result == "[{\"rate\":1}]")
    }

    @Test("A damaged file on disk is reported, a missing one is not") func realFiles() throws {
        let name = "openaps-settings-file-test-\(UUID().uuidString).json"
        let url = try #require(FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first)
            .appendingPathComponent(name)
        defer { try? FileManager.default.removeItem(at: url) }
        let storage = BaseFileStorage()
        let missing = try OpenAPS.loadRawOrDefaults(name: name, retrieveRaw: storage.retrieveRaw)
        #expect(missing == OpenAPS.defaults(for: name))
        // Bytes that are not valid UTF-8 cannot be read back as JSON text.
        try Data([0xFF, 0xFE, 0xFD]).write(to: url)
        #expect(throws: OpenAPSError.settingsFileUnreadable(name)) {
            _ = try OpenAPS.loadRawOrDefaults(name: name, retrieveRaw: storage.retrieveRaw)
        }
    }
}
