import Foundation

enum DataQueryBuilder {
    static func preview(tableName: String) -> String {
        "SELECT * FROM \(quotedIdentifier(tableName))"
    }

    static func combine(_ sources: [DataSource]) throws -> String {
        guard sources.count >= 2 else {
            throw DataWorkspaceError.needsMultipleSources(.combine)
        }

        return sources.map { source in
            "SELECT *, \(quotedLiteral(source.displayName)) AS \"_tidy_source\" FROM \(quotedIdentifier(source.tableName))"
        }
        .joined(separator: " UNION ALL BY NAME ")
    }

    static func compare(
        left: DataSource,
        right: DataSource,
        key: String
    ) throws -> String {
        var leftNames: [String: String] = [:]
        var rightNames: [String: String] = [:]
        for column in left.columns where leftNames[column.name.lowercased()] == nil {
            leftNames[column.name.lowercased()] = column.name
        }
        for column in right.columns where rightNames[column.name.lowercased()] == nil {
            rightNames[column.name.lowercased()] = column.name
        }
        guard let leftKey = leftNames[key.lowercased()],
              let rightKey = rightNames[key.lowercased()] else {
            throw DataWorkspaceError.noComparisonKey
        }

        let valueColumns = left.columns.compactMap { column -> (left: String, right: String)? in
            guard column.name.caseInsensitiveCompare(leftKey) != .orderedSame,
                  let rightName = rightNames[column.name.lowercased()] else { return nil }
            return (column.name, rightName)
        }
        let changedExpression = valueColumns.isEmpty
            ? "FALSE"
            : valueColumns.map { pair in
                "l.\(quotedIdentifier(pair.left)) IS DISTINCT FROM r.\(quotedIdentifier(pair.right))"
            }.joined(separator: " OR ")
        var projections = [
            "COALESCE(l.\(quotedIdentifier(leftKey)), r.\(quotedIdentifier(rightKey))) AS \(quotedIdentifier(leftKey))",
            "CASE WHEN l.\(quotedIdentifier(leftKey)) IS NULL THEN 'Added' " +
                "WHEN r.\(quotedIdentifier(rightKey)) IS NULL THEN 'Removed' " +
                "WHEN \(changedExpression) THEN 'Changed' ELSE 'Unchanged' END AS \"_tidy_status\""
        ]

        for pair in valueColumns {
            projections.append("l.\(quotedIdentifier(pair.left)) AS \(quotedIdentifier("\(pair.left)_left"))")
            projections.append("r.\(quotedIdentifier(pair.right)) AS \(quotedIdentifier("\(pair.left)_right"))")
        }

        return """
        SELECT \(projections.joined(separator: ", "))
        FROM \(quotedIdentifier(left.tableName)) AS l
        FULL OUTER JOIN \(quotedIdentifier(right.tableName)) AS r
          ON l.\(quotedIdentifier(leftKey)) = r.\(quotedIdentifier(rightKey))
        ORDER BY CASE \"_tidy_status\" WHEN 'Changed' THEN 1 WHEN 'Added' THEN 2 WHEN 'Removed' THEN 3 ELSE 4 END,
                 \(quotedIdentifier(leftKey))
        """
    }

    static func suggestedComparisonKey(for sources: [DataSource]) -> String? {
        guard let first = sources.first else { return nil }
        let shared = first.columns.map(\.name).filter { name in
            sources.dropFirst().allSatisfy { source in
                source.columns.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame }
            }
        }
        let priorities = ["id", "uuid", "key"]
        if let exact = priorities.first(where: { preferred in
            shared.contains { $0.caseInsensitiveCompare(preferred) == .orderedSame }
        }), let match = shared.first(where: { $0.caseInsensitiveCompare(exact) == .orderedSame }) {
            return match
        }
        return shared.first(where: { $0.lowercased().hasSuffix("_id") }) ?? shared.first
    }

    static func validateReadOnlySQL(_ sql: String, allowedTables: Set<String>) throws -> String {
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutTrailingSemicolon = trimmed.hasSuffix(";") ? String(trimmed.dropLast()) : trimmed
        let uppercased = withoutTrailingSemicolon.uppercased()
        guard uppercased.hasPrefix("SELECT ") || uppercased.hasPrefix("WITH ") else {
            throw DataWorkspaceError.unsafeQuery("only SELECT queries are allowed")
        }
        guard !withoutTrailingSemicolon.contains(";") else {
            throw DataWorkspaceError.unsafeQuery("multiple SQL statements are not allowed")
        }

        let forbidden = [
            "INSTALL", "LOAD", "ATTACH", "DETACH", "COPY", "EXPORT", "IMPORT",
            "PRAGMA", "CREATE", "UPDATE", "INSERT", "DELETE", "DROP", "ALTER",
            "READ_", "SCAN(", "GLOB(", "HTTP://", "HTTPS://", "INFORMATION_SCHEMA", "DUCKDB_"
        ]
        if let token = forbidden.first(where: { containsToken($0, in: uppercased) }) {
            throw DataWorkspaceError.unsafeQuery("\(token) is not available in data questions")
        }

        guard !allowedTables.isEmpty else { throw DataWorkspaceError.noSources }
        guard allowedTables.contains(where: { table in
            withoutTrailingSemicolon.range(
                of: "\"\(table.replacingOccurrences(of: "\"", with: "\"\""))\"",
                options: [.caseInsensitive]
            ) != nil
        }) else {
            throw DataWorkspaceError.unsafeQuery("the query must use one of the imported CSV tables")
        }
        return withoutTrailingSemicolon
    }

    static func quotedIdentifier(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    static func quotedLiteral(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }

    private static func containsToken(_ token: String, in sql: String) -> Bool {
        if token.contains("(") || token.contains("://") || token.hasSuffix("_") {
            return sql.contains(token)
        }
        let escaped = NSRegularExpression.escapedPattern(for: token)
        return sql.range(of: "\\b\(escaped)\\b", options: .regularExpression) != nil
    }
}
