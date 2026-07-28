import Foundation
import SQLite3

final class ClipboardStore {
    private var database: OpaquePointer?
    private let queue = DispatchQueue(label: "tidy.clipboard-store")

    init() {
        openDatabase()
        migrate()
    }

    deinit {
        sqlite3_close(database)
    }

    func insert(content: String, sourceAppBundleID: String?, sourceAppName: String?, maxEntries: Int, maxAgeDays: Int) {
        let normalizedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedContent.isEmpty else { return }

        queue.sync {
            if let existingID = existingEntryID(for: normalizedContent) {
                deleteEntryOnQueue(id: existingID)
            }

            let preview = String(normalizedContent.prefix(200))
            let sql = """
            INSERT INTO clipboard_entries
            (content, preview, source_app_bundle_id, source_app_name, created_at, char_count)
            VALUES (?, ?, ?, ?, ?, ?);
            """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(statement) }

            bind(normalizedContent, to: statement, at: 1)
            bind(preview, to: statement, at: 2)
            bind(sourceAppBundleID, to: statement, at: 3)
            bind(sourceAppName, to: statement, at: 4)
            sqlite3_bind_double(statement, 5, Date().timeIntervalSince1970)
            sqlite3_bind_int64(statement, 6, Int64(normalizedContent.count))
            sqlite3_step(statement)
            applyRetentionOnQueue(maxEntries: maxEntries, maxAgeDays: maxAgeDays)
        }
    }

    func entries(matching query: String, limit: Int = 80) -> [ClipboardEntry] {
        queue.sync {
            let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedQuery.isEmpty {
                return loadEntries(sql: """
                    SELECT id, content, preview, source_app_bundle_id, source_app_name, created_at, char_count
                    FROM clipboard_entries
                    ORDER BY created_at DESC
                    LIMIT ?;
                    """, bind: { statement in
                        sqlite3_bind_int(statement, 1, Int32(limit))
                    })
            }

            let matchQuery = ftsQuery(from: trimmedQuery)
            guard !matchQuery.isEmpty else { return [] }
            return loadEntries(sql: """
                SELECT e.id, e.content, e.preview, e.source_app_bundle_id, e.source_app_name, e.created_at, e.char_count
                FROM clipboard_entries e
                JOIN clipboard_entries_fts fts ON fts.rowid = e.id
                WHERE clipboard_entries_fts MATCH ?
                ORDER BY e.created_at DESC
                LIMIT ?;
                """, bind: { statement in
                    bind(matchQuery, to: statement, at: 1)
                    sqlite3_bind_int(statement, 2, Int32(limit))
                })
        }
    }

    func deleteEntry(id: Int64) {
        queue.sync {
            deleteEntryOnQueue(id: id)
        }
    }

    func deleteAll() {
        queue.sync {
            _ = sqlite3_exec(database, "DELETE FROM clipboard_entries;", nil, nil, nil)
        }
    }

    func applyRetention(maxEntries: Int, maxAgeDays: Int) {
        queue.sync {
            applyRetentionOnQueue(maxEntries: maxEntries, maxAgeDays: maxAgeDays)
        }
    }

    private func openDatabase() {
        let fileManager = FileManager.default
        let directory = SecureLocalStorage.applicationSupportDirectory(fileManager: fileManager)
        let databaseURL = directory.appendingPathComponent("clipboard.sqlite")
        sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
        SecureLocalStorage.protectFile(at: databaseURL)
    }

    private func migrate() {
        let sql = """
        PRAGMA journal_mode=WAL;
        CREATE TABLE IF NOT EXISTS clipboard_entries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            content TEXT NOT NULL,
            preview TEXT NOT NULL,
            source_app_bundle_id TEXT,
            source_app_name TEXT,
            created_at REAL NOT NULL,
            char_count INTEGER NOT NULL
        );
        CREATE VIRTUAL TABLE IF NOT EXISTS clipboard_entries_fts
        USING fts5(content, content='clipboard_entries', content_rowid='id');
        CREATE TRIGGER IF NOT EXISTS clipboard_entries_ai AFTER INSERT ON clipboard_entries BEGIN
            INSERT INTO clipboard_entries_fts(rowid, content) VALUES (new.id, new.content);
        END;
        CREATE TRIGGER IF NOT EXISTS clipboard_entries_ad AFTER DELETE ON clipboard_entries BEGIN
            INSERT INTO clipboard_entries_fts(clipboard_entries_fts, rowid, content) VALUES('delete', old.id, old.content);
        END;
        CREATE TRIGGER IF NOT EXISTS clipboard_entries_au AFTER UPDATE ON clipboard_entries BEGIN
            INSERT INTO clipboard_entries_fts(clipboard_entries_fts, rowid, content) VALUES('delete', old.id, old.content);
            INSERT INTO clipboard_entries_fts(rowid, content) VALUES (new.id, new.content);
        END;
        CREATE INDEX IF NOT EXISTS idx_clipboard_entries_created_at ON clipboard_entries(created_at DESC);
        CREATE INDEX IF NOT EXISTS idx_clipboard_entries_content ON clipboard_entries(content);
        """
        sqlite3_exec(database, sql, nil, nil, nil)
    }

    private func loadEntries(sql: String, bind: (OpaquePointer?) -> Void) -> [ClipboardEntry] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        bind(statement)

        var entries: [ClipboardEntry] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            entries.append(ClipboardEntry(
                id: sqlite3_column_int64(statement, 0),
                content: stringColumn(statement, 1) ?? "",
                preview: stringColumn(statement, 2) ?? "",
                sourceAppBundleID: stringColumn(statement, 3),
                sourceAppName: stringColumn(statement, 4),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 5)),
                charCount: Int(sqlite3_column_int64(statement, 6))
            ))
        }
        return entries
    }

    private func existingEntryID(for content: String) -> Int64? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT id FROM clipboard_entries WHERE content = ? LIMIT 1;", -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        bind(content, to: statement, at: 1)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return sqlite3_column_int64(statement, 0)
    }

    private func deleteEntryOnQueue(id: Int64) {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "DELETE FROM clipboard_entries WHERE id = ?;", -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, id)
        sqlite3_step(statement)
    }

    private func applyRetentionOnQueue(maxEntries: Int, maxAgeDays: Int) {
        let cutoff = Date().addingTimeInterval(-Double(maxAgeDays) * 24 * 60 * 60).timeIntervalSince1970
        var cutoffStatement: OpaquePointer?
        if sqlite3_prepare_v2(database, "DELETE FROM clipboard_entries WHERE created_at < ?;", -1, &cutoffStatement, nil) == SQLITE_OK {
            sqlite3_bind_double(cutoffStatement, 1, cutoff)
            sqlite3_step(cutoffStatement)
        }
        sqlite3_finalize(cutoffStatement)

        var countStatement: OpaquePointer?
        let sql = """
        DELETE FROM clipboard_entries
        WHERE id NOT IN (
            SELECT id FROM clipboard_entries ORDER BY created_at DESC LIMIT ?
        );
        """
        if sqlite3_prepare_v2(database, sql, -1, &countStatement, nil) == SQLITE_OK {
            sqlite3_bind_int(countStatement, 1, Int32(max(1, maxEntries)))
            sqlite3_step(countStatement)
        }
        sqlite3_finalize(countStatement)
    }

    private func ftsQuery(from query: String) -> String {
        query
            .lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map { String($0).replacingOccurrences(of: "\"", with: "\"\"") + "*" }
            .joined(separator: " ")
    }

    private func bind(_ value: String?, to statement: OpaquePointer?, at index: Int32) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
    }

    private func stringColumn(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard let value = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: value)
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
