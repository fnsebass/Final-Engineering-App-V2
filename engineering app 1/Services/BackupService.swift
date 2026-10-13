//
//  BackupService.swift
//  Tolerance
//
//  Manual backup/restore for the on-device SwiftData store (Settings →
//  Sync → Export Backup / Restore from Backup). Packages the store's raw
//  SQLite file plus its -wal/-shm sidecars (recent writes can still be
//  sitting in the WAL file, not yet checkpointed into the main file) into a
//  single file the system share sheet / file picker can handle with no
//  custom UTType registration.
//
//  The on-disk layout is a small length-prefixed binary framing rather than
//  JSON — encoding raw file Data through JSONEncoder's base64 path is slow
//  enough on larger stores to visibly stall the UI for upwards of a minute.
//  Restoring still accepts the older JSON format so backups made before
//  this format changed can still be used.
//
//  Restoring can't safely happen while the live store is already open by a
//  ModelContainer, so a restore is staged to disk and applied the next time
//  the app launches, before engineering_app_1App opens the store — see
//  applyPendingRestoreIfNeeded.
//

import Foundation

private let backupMagic: [UInt8] = Array("TOLBACKUP1".utf8)

enum BackupError: LocalizedError {
    case storeNotFound
    case invalidBackupFile

    var errorDescription: String? {
        switch self {
        case .storeNotFound:
            return "Could not find the notes database to back up."
        case .invalidBackupFile:
            return "This doesn't look like a valid backup file."
        }
    }
}

enum BackupService {
    private static let pendingRestoreFlagKey = "settings.sync.pendingRestore"
    private static let stagingFileName = "PendingRestore.tolbackup"

    /// The live SwiftData store's file URL, captured once in
    /// engineering_app_1App.makeContainer() — SwiftUI views have no other
    /// way to learn this, since SwiftData assigns it internally when no
    /// explicit `url:` is passed to ModelConfiguration.
    static var liveStoreURL: URL?

    // MARK: - Export

    /// Builds a single exportable file containing the full on-disk SwiftData
    /// store, ready to hand to a share sheet. Caller should `try?
    /// modelContext.save()` first so any pending in-memory changes are
    /// flushed to disk before the files are read. Does raw file I/O only —
    /// no JSON/base64 — so callers should still run it off the main thread
    /// for larger stores.
    static func exportBackup(storeURL: URL) throws -> URL {
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            throw BackupError.storeNotFound
        }
        let storeData = try Data(contentsOf: storeURL)
        let walData = try? Data(contentsOf: sidecarURL(for: storeURL, suffix: "-wal"))
        let shmData = try? Data(contentsOf: sidecarURL(for: storeURL, suffix: "-shm"))

        var output = Data()
        output.append(contentsOf: backupMagic)
        appendUInt32(1, to: &output)
        appendChunk(storeData, to: &output)
        appendChunk(walData ?? Data(), to: &output)
        appendChunk(shmData ?? Data(), to: &output)

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HHmm"
        let fileName = "Notes Backup \(dateFormatter.string(from: .now)).tolbackup"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        try output.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Restore

    /// Validates `pickedURL` as a backup file and stages it to replace the
    /// live store the next time the app launches.
    static func stageRestore(from pickedURL: URL) throws {
        let needsSecurityScope = pickedURL.startAccessingSecurityScopedResource()
        defer { if needsSecurityScope { pickedURL.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: pickedURL)
        guard decodeBackup(data) != nil else {
            throw BackupError.invalidBackupFile
        }

        let staging = stagingFileURL()
        try? FileManager.default.removeItem(at: staging)
        try data.write(to: staging, options: .atomic)
        UserDefaults.standard.set(true, forKey: pendingRestoreFlagKey)
    }

    static var isRestorePending: Bool {
        UserDefaults.standard.bool(forKey: pendingRestoreFlagKey)
    }

    /// Called once at launch, before the ModelContainer opens the store —
    /// replaces the on-disk store files with whatever was staged by
    /// `stageRestore`, if anything was.
    static func applyPendingRestoreIfNeeded(storeURL: URL) {
        guard UserDefaults.standard.bool(forKey: pendingRestoreFlagKey) else { return }
        let staging = stagingFileURL()
        defer {
            UserDefaults.standard.set(false, forKey: pendingRestoreFlagKey)
            try? FileManager.default.removeItem(at: staging)
        }

        guard let data = try? Data(contentsOf: staging),
              let payload = decodeBackup(data) else { return }

        let walURL = sidecarURL(for: storeURL, suffix: "-wal")
        let shmURL = sidecarURL(for: storeURL, suffix: "-shm")
        for url in [storeURL, walURL, shmURL] {
            try? FileManager.default.removeItem(at: url)
        }
        try? payload.storeData.write(to: storeURL, options: .atomic)
        if !payload.walData.isEmpty { try? payload.walData.write(to: walURL, options: .atomic) }
        if !payload.shmData.isEmpty { try? payload.shmData.write(to: shmURL, options: .atomic) }
    }

    // MARK: - Binary framing

    private struct DecodedBackup {
        let storeData: Data
        let walData: Data
        let shmData: Data
    }

    /// Legacy format used before the binary framing above — kept so backups
    /// made by earlier versions of the app can still be restored.
    private struct LegacyBackupPayload: Codable {
        let exportDate: Date
        let formatVersion: Int
        let storeData: Data
        let walData: Data?
        let shmData: Data?
    }

    private static func decodeBackup(_ data: Data) -> DecodedBackup? {
        if data.starts(with: backupMagic) {
            var offset = backupMagic.count
            guard readUInt32(data, at: &offset) != nil else { return nil }
            guard let storeData = readChunk(data, at: &offset) else { return nil }
            guard let walData = readChunk(data, at: &offset) else { return nil }
            guard let shmData = readChunk(data, at: &offset) else { return nil }
            return DecodedBackup(storeData: storeData, walData: walData, shmData: shmData)
        }
        if let payload = try? JSONDecoder().decode(LegacyBackupPayload.self, from: data) {
            return DecodedBackup(storeData: payload.storeData,
                                  walData: payload.walData ?? Data(),
                                  shmData: payload.shmData ?? Data())
        }
        return nil
    }

    private static func appendUInt32(_ value: UInt32, to data: inout Data) {
        for i in 0..<4 {
            data.append(UInt8((value >> (8 * i)) & 0xFF))
        }
    }

    private static func appendChunk(_ chunk: Data, to data: inout Data) {
        let length = UInt64(chunk.count)
        for i in 0..<8 {
            data.append(UInt8((length >> (8 * i)) & 0xFF))
        }
        data.append(chunk)
    }

    private static func readUInt32(_ data: Data, at offset: inout Int) -> UInt32? {
        guard offset + 4 <= data.count else { return nil }
        var value: UInt32 = 0
        for i in 0..<4 {
            value |= UInt32(data[data.startIndex + offset + i]) << (8 * i)
        }
        offset += 4
        return value
    }

    private static func readChunk(_ data: Data, at offset: inout Int) -> Data? {
        guard offset + 8 <= data.count else { return nil }
        var length: UInt64 = 0
        for i in 0..<8 {
            length |= UInt64(data[data.startIndex + offset + i]) << (8 * i)
        }
        offset += 8
        let len = Int(length)
        guard len >= 0, offset + len <= data.count else { return nil }
        let start = data.startIndex + offset
        let chunk = data.subdata(in: start..<(start + len))
        offset += len
        return chunk
    }

    // MARK: - Helpers

    /// SQLite's sidecar naming convention is the full store path with the
    /// suffix appended directly — e.g. "default.store" → "default.store-wal".
    private static func sidecarURL(for storeURL: URL, suffix: String) -> URL {
        URL(fileURLWithPath: storeURL.path + suffix)
    }

    private static func stagingFileURL() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return dir.appendingPathComponent(stagingFileName)
    }
}
