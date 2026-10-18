import CloudKit
import Foundation
import Testing
@testable import Trio

/// Record store that keeps everything in memory, so the chunking runs without an iCloud account.
final class InMemoryCloudRecords: CloudRecordStoring {
    var stored: [CKRecord.ID: CKRecord] = [:]
    var failParentSave = false

    func save(_ records: [CKRecord], overwrite: Bool) async throws {
        if failParentSave, records.contains(where: { $0.recordType == TrioCloudRecordCodec.recordType }) {
            throw BackupError.iCloudUnavailable
        }
        if !overwrite, records.contains(where: { stored[$0.recordID] != nil }) { throw CloudRecordError.conflict }
        for record in records { stored[record.recordID] = record }
    }

    func fetch(_ ids: [CKRecord.ID]) async throws -> [CKRecord.ID: CKRecord] {
        ids.reduce(into: [:]) { result, id in result[id] = stored[id] }
    }

    func delete(_ ids: [CKRecord.ID]) async throws {
        for id in ids { stored[id] = nil }
    }

    func query(recordType: String, desiredKeys _: [String]) async throws -> [(id: CKRecord.ID, record: Result<CKRecord, Error>)] {
        stored.values.filter { $0.recordType == recordType }
            .map { (id: $0.recordID, record: Result<CKRecord, Error>.success($0)) }
    }

    var chunks: [CKRecord] {
        stored.values.filter { $0.recordType == TrioCloudRecordCodec.chunkRecordType }
            .sorted { $0.recordID.recordName < $1.recordID.recordName }
    }

    var parents: [CKRecord] { stored.values.filter { $0.recordType == TrioCloudRecordCodec.recordType } }
}

extension BackupSnapshotTests {
    func historyBytes(_ count: Int, seed: Int = 0) -> Data {
        // Large inputs only need the right size, so they skip the slow per-byte pattern.
        if count > 5_000_000 { return Data(repeating: UInt8(truncatingIfNeeded: seed &+ 1), count: count) }
        return Data((0 ..< count).map { UInt8(truncatingIfNeeded: ($0 &* 31) &+ seed) })
    }

    func backup(withHistory history: Data?, origin: TrioSettingsBackup.Origin = .manual) throws -> TrioSettingsBackup {
        var snapshot = try makeBackup(validConfiguration(), origin: origin)
        if let history {
            snapshot.treatmentHistory = history
            snapshot.treatmentHistoryChecksum = TrioSettingsBackup.digest(history)
        }
        return snapshot
    }

    @Test("History is split into linked chunks and reassembled and verified on download") func historyChunkRoundTrip() async throws {
        let records = InMemoryCloudRecords()
        let store = TrioChunkedCloudStore(records: records)
        let history = historyBytes(2 * TrioCloudRecordCodec.maximumChunkSize + 1234)
        let snapshot = try backup(withHistory: history)
        _ = try await store.upload(snapshot)

        #expect(records.parents.count == 1)
        #expect(records.chunks.count == 3)
        for (index, chunk) in records.chunks.enumerated() {
            #expect(chunk.encryptedValues["parent"] as? String == snapshot.id.uuidString)
            #expect((chunk.encryptedValues["index"] as? NSNumber)?.intValue == index)
            #expect((chunk.encryptedValues["count"] as? NSNumber)?.intValue == 3)
            #expect(chunk.encryptedValues["checksum"] as? String == snapshot.treatmentHistoryChecksum)
            // Nothing is stored in the clear or as an asset.
            #expect(!chunk.allKeys().contains { chunk[$0] is CKAsset })
            #expect(((chunk.encryptedValues["data"] as? Data)?.count ?? .max) <= TrioCloudRecordCodec.maximumChunkSize)
        }
        let parent = try #require(records.parents.first)
        #expect(!parent.allKeys().contains { parent[$0] is CKAsset })
        let storedSnapshot = try #require(parent.encryptedValues["snapshot"] as? Data)
        #expect(storedSnapshot.count < 100_000)

        let downloaded = try await store.download(id: snapshot.id.uuidString)
        #expect(downloaded.treatmentHistory == history)
        #expect(downloaded.treatmentHistoryChecksum == snapshot.treatmentHistoryChecksum)
        #expect(downloaded.fingerprint == snapshot.fingerprint)
    }

    @Test("A backup without history stores no chunks") func noHistoryNoChunks() async throws {
        let records = InMemoryCloudRecords()
        let store = TrioChunkedCloudStore(records: records)
        let snapshot = try backup(withHistory: nil)
        _ = try await store.upload(snapshot)
        #expect(records.chunks.isEmpty)
        let downloaded = try await store.download(id: snapshot.id.uuidString)
        #expect(downloaded.treatmentHistory == nil)
    }

    @Test("A chunk with changed content is rejected on download") func tamperedChunk() async throws {
        let records = InMemoryCloudRecords()
        let store = TrioChunkedCloudStore(records: records)
        let snapshot = try backup(withHistory: historyBytes(TrioCloudRecordCodec.maximumChunkSize + 10))
        _ = try await store.upload(snapshot)
        let chunk = try #require(records.chunks.last)
        var data = try #require(chunk.encryptedValues["data"] as? Data)
        data[0] = data[0] &+ 1
        chunk.encryptedValues["data"] = data as NSData
        await #expect(throws: BackupError.integrityCheckFailed) { _ = try await store.download(id: snapshot.id.uuidString) }
    }

    @Test("A missing chunk is rejected on download") func missingChunk() async throws {
        let records = InMemoryCloudRecords()
        let store = TrioChunkedCloudStore(records: records)
        let snapshot = try backup(withHistory: historyBytes(TrioCloudRecordCodec.maximumChunkSize + 10))
        _ = try await store.upload(snapshot)
        records.stored[TrioCloudRecordCodec.chunkRecordID(parent: snapshot.id, index: 1)] = nil
        await #expect(throws: BackupError.invalidCloudRecord) { _ = try await store.download(id: snapshot.id.uuidString) }
    }

    @Test("A chunk that names another backup, position or count is rejected") func mislinkedChunks() async throws {
        for field in ["parent", "index", "count", "checksum"] {
            let records = InMemoryCloudRecords()
            let store = TrioChunkedCloudStore(records: records)
            let snapshot = try backup(withHistory: historyBytes(TrioCloudRecordCodec.maximumChunkSize + 10))
            _ = try await store.upload(snapshot)
            let chunk = try #require(records.chunks.first)
            switch field {
            case "parent": chunk.encryptedValues["parent"] = UUID().uuidString as NSString
            case "index": chunk.encryptedValues["index"] = 1 as NSNumber
            case "count": chunk.encryptedValues["count"] = 5 as NSNumber
            default: chunk.encryptedValues["checksum"] = "0000" as NSString
            }
            await #expect(throws: BackupError.invalidCloudRecord) { _ = try await store.download(id: snapshot.id.uuidString) }
        }
    }

    @Test("History that does not fit the iCloud limit is refused before anything is stored") func historyCap() async throws {
        let records = InMemoryCloudRecords()
        let store = TrioChunkedCloudStore(records: records)
        let snapshot = try backup(withHistory: historyBytes(TrioCloudRecordCodec.maximumHistorySize + 1))
        await #expect(throws: BackupError.historyTooLargeForICloud) { _ = try await store.upload(snapshot) }
        #expect(records.stored.isEmpty)
        let limit = try backup(withHistory: historyBytes(TrioCloudRecordCodec.maximumHistorySize))
        _ = try await store.upload(limit)
        #expect(records.chunks.count == TrioCloudRecordCodec.maximumChunkCount)
    }

    @Test("An automatic backup never carries history") func automaticRefusesHistory() async throws {
        let records = InMemoryCloudRecords()
        let store = TrioChunkedCloudStore(records: records)
        let snapshot = try backup(withHistory: historyBytes(1000), origin: .automatic)
        await #expect(throws: BackupError.historyRequiresManualBackup) { _ = try await store.upload(snapshot) }
        #expect(records.stored.isEmpty)
    }

    @Test("Deleting a backup deletes its chunks") func deleteWithChunks() async throws {
        let records = InMemoryCloudRecords()
        let store = TrioChunkedCloudStore(records: records)
        let kept = try backup(withHistory: historyBytes(TrioCloudRecordCodec.maximumChunkSize + 10, seed: 1))
        let removed = try backup(withHistory: historyBytes(3 * TrioCloudRecordCodec.maximumChunkSize, seed: 2))
        _ = try await store.upload(kept)
        _ = try await store.upload(removed)
        #expect(records.chunks.count == 2 + 3)
        try await store.delete(id: removed.id.uuidString)
        #expect(records.chunks.count == 2)
        #expect(records.parents.count == 1)
        #expect(records.chunks.allSatisfy { $0.encryptedValues["parent"] as? String == kept.id.uuidString })
        try await store.delete(id: removed.id.uuidString)
    }

    @Test("A retry after an interrupted upload completes the same backup") func retryAfterInterruptedUpload() async throws {
        let records = InMemoryCloudRecords()
        let store = TrioChunkedCloudStore(records: records)
        let history = historyBytes(TrioCloudRecordCodec.maximumChunkSize + 10)
        let snapshot = try backup(withHistory: history)
        records.failParentSave = true
        await #expect(throws: BackupError.iCloudUnavailable) { _ = try await store.upload(snapshot) }
        #expect(records.parents.isEmpty)
        #expect(records.chunks.count == 2)
        records.failParentSave = false
        _ = try await store.upload(snapshot)
        _ = try await store.upload(snapshot)
        #expect(records.parents.count == 1)
        #expect(records.chunks.count == 2)
        #expect(try await store.download(id: snapshot.id.uuidString).treatmentHistory == history)
    }

    @Test("Renaming a backup keeps its history") func renameKeepsHistory() async throws {
        let records = InMemoryCloudRecords()
        let store = TrioChunkedCloudStore(records: records)
        let history = historyBytes(TrioCloudRecordCodec.maximumChunkSize + 10)
        let snapshot = try backup(withHistory: history)
        _ = try await store.upload(snapshot)
        let entry = try await store.rename(id: snapshot.id.uuidString, name: "Renamed")
        #expect(entry.name == "Renamed")
        let downloaded = try await store.download(id: snapshot.id.uuidString)
        #expect(downloaded.name == "Renamed")
        #expect(downloaded.treatmentHistory == history)
        #expect(try await store.list().count == 1)
    }

    @MainActor
    @Test("Only a manual backup with history opted in uploads history, and retention removes its chunks") func coordinatorHistory(
    ) async throws {
        let records = InMemoryCloudRecords()
        let history = historyBytes(TrioCloudRecordCodec.maximumChunkSize + 10)
        let coordinator = TrioCloudBackupCoordinator(
            cloud: TrioChunkedCloudStore(records: records),
            defaults: isolatedDefaults(),
            queueURL: try directory().appendingPathComponent("queue.json"),
            onboardingInProgress: { false },
            capture: { origin, name in
                var snapshot = try makeBackup(validConfiguration(), origin: origin, name: name)
                snapshot.treatmentHistory = history
                snapshot.treatmentHistoryChecksum = TrioSettingsBackup.digest(history)
                return snapshot
            }
        )

        // The daily backup leaves history out even if the capture produced it.
        await coordinator.runAutomaticBackup()
        #expect(records.parents.count == 1)
        #expect(records.chunks.isEmpty)

        let oldest = try await coordinator.createManualBackup(name: "Oldest history", includeHistory: true)
        #expect(records.chunks.count == 2)
        #expect(try await coordinator.downloadBackup(id: oldest.id).treatmentHistory == history)

        // A manual backup without the opt-in has none, even though the capture produced history.
        let plain = try await coordinator.createManualBackup(name: "Plain")
        #expect(records.chunks.count == 2)
        #expect(try await coordinator.downloadBackup(id: plain.id).treatmentHistory == nil)

        // Keeping three manual backups removes the oldest one together with its chunks.
        try await coordinator.setRetentionLimit(3, for: .manual)
        _ = try await coordinator.createManualBackup(name: "Second history", includeHistory: true)
        _ = try await coordinator.createManualBackup(name: "Third history", includeHistory: true)
        let manual = try await coordinator.listBackups().filter { $0.origin == .manual }
        #expect(manual.count == 3)
        #expect(!manual.contains { $0.id == oldest.id })
        #expect(records.chunks.count == 4)
        for entry in manual where entry.name?.hasSuffix("history") == true {
            #expect(try await coordinator.downloadBackup(id: entry.id).treatmentHistory == history)
        }
        coordinator.automaticEnabled = false
    }

    @MainActor
    @Test("History above the iCloud limit is refused with a clear message and leaves nothing queued") func coordinatorCap() async throws {
        let records = InMemoryCloudRecords()
        let coordinator = TrioCloudBackupCoordinator(
            cloud: TrioChunkedCloudStore(records: records),
            defaults: isolatedDefaults(),
            queueURL: try directory().appendingPathComponent("queue.json"),
            onboardingInProgress: { false },
            capture: { origin, name in
                var snapshot = try makeBackup(validConfiguration(), origin: origin, name: name)
                let history = historyBytes(TrioCloudRecordCodec.maximumHistorySize + 1)
                snapshot.treatmentHistory = history
                snapshot.treatmentHistoryChecksum = TrioSettingsBackup.digest(history)
                return snapshot
            }
        )
        await #expect(throws: BackupError.historyTooLargeForICloud) {
            _ = try await coordinator.createManualBackup(name: "Too large", includeHistory: true)
        }
        #expect(try coordinator.loadQueue().isEmpty)
        #expect(records.stored.isEmpty)
        #expect(BackupError.historyTooLargeForICloud.errorDescription?.isEmpty == false)
        coordinator.automaticEnabled = false
    }
}
