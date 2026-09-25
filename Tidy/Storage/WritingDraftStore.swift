import Foundation

@MainActor
final class WritingDraftStore {
    private let fileURL: URL?
    private var memory: [WritingDraft] = []

    init(fileURL: URL?) { self.fileURL = fileURL }

    func load() throws -> [WritingDraft] {
        guard let fileURL else { return memory }
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let drafts = try JSONDecoder().decode([WritingDraft].self, from: Data(contentsOf: fileURL))
        guard Set(drafts.map(\.id)).count == drafts.count else {
            throw ProductivityError.invalid("The draft file contains duplicate records.")
        }
        return drafts
    }

    func save(_ drafts: [WritingDraft]) throws {
        guard let fileURL else { memory = drafts; return }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: NSNumber(value: 0o700)])
        try JSONEncoder().encode(drafts).write(to: fileURL, options: .atomic)
        SecureLocalStorage.protectFile(at: fileURL)
    }
}
