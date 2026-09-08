import Foundation

actor ProductivitySyncTransport {
    private let encoder: JSONEncoder = {
        let value = JSONEncoder()
        value.outputFormatting = [.prettyPrinted, .sortedKeys]
        return value
    }()

    func exchange(folder: URL, revisions: [ProductivitySyncRevision]?, backup: ProductivityBackup?) throws -> [ProductivitySyncRevision] {
        let root = folder.appendingPathComponent("Tidy Today", isDirectory: true)
        let accessed = folder.startAccessingSecurityScopedResource()
        defer { if accessed { folder.stopAccessingSecurityScopedResource() } }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ProductivityError.invalid("The selected sync folder is unavailable. Reconnect Drive or choose the folder again.")
        }
        if let backup { try writeBackup(backup, directory: root.appendingPathComponent("Backups")) }
        guard let revisions else { return [] }
        let changes = root.appendingPathComponent("Changes", isDirectory: true)
        try FileManager.default.createDirectory(at: changes, withIntermediateDirectories: true)
        for revision in revisions {
            try Task.checkCancellation()
            let url = changes.appendingPathComponent(revision.id.uuidString + ".json")
            if FileManager.default.fileExists(atPath: url.path) {
                let existing = try JSONDecoder().decode(ProductivitySyncRevision.self, from: read(url))
                guard existing == revision else { throw ProductivityError.invalid("A sync file changed unexpectedly. Both versions remain saved; sync has paused.") }
            } else {
                try writeImmutable(encoder.encode(revision), to: url)
            }
        }
        let files = try FileManager.default.contentsOfDirectory(at: changes, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles])
            .filter { $0.pathExtension == "json" }
        guard files.count <= 50_000 else { throw ProductivityError.invalid("This sync history is too large for this version of Tidy. Your local workspace is unchanged.") }
        var totalBytes = 0
        return try files.map { url in
            try Task.checkCancellation()
            let data = try read(url)
            totalBytes += data.count
            guard totalBytes <= 128_000_000 else { throw ProductivityError.invalid("This sync history exceeds 128 MB. Your local workspace is unchanged.") }
            return try JSONDecoder().decode(ProductivitySyncRevision.self, from: data)
        }
    }

    func writeBackup(_ backup: ProductivityBackup, directory: URL) throws {
        try backup.validate()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = Int(backup.createdAt.timeIntervalSince1970)
        try writeImmutable(encoder.encode(backup), to: directory.appendingPathComponent("\(stamp)-\(backup.id).json"))
    }

    func backups(folder: URL) throws -> [ProductivityBackupFile] {
        let accessed = folder.startAccessingSecurityScopedResource()
        defer { if accessed { folder.stopAccessingSecurityScopedResource() } }
        let directory = folder.appendingPathComponent("Tidy Today/Backups")
        if !FileManager.default.fileExists(atPath: directory.path) { return [] }
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent > $1.lastPathComponent }.prefix(30)
        return try urls.map { url in
            let backup = try JSONDecoder().decode(ProductivityBackup.self, from: read(url))
            try backup.validate()
            return ProductivityBackupFile(url: url, backup: backup)
        }
    }

    func backupFile(at url: URL) throws -> ProductivityBackupFile {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let backup = try JSONDecoder().decode(ProductivityBackup.self, from: read(url))
        try backup.validate()
        return ProductivityBackupFile(url: url, backup: backup)
    }

    private func writeImmutable(_ data: Data, to url: URL) throws {
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(UUID()).pending")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try data.write(to: temporary, options: .atomic)
        do { try FileManager.default.moveItem(at: temporary, to: url) }
        catch {
            guard (try? Data(contentsOf: url)) == data else { throw error }
        }
    }

    private func read(_ url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? Int.max) <= 20_000_000 else {
            throw ProductivityError.invalid("A sync file is not a regular file or exceeds 20 MB. No local content was replaced.")
        }
        return try Data(contentsOf: url)
    }
}
