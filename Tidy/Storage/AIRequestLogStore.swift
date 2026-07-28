import Foundation

@MainActor
final class AIRequestLogStore: ObservableObject {
    @Published private(set) var entries: [AIRequestLogEntry] = []
    private let url: URL

    init() {
        let directory = SecureLocalStorage.applicationSupportDirectory()
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
        SecureLocalStorage.protectFile(at: url)
    }
}
