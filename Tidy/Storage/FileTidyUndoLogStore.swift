import Foundation

@MainActor
final class FileTidyUndoLogStore: ObservableObject {
    @Published private(set) var sessions: [FileTidyUndoSession] = []
    private let url: URL

    init(directory: URL? = nil) {
        let directory = directory ?? SecureLocalStorage.applicationSupportDirectory()
        SecureLocalStorage.ensureOwnerOnlyDirectory(at: directory)
        url = directory.appendingPathComponent("file-tidy-undo.json")
        load()
    }

    func recoveryJournal(rootURL: URL) -> @Sendable ([FileTidyAppliedMove]) throws -> Void {
        let fileURL = url
        let sessionID = UUID()
        let date = Date()
        return { moves in
            let previous: [FileTidyUndoSession]
            if FileManager.default.fileExists(atPath: fileURL.path) {
                previous = try JSONDecoder().decode([FileTidyUndoSession].self, from: Data(contentsOf: fileURL))
            } else { previous = [] }
            let session = FileTidyUndoSession(id: sessionID, rootPath: rootURL.path, createdAt: date, moves: moves)
            let updated = [session] + previous.filter { $0.id != sessionID }
            try JSONEncoder().encode(updated).write(to: fileURL, options: .atomic)
            SecureLocalStorage.protectFile(at: fileURL)
        }
    }

    func reload() { load() }

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

    func clear() {
        sessions.removeAll()
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
        SecureLocalStorage.protectFile(at: url)
    }
}
