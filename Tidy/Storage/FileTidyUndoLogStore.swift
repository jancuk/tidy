import Foundation

@MainActor
final class FileTidyUndoLogStore: ObservableObject {
    @Published private(set) var sessions: [FileTidyUndoSession] = []
    private let url: URL

    init() {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Tidy", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("file-tidy-undo.json")
        load()
    }

    func append(rootURL: URL, moves: [FileTidyAppliedMove]) {
        guard !moves.isEmpty else { return }
        sessions.insert(FileTidyUndoSession(
            id: UUID(),
            rootPath: rootURL.path,
            createdAt: Date(),
            moves: moves
        ), at: 0)
        sessions = Array(sessions.prefix(25))
        save()
    }

    func remove(_ session: FileTidyUndoSession) {
        sessions.removeAll { $0.id == session.id }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([FileTidyUndoSession].self, from: data) else {
            sessions = []
            return
        }
        sessions = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        try? data.write(to: url, options: .atomic)
        chmod(url.path, S_IRUSR | S_IWUSR)
    }
}
