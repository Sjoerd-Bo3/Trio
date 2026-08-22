import Foundation
import Testing

@testable import Trio

@Suite("Settings Backup Codable Tests") struct SettingsBackupCodableTests {
    @Test("Full backup survives an encode/decode round trip") func testRoundTrip() throws {
        let backup = SettingsBackupTestFixtures.fullBackup()

        let data = try JSONCoding.encoder.encode(backup)
        let decoded = try JSONCoding.decoder.decode(SettingsBackup.self, from: data)

        #expect(decoded == backup)
    }

    @Test("Partial backup decodes with missing sections as nil") func testPartialBackup() throws {
        let json = """
        {
            "schemaVersion": 1,
            "therapy": {
                "basalProfile": [
                    { "start": "00:00:00", "minutes": 0, "rate": 0.8 }
                ]
            }
        }
        """
        let decoded = try JSONCoding.decoder.decode(SettingsBackup.self, from: Data(json.utf8))

        #expect(decoded.schemaVersion == 1)
        #expect(decoded.therapy?.basalProfile?.count == 1)
        #expect(decoded.therapy?.basalProfile?.first?.rate == 0.8)
        #expect(decoded.trioSettings == nil)
        #expect(decoded.preferences == nil)
        #expect(decoded.presets == nil)
        #expect(decoded.credentials == nil)
        #expect(decoded.exportDate == nil)
    }

    @Test("Backup from a newer schema decodes, ignoring unknown keys") func testFutureSchema() throws {
        let json = """
        {
            "schemaVersion": 99,
            "someFutureSection": { "flag": true },
            "trioSettings": {
                "units": "mmol/L",
                "someFutureSetting": 42
            }
        }
        """
        let decoded = try JSONCoding.decoder.decode(SettingsBackup.self, from: Data(json.utf8))

        #expect(decoded.schemaVersion == 99)
        #expect(decoded.schemaVersion > SettingsBackup.currentSchemaVersion)
        #expect(decoded.trioSettings?.units == .mmolL)
    }

    @Test("File without schemaVersion is rejected") func testMissingSchemaVersion() {
        let json = """
        { "trioSettings": { "units": "mg/dL" } }
        """
        #expect(throws: (any Error).self) {
            _ = try JSONCoding.decoder.decode(SettingsBackup.self, from: Data(json.utf8))
        }
    }

    @Test("Garbage data is rejected") func testGarbage() {
        #expect(throws: (any Error).self) {
            _ = try JSONCoding.decoder.decode(SettingsBackup.self, from: Data("not json at all".utf8))
        }
    }

    @Test("Credentials are only encoded when present") func testCredentialsAbsentByDefault() throws {
        var backup = SettingsBackupTestFixtures.fullBackup()
        backup.credentials = nil
        backup.devices?.pumpState = nil
        backup.devices?.cgmState = nil

        let data = try JSONCoding.encoder.encode(backup)
        let json = String(decoding: data, as: UTF8.self)

        #expect(!json.contains("credentials"))
        #expect(!json.contains("supersecret"))
        #expect(!json.contains("pumpState"))
    }

    @Test("Manager state survives a base64 plist round trip") func testManagerStateRoundTrip() throws {
        let rawValue: [String: Any] = [
            "managerIdentifier": "Omnipod",
            "state": ["address": 123_456, "nested": ["a": true]]
        ]

        let encoded = try #require(SettingsBackup.encodeManagerState(rawValue))
        let decoded = try #require(SettingsBackup.decodeManagerState(encoded))

        #expect(decoded["managerIdentifier"] as? String == "Omnipod")
        let state = try #require(decoded["state"] as? [String: Any])
        #expect(state["address"] as? Int == 123_456)
        #expect((state["nested"] as? [String: Any])?["a"] as? Bool == true)
    }

    @Test("Invalid base64 manager state decodes to nil") func testInvalidManagerState() {
        #expect(SettingsBackup.decodeManagerState("not-base64-!!!") == nil)
        #expect(SettingsBackup.decodeManagerState(Data("plain text".utf8).base64EncodedString()) == nil)
    }
}
