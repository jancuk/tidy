import Foundation
import Testing
@testable import Tidy

struct HistoryStorageTests {
    @MainActor @Test func historiesPersistAndClearOnlyTheirOwnDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("first")
        let second = root.appendingPathComponent("second")
        let corrections = CorrectionLogStore(directory: first)
        corrections.append(original: "These is ready.", corrected: "These are ready.", providerID: "openai")
        let requests = AIRequestLogStore(directory: first)
        requests.append(AIRequestLogEntry(providerName: "OpenAI", requestPreview: "These is ready.", durationMs: 180, source: "grammar"))
        #expect(CorrectionLogStore(directory: first).entries.first?.corrected == "These are ready.")
        #expect(AIRequestLogStore(directory: first).entries.count == 1)
        #expect(CorrectionLogStore(directory: second).entries.isEmpty)
        #expect(AIRequestLogStore(directory: second).entries.isEmpty)
        CorrectionLogStore(directory: second).clear()
        AIRequestLogStore(directory: second).clear()
        #expect(CorrectionLogStore(directory: first).entries.count == 1)
        #expect(AIRequestLogStore(directory: first).entries.count == 1)
    }

    @Test func clipboardSearchKeepsFullContentAndDeletesOnlySelectedItem() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ClipboardStore(directory: root)
        let longText = String(repeating: "Reading a longer note. ", count: 30) + "Reconciliation"
        store.insert(content: longText, sourceAppBundleID: nil, sourceAppName: "Notes", maxEntries: 50, maxAgeDays: 7)
        store.insert(content: "Another item", sourceAppBundleID: nil, sourceAppName: nil, maxEntries: 50, maxAgeDays: 7)
        let found = try #require(store.entries(matching: "Reconciliation").first)
        #expect(found.preview.count == 200)
        #expect(found.content == longText)
        store.deleteEntry(id: found.id)
        #expect(store.entries(matching: "").map(\.content) == ["Another item"])
    }
}
