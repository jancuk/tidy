import Foundation
import SQLite3
import Testing
@testable import Tidy

struct ClipboardFavoritesTests {
    @Test func favoritesSurviveRetentionAndRecopyAndCanBeFiltered() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ClipboardStore(directory: root)
        let content = "  reusable snippet\n"
        store.insert(content: content, sourceAppBundleID: "org.example.editor", sourceAppName: "Editor", maxEntries: 5, maxAgeDays: 7)
        let first = try #require(store.entries(matching: "").first)
        #expect(store.setMetadata(id: first.id, pinned: true, collection: "Code"))
        store.insert(content: "Other text", sourceAppBundleID: nil, sourceAppName: nil, maxEntries: 1, maxAgeDays: 7)
        store.insert(content: content, sourceAppBundleID: nil, sourceAppName: "Tidy", maxEntries: 1, maxAgeDays: 7)
        let pinned = try #require(store.entries(matching: "snippet", pinnedOnly: true, collection: "Code").first)
        #expect(pinned.id == first.id)
        #expect(pinned.content == content)
        #expect(pinned.sourceAppName == "Editor")
        #expect(store.collections() == ["Code"])
        store.applyRetention(maxEntries: 1, maxAgeDays: -1)
        #expect(store.entries(matching: "").map(\.id) == [first.id])
        #expect(store.entries(matching: "Other", pinnedOnly: true).isEmpty)
        #expect(store.setMetadata(id: first.id, pinned: false, collection: ""))
        store.applyRetention(maxEntries: 1, maxAgeDays: -1)
        #expect(store.entries(matching: "").isEmpty)
    }

    @Test func legacyDatabaseMigratesWithoutLosingHistory() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var db: OpaquePointer?
        #expect(sqlite3_open(root.appendingPathComponent("clipboard.sqlite").path, &db) == SQLITE_OK)
        let sql = """
        CREATE TABLE clipboard_entries (id INTEGER PRIMARY KEY AUTOINCREMENT, content TEXT NOT NULL, preview TEXT NOT NULL, source_app_bundle_id TEXT, source_app_name TEXT, created_at REAL NOT NULL, char_count INTEGER NOT NULL);
        INSERT INTO clipboard_entries (content, preview, created_at, char_count) VALUES ('legacy text', 'legacy text', 1000, 11);
        """
        #expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK)
        sqlite3_close(db)
        let store = ClipboardStore(directory: root)
        let entry = try #require(store.entries(matching: "").first)
        #expect(entry.content == "legacy text")
        #expect(!entry.isPinned)
        #expect(entry.collection.isEmpty)
        #expect(store.setMetadata(id: entry.id, pinned: true, collection: "Legacy"))
        #expect(ClipboardStore(directory: root).entries(matching: "").first?.isPinned == true)
    }
}
