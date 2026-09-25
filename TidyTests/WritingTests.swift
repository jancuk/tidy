import Foundation
import Testing
@testable import Tidy

@MainActor
struct WritingTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("TidyWritingTests-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func service(_ folder: URL? = nil) -> ProductivityService {
        ProductivityService(store: ProductivityStore(fileURL: folder?.appendingPathComponent("productivity.json")),
                            notifier: SilentProductivityNotifications())
    }

    @Test func unfinishedWritingSurvivesRestartWithoutPublishingANote() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = service(directory)
        let item = ProductivityItem(kind: .note, tags: ["idea"], pinned: true)
        let text = "# My idea\n\n  Keep the exact spacing.\n"
        #expect(workspace.keepWritingDraft(item: item, source: text))
        #expect(workspace.snapshot.items.isEmpty)
        let restored = service(directory)
        #expect(restored.writingDrafts.first?.source == text)
        #expect(restored.writingDrafts.first?.item.pinned == true)
        #expect(restored.writingDrafts.first?.item.tags == ["idea"])
        #expect(restored.finishWriting(item, source: text))
        #expect(restored.snapshot.items.first?.markdownSource == text)
        #expect(restored.writingDrafts.isEmpty)
        #expect(service(directory).writingDrafts.isEmpty)
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("writing-drafts.json").path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test func discardingAnEditPreservesTheSavedNote() {
        let workspace = service()
        #expect(workspace.quickCapture("# Original\n\nKeep me.", kind: .note))
        let original = workspace.snapshot.items[0]
        #expect(workspace.keepWritingDraft(item: original, source: "Changed"))
        #expect(workspace.discardWritingDraft(original.id))
        #expect(workspace.snapshot.items == [original])
        #expect(workspace.writingDrafts.isEmpty)
    }

    @Test func concurrentNoteChangeRequiresSavingACopy() {
        let workspace = service()
        #expect(workspace.quickCapture("Original", kind: .note))
        let original = workspace.snapshot.items[0]
        #expect(workspace.keepWritingDraft(item: original, source: "My draft"))
        var remote = original
        remote.setMarkdownSource("Another edit")
        #expect(workspace.save(remote))
        #expect(workspace.keepWritingDraft(item: original, source: "My latest draft"))
        #expect(!workspace.finishWriting(original, source: "My latest draft"))
        #expect(workspace.snapshot.items[0].markdownSource == "Another edit")
        #expect(workspace.writingDrafts.count == 1)
        #expect(workspace.finishWriting(original, source: "My latest draft", asCopy: true))
        #expect(Set(workspace.snapshot.items.map(\.markdownSource)) == ["Another edit", "My latest draft"])
        #expect(workspace.writingDrafts.isEmpty)
    }

    @Test func archivedNoteIsNotSilentlyRestoredByAnOldDraft() {
        let workspace = service()
        #expect(workspace.quickCapture("Original", kind: .note))
        let original = workspace.snapshot.items[0]
        #expect(workspace.keepWritingDraft(item: original, source: "Draft"))
        workspace.archive(original)
        #expect(!workspace.finishWriting(original, source: "Draft"))
        #expect(workspace.snapshot.items[0].archivedAt != nil)
        #expect(workspace.writingDrafts.count == 1)
    }

    @Test func corruptDraftFileBlocksOverwritingAndKeepsOriginalBytes() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("writing-drafts.json")
        let bytes = Data("recover this draft".utf8)
        try bytes.write(to: url)
        let workspace = service(directory)
        #expect(!workspace.writingDraftsReady)
        #expect(!workspace.keepWritingDraft(item: ProductivityItem(kind: .note), source: "Replacement"))
        #expect(try Data(contentsOf: url) == bytes)
        #expect(workspace.storageReady)
    }

    @Test func failedDraftWriteDoesNotReportSuccess() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = service(directory)
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("writing-drafts.json"), withIntermediateDirectories: false)
        #expect(!workspace.keepWritingDraft(item: ProductivityItem(kind: .note), source: "My writing"))
        #expect(workspace.writingDrafts.isEmpty)
        #expect(workspace.writingDraftError != nil)
    }

    @Test func failedNoteSaveKeepsRecoverableDraft() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = service(directory)
        let item = ProductivityItem(kind: .note)
        #expect(workspace.keepWritingDraft(item: item, source: "Recover me"))
        try FileManager.default.createDirectory(at: directory.appendingPathComponent("productivity.json"), withIntermediateDirectories: false)
        #expect(!workspace.finishWriting(item, source: "Recover me"))
        #expect(workspace.snapshot.items.isEmpty)
        #expect(workspace.writingDrafts.first?.source == "Recover me")
    }

    @Test func markdownPunctuationDoesNotCountTowardWordGoal() {
        #expect(WritingMetrics.wordCount("# Hello world\n\n- [ ] Write one sentence.\n---") == 5)
        #expect(WritingMetrics.wordCount("  \n\t") == 0)
    }
}
