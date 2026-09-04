import DuckDB
import Foundation

protocol TabularDataEngine: Sendable {
    func registerCSV(_ url: URL, id: UUID, tableName: String) async throws -> DataSource
    func removeTable(named tableName: String) async throws
    func query(_ sql: String, limit: Int) async throws -> DataTable
    func exportCSV(query sql: String, to url: URL) async throws
}

actor DuckDBDataEngine: TabularDataEngine {
    private var database: Database?
    private var databaseConnection: Connection?

    func registerCSV(_ url: URL, id: UUID, tableName: String) throws -> DataSource {
        let connection = try activeConnection()
        let table = DataQueryBuilder.quotedIdentifier(tableName)
        let path = DataQueryBuilder.quotedLiteral(url.path)
        try connection.execute("""
        CREATE OR REPLACE VIEW \(table) AS
        SELECT * FROM read_csv(
            \(path),
            auto_detect = true,
            header = true,
            sample_size = -1,
            ignore_errors = false
        )
        """)

        let description = try connection.query("DESCRIBE SELECT * FROM \(table)")
        let nameColumn = description[0].cast(to: String.self)
        let typeColumn = description[1].cast(to: String.self)
        let columns = (0..<Int(description.rowCount)).map { index in
            DataColumn(
                name: nameColumn[UInt64(index)] ?? "Column \(index + 1)",
                type: typeColumn[UInt64(index)] ?? "UNKNOWN"
            )
        }

        let countResult = try connection.query("SELECT COUNT(*)::VARCHAR AS row_count FROM \(table)")
        let rowCount = Int(countResult[0].cast(to: String.self)[0] ?? "0") ?? 0
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let byteCount = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        return DataSource(
            id: id,
            url: url,
            tableName: tableName,
            displayName: url.lastPathComponent,
            rowCount: rowCount,
            columns: columns,
            byteCount: byteCount
        )
    }

    func removeTable(named tableName: String) throws {
        try activeConnection().execute("DROP VIEW IF EXISTS \(DataQueryBuilder.quotedIdentifier(tableName))")
    }

    func query(_ sql: String, limit: Int = 250) throws -> DataTable {
        let connection = try activeConnection()
        let boundedLimit = max(1, min(limit, 1_000))
        let countResult = try connection.query("SELECT COUNT(*)::VARCHAR FROM (\(sql)) AS tidy_count")
        let totalRowCount = Int(countResult[0].cast(to: String.self)[0] ?? "0") ?? 0
        let result = try connection.query("""
        SELECT COLUMNS(*)::VARCHAR
        FROM (\(sql)) AS tidy_result
        LIMIT \(boundedLimit)
        """)
        let columns = (0..<Int(result.columnCount)).map { result.columnName(at: UInt64($0)) }
        let stringColumns = (0..<Int(result.columnCount)).map {
            result[UInt64($0)].cast(to: String.self)
        }
        let rows = (0..<Int(result.rowCount)).map { rowIndex in
            stringColumns.map { $0[UInt64(rowIndex)] }
        }
        return DataTable(
            columns: columns,
            rows: rows,
            totalRowCount: totalRowCount,
            isTruncated: totalRowCount > boundedLimit
        )
    }

    func exportCSV(query sql: String, to url: URL) throws {
        let path = DataQueryBuilder.quotedLiteral(url.path)
        try activeConnection().execute("COPY (\(sql)) TO \(path) (FORMAT CSV, HEADER TRUE)")
    }

    private func activeConnection() throws -> Connection {
        if let databaseConnection { return databaseConnection }
        let database = try Database(store: .inMemory)
        let connection = try database.connect()
        self.database = database
        databaseConnection = connection
        return connection
    }
}
