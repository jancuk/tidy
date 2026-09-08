import Foundation
import Testing
@testable import Tidy

struct DeveloperCleanupTests {
    @Test func discoversHiddenBuildFoldersAndDoesNotOrganizeProjectSourceFiles() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("{}", root.appendingPathComponent("package.json"))
        try write("Keep this README", root.appendingPathComponent("README.md"))
        try write("hidden output", root.appendingPathComponent(".next/.cache/data"))
        try write("module", root.appendingPathComponent("node_modules/example/index.js"))
        let result = try FileTidyService().scan(rootURL: root)
        #expect(result.developerProjects.count == 1)
        #expect(Set(result.proposals.map(\.fileName)) == [".next", "node_modules"])
        #expect(result.proposals.allSatisfy { !$0.isRecommendedByDefault })
        #expect(result.developerProjects[0].artifactSize == Int64("hidden outputmodule".utf8.count))
        #expect(result.proposals.allSatisfy { $0.destinationPath.contains(DeveloperProjectScanner.reviewFolder) })
        #expect(result.proposals.first { $0.fileName == ".next" }?.destinationURL == root.resolvingSymlinksInPath().appendingPathComponent("Tidy Project Review/.next"))
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("README.md").path))
    }

    @Test func nestedProjectsAreCountedSeparatelyAndSymlinksAndReviewFoldersAreSkipped() throws {
        let root = try makeRoot()
        let outside = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        try write("{}", root.appendingPathComponent("package.json"))
        try write("root", root.appendingPathComponent("src.txt"))
        try write("{}", root.appendingPathComponent("packages/widget/package.json"))
        try write("child", root.appendingPathComponent("packages/widget/dist/bundle.js"))
        try write("secret", outside.appendingPathComponent("package.json"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("linked"), withDestinationURL: outside)
        try write("{}", root.appendingPathComponent("Tidy Project Review/package.json"))
        let result = try DeveloperProjectScanner().scan(root: root)
        #expect(result.projects.count == 2)
        #expect(result.projects.first { $0.url == root.resolvingSymlinksInPath().standardizedFileURL }?.size == 6)
        #expect(result.projects.first { $0.url.lastPathComponent == "widget" }?.size == 7)
        #expect(result.proposals.count == 1)
    }

    @Test func dirtyRepositoriesAreFlaggedAndTrackedBuildFilesCannotBeMoved() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try git(["init", "-q", root.path])
        try write("{}", root.appendingPathComponent("package.json"))
        try write("hand-edited", root.appendingPathComponent("dist/important.txt"))
        try git(["-C", root.path, "add", "package.json", "dist/important.txt"])
        let result = try FileTidyService().scan(rootURL: root)
        #expect(result.developerProjects.first?.gitState == .changed)
        let proposal = try #require(result.proposals.first { $0.fileName == "dist" })
        #expect(proposal.risk == .high)
        #expect(throws: FileTidyError.self) { try FileTidyService().apply([proposal], rootURL: root) }
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("dist/important.txt").path))
    }

    @MainActor @Test func moveJournalIsDurableBeforeMutationAndUndoRestoresHiddenFiles() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("{}", root.appendingPathComponent("package.json"))
        let original = root.appendingPathComponent(".next/.cache/file")
        try write("keep me", original)
        let service = FileTidyService()
        let proposal = try #require(service.scan(rootURL: root).proposals.first)
        let store = FileTidyUndoLogStore(directory: root.appendingPathComponent("history"))
        let journal = store.recoveryJournal(rootURL: root)
        var journalSawOriginal = false
        _ = try service.apply([proposal], rootURL: root) { moves in
            journalSawOriginal = FileManager.default.fileExists(atPath: original.path)
            try journal(moves)
        }
        #expect(journalSawOriginal)
        let reloaded = FileTidyUndoLogStore(directory: root.appendingPathComponent("history"))
        let session = try #require(reloaded.sessions.first)
        #expect(!FileManager.default.fileExists(atPath: original.path))
        try service.undo(session)
        #expect(try String(contentsOf: original, encoding: .utf8) == "keep me")
    }

    @Test func failedJournalPreventsAnyMoveAndBatchPreflightRejectsConflictingSources() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Screenshot.png")
        try write("image", source)
        let service = FileTidyService()
        let proposal = try #require(service.scan(rootURL: root).proposals.first)
        #expect(throws: FileTidyError.self) {
            try service.apply([proposal], rootURL: root) { _ in throw CocoaError(.fileWriteNoPermission) }
        }
        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(throws: FileTidyError.self) { try service.apply([proposal, proposal], rootURL: root) }
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test func undoPreflightNeverOverwritesAnOccupiedOriginalPath() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("image", root.appendingPathComponent("Screenshot.png"))
        let service = FileTidyService()
        let moves = try service.apply(service.scan(rootURL: root).proposals, rootURL: root)
        let move = try #require(moves.first)
        try write("new content", URL(fileURLWithPath: move.sourcePath))
        let session = FileTidyUndoSession(id: UUID(), rootPath: root.path, createdAt: Date(), moves: moves)
        #expect(throws: FileTidyError.self) { try service.undo(session) }
        #expect(try String(contentsOfFile: move.sourcePath, encoding: .utf8) == "new content")
        #expect(FileManager.default.fileExists(atPath: move.finalDestinationPath))
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TidyCleanup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func write(_ content: String, _ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func git(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }
}
