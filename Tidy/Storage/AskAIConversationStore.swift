import Foundation

struct AskAIConversation: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var messages: [AskAIMessage]
    var updatedAt = Date()

    var markdown: String {
        (["# " + title] + messages.map { "## " + ($0.role == .user ? "You" : "Assistant") + "\n\n" + $0.content })
            .joined(separator: "\n\n") + "\n"
    }
}

@MainActor
final class AskAIConversationStore: ObservableObject {
    @Published private(set) var conversations: [AskAIConversation] = []
    @Published private(set) var errorMessage: String?
    private let url: URL
    private var readable = true
    private struct Archive: Codable { var version = 1; var conversations: [AskAIConversation] }
    private static let maximumBytes = 10_000_000

    init(directory: URL? = nil) {
        let directory = directory ?? SecureLocalStorage.applicationSupportDirectory()
        SecureLocalStorage.ensureOwnerOnlyDirectory(at: directory)
        url = directory.appendingPathComponent("ai-conversations.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
            guard size <= Self.maximumBytes else { throw TextActionError.invalid("Chat history exceeds 10 MB.") }
            let archive = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: url))
            guard archive.version == 1,
                  Set(archive.conversations.map(\.id)).count == archive.conversations.count,
                  archive.conversations.allSatisfy({ Set($0.messages.map(\.id)).count == $0.messages.count }) else {
                throw TextActionError.invalid("Unsupported or damaged chat history.")
            }
            conversations = archive.conversations.sorted { $0.updatedAt > $1.updatedAt }
        } catch {
            readable = false
            errorMessage = "Chat history could not be loaded. The original file is preserved. \(error.localizedDescription)"
        }
    }

    func save(_ conversation: AskAIConversation) throws {
        guard !conversation.messages.isEmpty else { return }
        try persist(([conversation] + conversations.filter { $0.id != conversation.id }).sorted { $0.updatedAt > $1.updatedAt })
    }

    func delete(_ id: UUID) throws { try persist(conversations.filter { $0.id != id }) }
    func clear() throws { try persist([]) }

    func rename(_ id: UUID, title: String) throws {
        let title = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        guard !title.isEmpty else { return }
        var next = conversations
        guard let index = next.firstIndex(where: { $0.id == id }) else { return }
        next[index].title = title
        try persist(next)
    }

    private func persist(_ conversations: [AskAIConversation]) throws {
        guard readable else { throw TextActionError.invalid(errorMessage ?? "Chat history is unavailable.") }
        guard conversations.count <= 100 else { throw TextActionError.invalid("Chat history is full. Export and delete an older chat to save another.") }
        let data = try JSONEncoder().encode(Archive(conversations: conversations))
        guard data.count <= Self.maximumBytes else { throw TextActionError.invalid("Chat history exceeds 10 MB. Export and delete older chats to make room.") }
        try data.write(to: url, options: .atomic)
        SecureLocalStorage.protectFile(at: url)
        self.conversations = conversations
        errorMessage = nil
    }
}
