import Foundation

@MainActor
final class SlackOutboxStore {
    let url: URL?
    private var memory: [SlackSendRecord] = []

    init(directory: URL?) { url = directory?.appendingPathComponent("slack-outbox.json") }

    func load() throws -> [SlackSendRecord] {
        guard let url else { return memory }
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([SlackSendRecord].self, from: Data(contentsOf: url))
    }

    func save(_ records: [SlackSendRecord]) throws {
        guard let url else { memory = records; return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: NSNumber(value: 0o700)])
        try JSONEncoder().encode(records).write(to: url, options: .atomic)
        SecureLocalStorage.protectFile(at: url)
    }
}
