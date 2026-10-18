import CloudKit
import Foundation

/// The few record operations the backup store needs. The CloudKit implementation lives in the iCloud build;
/// tests use an in-memory one, so the chunking logic runs without an iCloud account.
protocol CloudRecordStoring {
    /// With `overwrite` false, saving a record whose id already exists throws `CloudRecordError.conflict`.
    func save(_ records: [CKRecord], overwrite: Bool) async throws
    /// Records that do not exist are left out of the result.
    func fetch(_ ids: [CKRecord.ID]) async throws -> [CKRecord.ID: CKRecord]
    /// Records that do not exist are ignored.
    func delete(_ ids: [CKRecord.ID]) async throws
    func query(recordType: String, desiredKeys: [String]) async throws -> [(id: CKRecord.ID, record: Result<CKRecord, Error>)]
}

enum CloudRecordError: Error, Equatable {
    case conflict
}

/// The opt-in treatment history is too large for one record, so it travels in extra records of the same zone.
/// Each chunk names its backup, its position, the number of chunks and the checksum of the whole history.
/// Everything is stored in `encryptedValues`; no `CKAsset` is used because assets are not encrypted.
extension TrioCloudRecordCodec {
    static let chunkRecordType = "TrioSettingsBackupChunk"
    /// Well below the 1 MB record limit, which also covers field names and encryption overhead.
    static let maximumChunkSize = 500_000
    /// The most history one iCloud backup may carry.
    static let maximumHistorySize = 16 * 1024 * 1024
    /// Chunks per request, which keeps every CloudKit request small.
    static let chunkBatchSize = 4

    struct HistoryInfo: Equatable {
        let chunkCount: Int
        let byteCount: Int
    }

    static func chunkRecordID(parent: UUID, index: Int) -> CKRecord.ID {
        CKRecord.ID(recordName: "\(parent.uuidString)-h\(index)", zoneID: zoneID)
    }

    static func chunkCount(forByteCount bytes: Int) -> Int {
        (bytes + maximumChunkSize - 1) / maximumChunkSize
    }

    static var maximumChunkCount: Int { chunkCount(forByteCount: maximumHistorySize) }

    /// Separates the history from the snapshot, which is stored without it. Only manual backups may carry history.
    static func split(_ candidate: TrioSettingsBackup) throws -> (stored: TrioSettingsBackup, history: Data?) {
        guard let history = candidate.treatmentHistory else { return (candidate, nil) }
        guard candidate.origin == .manual else { throw BackupError.historyRequiresManualBackup }
        guard history.count <= maximumHistorySize else { throw BackupError.historyTooLargeForICloud }
        guard candidate.treatmentHistoryChecksum == TrioSettingsBackup.digest(history) else { throw BackupError.integrityCheckFailed }
        var stored = candidate
        stored.treatmentHistory = nil
        return (stored, history)
    }

    /// Puts downloaded history back and verifies it against the checksum stored with the snapshot.
    static func join(_ stored: TrioSettingsBackup, history: Data) throws -> TrioSettingsBackup {
        var result = stored
        result.treatmentHistory = history
        return try result.validated()
    }

    static func chunkRecords(parent: UUID, history: Data, checksum: String) throws -> [CKRecord] {
        guard !history.isEmpty, history.count <= maximumHistorySize else { throw BackupError.historyTooLargeForICloud }
        let count = chunkCount(forByteCount: history.count)
        return (0 ..< count).map { index in
            let start = index * maximumChunkSize
            let end = min(start + maximumChunkSize, history.count)
            let record = CKRecord(recordType: chunkRecordType, recordID: chunkRecordID(parent: parent, index: index))
            record.encryptedValues["parent"] = parent.uuidString as NSString
            record.encryptedValues["index"] = index as NSNumber
            record.encryptedValues["count"] = count as NSNumber
            record.encryptedValues["checksum"] = checksum as NSString
            record.encryptedValues["data"] = history.subdata(in: start ..< end) as NSData
            return record
        }
    }

    /// Reads the chunk layout the backup record announces, if it has history.
    static func historyInfo(from record: CKRecord) throws -> HistoryInfo? {
        let chunks = record.encryptedValues["historyChunkCount"] as? NSNumber
        let bytes = record.encryptedValues["historyByteCount"] as? NSNumber
        if chunks == nil, bytes == nil { return nil }
        guard let chunks = chunks?.intValue, let bytes = bytes?.intValue,
              bytes > 0, bytes <= maximumHistorySize, chunks == chunkCount(forByteCount: bytes)
        else { throw BackupError.invalidCloudRecord }
        return HistoryInfo(chunkCount: chunks, byteCount: bytes)
    }

    /// Joins the chunks in order. Every chunk must belong to this backup, sit at its position, agree on the
    /// count and checksum, and the result must match both the announced size and the checksum.
    static func assembleHistory(
        parent: UUID,
        info: HistoryInfo,
        checksum: String,
        records: [CKRecord.ID: CKRecord]
    ) throws -> Data {
        var history = Data()
        for index in 0 ..< info.chunkCount {
            guard let record = records[chunkRecordID(parent: parent, index: index)],
                  record.recordType == chunkRecordType,
                  record.encryptedValues["parent"] as? String == parent.uuidString,
                  (record.encryptedValues["index"] as? NSNumber)?.intValue == index,
                  (record.encryptedValues["count"] as? NSNumber)?.intValue == info.chunkCount,
                  record.encryptedValues["checksum"] as? String == checksum,
                  let part = record.encryptedValues["data"] as? Data,
                  part.count <= maximumChunkSize
            else { throw BackupError.invalidCloudRecord }
            history.append(part)
        }
        guard history.count == info.byteCount, TrioSettingsBackup.digest(history) == checksum else {
            throw BackupError.integrityCheckFailed
        }
        return history
    }
}

/// The backup store on top of a record-level store: a snapshot record per backup, plus chunk records for history.
final class TrioChunkedCloudStore: TrioCloudBackupStoring {
    private let records: CloudRecordStoring

    init(records: CloudRecordStoring) {
        self.records = records
    }

    private typealias Codec = TrioCloudRecordCodec

    func upload(_ candidate: TrioSettingsBackup) async throws -> BackupEntry {
        let (stored, history) = try Codec.split(candidate)
        let validated = try stored.validated()
        let recordID = Codec.recordID(for: candidate.id)
        var chunks: [CKRecord] = []
        var info: Codec.HistoryInfo?
        if let history, let checksum = stored.treatmentHistoryChecksum {
            chunks = try Codec.chunkRecords(parent: candidate.id, history: history, checksum: checksum)
            info = Codec.HistoryInfo(chunkCount: chunks.count, byteCount: history.count)
        }
        // A retry reuses the backup id: an existing record is only accepted when it is the same backup.
        if let existing = try await records.fetch([recordID])[recordID] {
            return try await finishExisting(existing, matching: validated, chunks: chunks)
        }
        let record = CKRecord(recordType: Codec.recordType, recordID: recordID)
        try Codec.fill(record, with: stored, history: info)
        // Chunks first, so a backup record never points to chunks that are missing.
        try await save(chunks)
        do {
            try await records.save([record], overwrite: false)
            return try Codec.entry(from: record)
        } catch CloudRecordError.conflict {
            guard let existing = try await records.fetch([recordID])[recordID] else { throw BackupError.invalidCloudRecord }
            return try await finishExisting(existing, matching: validated, chunks: chunks)
        }
    }

    private func finishExisting(_ existing: CKRecord, matching uploaded: TrioSettingsBackup, chunks: [CKRecord]) async throws -> BackupEntry {
        let saved = try Codec.snapshot(from: existing)
        guard try saved.matchesUploadedSnapshot(uploaded) else { throw BackupError.integrityCheckFailed }
        // The chunks are identical to the ones the earlier attempt wrote; writing them again repairs a partial upload.
        try await save(chunks)
        return try Codec.entry(from: existing)
    }

    func list() async throws -> [BackupEntry] {
        let keys = ["createdAt", "origin", "fingerprint", "name", "appVersion", "schemaVersion"]
        var entries: [BackupEntry] = []
        for (id, result) in try await records.query(recordType: Codec.recordType, desiredKeys: keys) {
            do {
                entries.append(try Codec.entry(from: result.get()))
            } catch {
                // Keep an unavailable/corrupt record visible instead of hiding history.
                entries.append(BackupEntry(
                    id: id.recordName,
                    createdAt: .distantPast,
                    origin: .automatic,
                    name: "Unavailable Backup",
                    fingerprint: "",
                    validationMessage: error.localizedDescription
                ))
            }
        }
        return entries.sorted { $0.createdAt > $1.createdAt }
    }

    func download(id: String) async throws -> TrioSettingsBackup {
        let recordID = CKRecord.ID(recordName: id, zoneID: Codec.zoneID)
        guard let record = try await records.fetch([recordID])[recordID] else { throw BackupError.invalidCloudRecord }
        let stored = try Codec.snapshot(from: record)
        guard let info = try Codec.historyInfo(from: record) else {
            // History announced by the snapshot but not by the record means chunks went missing.
            if stored.treatmentHistory == nil, stored.treatmentHistoryChecksum != nil { throw BackupError.invalidCloudRecord }
            return stored
        }
        guard let checksum = stored.treatmentHistoryChecksum, stored.treatmentHistory == nil else {
            throw BackupError.invalidCloudRecord
        }
        let ids = (0 ..< info.chunkCount).map { Codec.chunkRecordID(parent: stored.id, index: $0) }
        var found: [CKRecord.ID: CKRecord] = [:]
        for batch in Self.batches(ids) {
            let part = try await records.fetch(batch)
            found.merge(part) { current, _ in current }
        }
        let history = try Codec.assembleHistory(parent: stored.id, info: info, checksum: checksum, records: found)
        return try Codec.join(stored, history: history)
    }

    /// Removes the chunks first and the backup record last, so an interrupted delete can be repeated.
    func delete(id: String) async throws {
        guard let parent = UUID(uuidString: id) else {
            try await records.delete([CKRecord.ID(recordName: id, zoneID: Codec.zoneID)])
            return
        }
        let recordID = Codec.recordID(for: parent)
        if let record = try await records.fetch([recordID])[recordID] {
            var count = 0
            if let info = try? Codec.historyInfo(from: record) {
                count = info.chunkCount
            } else if record.encryptedValues["historyChunkCount"] != nil || record.encryptedValues["historyByteCount"] != nil {
                // A damaged layout: remove every id a chunk could have.
                count = Codec.maximumChunkCount
            }
            let ids = (0 ..< count).map { Codec.chunkRecordID(parent: parent, index: $0) }
            for batch in Self.batches(ids) { try await records.delete(batch) }
        }
        try await records.delete([recordID])
    }

    func rename(id: String, name: String) async throws -> BackupEntry {
        guard let name = TrioSettingsBackup.normalizedName(name) else { throw BackupError.backupNameRequired }
        let recordID = CKRecord.ID(recordName: id, zoneID: Codec.zoneID)
        guard let record = try await records.fetch([recordID])[recordID] else { throw BackupError.invalidCloudRecord }
        var snapshot = try Codec.snapshot(from: record)
        guard snapshot.origin == .manual else { throw BackupError.invalidCloudRecord }
        snapshot.name = name
        // The record's change tag prevents overwriting concurrent renames. The history fields stay as they are.
        try Codec.fill(record, with: snapshot)
        try await records.save([record], overwrite: false)
        return try Codec.entry(from: record)
    }

    private func save(_ chunks: [CKRecord]) async throws {
        for batch in Self.batches(chunks) { try await records.save(batch, overwrite: true) }
    }

    private static func batches<Element>(_ items: [Element]) -> [[Element]] {
        stride(from: 0, to: items.count, by: Codec.chunkBatchSize).map {
            Array(items[$0 ..< min($0 + Codec.chunkBatchSize, items.count)])
        }
    }
}
