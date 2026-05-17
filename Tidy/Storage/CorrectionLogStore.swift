import Foundation

@MainActor
final class CorrectionLogStore: ObservableObject {
    @Published private(set) var entries: [CorrectionLogEntry] = []
    private let url: URL

    init() {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Tidy", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("corrections.json")
        load()
    }

    func append(original: String, corrected: String, providerID: String) {
        entries.insert(CorrectionLogEntry(original: original, corrected: corrected, providerID: providerID), at: 0)
        entries = Array(entries.prefix(50))
        save()
    }

    func clear() {
        entries.removeAll()
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([CorrectionLogEntry].self, from: data) else {
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
