import Foundation

@MainActor
final class ProductivityStore {
    let fileURL: URL?
    private var memory = ProductivitySnapshot()

    init(fileURL: URL?) { self.fileURL = fileURL }

    static func local() -> ProductivityStore {
        ProductivityStore(fileURL: SecureLocalStorage.applicationSupportDirectory().appendingPathComponent("productivity.json"))
    }

    func load() throws -> ProductivitySnapshot {
        guard let fileURL else { return memory }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return ProductivitySnapshot() }
        let snapshot = try JSONDecoder().decode(ProductivitySnapshot.self, from: Data(contentsOf: fileURL))
        guard snapshot.version == 1 else { throw ProductivityError.unsupportedVersion }
        guard Set(snapshot.items.map(\.id)).count == snapshot.items.count,
              Set(snapshot.dailyNotes.map(\.id)).count == snapshot.dailyNotes.count else {
            throw ProductivityError.invalid("The productivity file contains duplicate records. The original file has been preserved.")
        }
        if let journal = snapshot.syncJournal { _ = try ProductivitySyncMerge.union(journal, []) }
        return snapshot
    }

    func save(_ snapshot: ProductivitySnapshot) throws {
        guard let fileURL else { memory = snapshot; return }
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: NSNumber(value: 0o700)])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
        SecureLocalStorage.protectFile(at: fileURL)
    }
}
