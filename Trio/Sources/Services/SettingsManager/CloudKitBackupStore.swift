import CloudKit
import Foundation

/// Whether iCloud backups can be used on this build and this phone.
enum CloudBackupAvailability {
    enum Status: Equatable {
        /// This build was made without the iCloud capability (`ENABLE_ICLOUD_BACKUP = NO`).
        case notBuilt
        case noAccount
        case available
    }

    /// True when the app was built with the CloudKit entitlement. Everything cloud related stays hidden otherwise.
    static var isBuiltWithCloudKit: Bool {
        #if TRIO_ICLOUD_BACKUP
            true
        #else
            false
        #endif
    }

    static func status() async -> Status {
        #if TRIO_ICLOUD_BACKUP
            let status = try? await CKContainer.default().accountStatus()
            return status == .available ? .available : .noAccount
        #else
            return .notBuilt
        #endif
    }
}

/// Private CloudKit storage with encrypted payload, fingerprint, and name fields.
protocol TrioCloudBackupStoring {
    /// False for builds without the iCloud capability; nothing is queued or uploaded then.
    var isAvailable: Bool { get }
    func upload(_ snapshot: TrioSettingsBackup) async throws -> BackupEntry
    func list() async throws -> [BackupEntry]
    func download(id: String) async throws -> TrioSettingsBackup
    func delete(id: String) async throws
    func rename(id: String, name: String) async throws -> BackupEntry
}

extension TrioCloudBackupStoring {
    var isAvailable: Bool { true }
}

/// Stands in for the real store in builds without the iCloud capability.
struct UnavailableCloudStore: TrioCloudBackupStoring {
    var isAvailable: Bool { false }
    func upload(_: TrioSettingsBackup) async throws -> BackupEntry { throw BackupError.iCloudUnavailable }
    func list() async throws -> [BackupEntry] { throw BackupError.iCloudUnavailable }
    func download(id _: String) async throws -> TrioSettingsBackup { throw BackupError.iCloudUnavailable }
    func delete(id _: String) async throws { throw BackupError.iCloudUnavailable }
    func rename(id _: String, name _: String) async throws -> BackupEntry { throw BackupError.iCloudUnavailable }
}

/// Record encoding shared by every build, so it can be tested without an iCloud account.
enum TrioCloudRecordCodec {
    static let recordType = "TrioSettingsBackup"
    static let zoneName = "TrioBackups"
    static let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
    /// A CloudKit record is limited to 1 MB in total.
    static let maximumPayloadSize = 750_000

    static func recordID(for id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
    }

    /// Every payload field lives in `encryptedValues`; only the fields the list needs for ordering and
    /// display are stored in the clear. Backups are never stored as assets, which CloudKit does not encrypt.
    /// A snapshot is stored without its treatment history. When it has some, the record announces how many
    /// chunk records hold it; a record that is filled again without `history` keeps what it announced.
    static func fill(_ record: CKRecord, with candidate: TrioSettingsBackup, history: HistoryInfo? = nil) throws {
        let snapshot = try candidate.validated()
        guard snapshot.treatmentHistory == nil else { throw BackupError.invalidCloudRecord }
        if let history {
            record.encryptedValues["historyChunkCount"] = history.chunkCount as NSNumber
            record.encryptedValues["historyByteCount"] = history.byteCount as NSNumber
        }
        let bytes = try JSONEncoder().encode(snapshot)
        guard bytes.count <= TrioSettingsBackup.maximumSize, bytes.count <= maximumPayloadSize else {
            throw BackupError.backupTooLarge
        }
        record["createdAt"] = snapshot.createdAt as NSDate
        record["origin"] = snapshot.origin.rawValue as NSString
        record["appVersion"] = snapshot.appVersion as NSString
        record["schemaVersion"] = snapshot.schemaVersion as NSNumber
        record.encryptedValues["fingerprint"] = snapshot.fingerprint as NSString
        record.encryptedValues["name"] = snapshot.name as NSString?
        record.encryptedValues["snapshot"] = bytes as NSData
    }

    static func snapshot(from record: CKRecord) throws -> TrioSettingsBackup {
        guard let fingerprint = record.encryptedValues["fingerprint"] as? String,
              let bytes = record.encryptedValues["snapshot"] as? Data
        else { throw BackupError.invalidCloudRecord }
        guard bytes.count <= TrioSettingsBackup.maximumSize else { throw BackupError.backupTooLarge }
        let snapshot = try TrioSettingsBackup.decode(bytes, expectedFingerprint: fingerprint)
        guard snapshot.id.uuidString == record.recordID.recordName else { throw BackupError.invalidCloudRecord }
        return snapshot
    }

    static func entry(from record: CKRecord) throws -> BackupEntry {
        guard let date = record["createdAt"] as? Date,
              let originName = record["origin"] as? String,
              let origin = TrioSettingsBackup.Origin(rawValue: originName),
              let fingerprint = record.encryptedValues["fingerprint"] as? String
        else { throw BackupError.invalidCloudRecord }
        return BackupEntry(
            id: record.recordID.recordName,
            createdAt: date,
            origin: origin,
            name: record.encryptedValues["name"] as? String,
            fingerprint: fingerprint,
            appVersion: record["appVersion"] as? String,
            schemaVersion: (record["schemaVersion"] as? NSNumber)?.intValue
        )
    }
}

#if TRIO_ICLOUD_BACKUP
    /// Record operations on the private database. Requests stay small: callers pass a few records at a time.
    struct CloudKitRecordStore: CloudRecordStoring {
        let database: CKDatabase

        func save(_ records: [CKRecord], overwrite: Bool) async throws {
            guard !records.isEmpty else { return }
            let result = try await database.modifyRecords(
                saving: records,
                deleting: [],
                savePolicy: overwrite ? .allKeys : .ifServerRecordUnchanged,
                atomically: true
            )
            for (_, saved) in result.saveResults {
                do { _ = try saved.get() } catch let error as CKError where error.code == .serverRecordChanged {
                    throw CloudRecordError.conflict
                }
            }
        }

        func fetch(_ ids: [CKRecord.ID]) async throws -> [CKRecord.ID: CKRecord] {
            guard !ids.isEmpty else { return [:] }
            var found: [CKRecord.ID: CKRecord] = [:]
            for (id, result) in try await database.records(for: ids) {
                do { found[id] = try result.get() } catch let error as CKError where error.code == .unknownItem { continue }
            }
            return found
        }

        func delete(_ ids: [CKRecord.ID]) async throws {
            guard !ids.isEmpty else { return }
            let result = try await database.modifyRecords(saving: [], deleting: ids, atomically: false)
            for (_, deleted) in result.deleteResults {
                // Already deleted by another device.
                do { try deleted.get() } catch let error as CKError where error.code == .unknownItem { continue }
            }
        }

        func query(recordType: String, desiredKeys: [String]) async throws -> [(id: CKRecord.ID, record: Result<CKRecord, Error>)] {
            let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
            var page = try await database.records(matching: query, inZoneWith: TrioCloudRecordCodec.zoneID, desiredKeys: desiredKeys)
            var rows: [(id: CKRecord.ID, record: Result<CKRecord, Error>)] = []
            while true {
                rows.append(contentsOf: page.matchResults.map { (id: $0.0, record: $0.1) })
                guard let cursor = page.queryCursor else { break }
                page = try await database.records(continuingMatchFrom: cursor, desiredKeys: desiredKeys)
            }
            return rows
        }
    }

    /// Private-database storage in a dedicated record zone. History travels in chunk records of the same zone.
    final class TrioCloudBackupStore: TrioCloudBackupStoring {
        private let container: CKContainer
        private let store: TrioChunkedCloudStore
        private var zoneReady = false

        init(container: CKContainer = .default()) {
            self.container = container
            store = TrioChunkedCloudStore(records: CloudKitRecordStore(database: container.privateCloudDatabase))
        }

        func checkAvailability() async throws {
            let status = try await container.accountStatus()
            guard status == .available else { throw BackupError.iCloudUnavailable }
            if !zoneReady {
                _ = try await container.privateCloudDatabase.save(CKRecordZone(zoneID: TrioCloudRecordCodec.zoneID))
                zoneReady = true
            }
        }

        func upload(_ snapshot: TrioSettingsBackup) async throws -> BackupEntry {
            // Refuse before touching iCloud when the history cannot be stored.
            _ = try TrioCloudRecordCodec.split(snapshot)
            try await checkAvailability()
            return try await store.upload(snapshot)
        }

        func rename(id: String, name: String) async throws -> BackupEntry {
            try await checkAvailability()
            return try await store.rename(id: id, name: name)
        }

        func list() async throws -> [BackupEntry] {
            try await checkAvailability()
            return try await store.list()
        }

        func download(id: String) async throws -> TrioSettingsBackup {
            try await checkAvailability()
            return try await store.download(id: id)
        }

        func delete(id: String) async throws {
            try await checkAvailability()
            try await store.delete(id: id)
        }
    }
#endif
