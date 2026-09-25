import Foundation

@MainActor
final class SlackReplyStore {
    let url: URL?
    private var memory = SlackReplySnapshot()
    init(directory: URL?) { url = directory?.appendingPathComponent("slack-replies.json") }

    func load() throws -> SlackReplySnapshot {
        guard let url else { return memory }
        guard FileManager.default.fileExists(atPath: url.path) else { return SlackReplySnapshot() }
        let value = try JSONDecoder().decode(SlackReplySnapshot.self, from: Data(contentsOf: url))
        guard value.version == 1, Set(value.topics.map(\.id)).count == value.topics.count,
              value.topics.allSatisfy({ !$0.mentions.isEmpty }) else {
            throw SlackReplyError.message("The Slack inbox cache is not supported. Its original data was preserved.")
        }
        return value
    }

    func save(_ value: SlackReplySnapshot) throws {
        guard let url else { memory = value; return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: NSNumber(value: 0o700)])
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
        SecureLocalStorage.protectFile(at: url)
    }
}
