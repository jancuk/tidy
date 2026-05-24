import Foundation

@MainActor
final class AIRequestLogStore: ObservableObject {
    @Published private(set) var entries: [AIRequestLogEntry] = []
    private let url: URL

    init() {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Tidy", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("ai-requests.json")
        load()
    }

    func append(_ entry: AIRequestLogEntry) {
        entries.insert(entry, at: 0)
        entries = Array(entries.prefix(100))
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([AIRequestLogEntry].self, from: data) else {
            entries = []
            return
        }
        entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: url, options: .atomic)
        chmod(url.path, S_IRUSR | S_IWUSR)
    }
}
