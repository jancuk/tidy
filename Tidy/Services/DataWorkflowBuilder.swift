import Foundation

struct DataWorkflowPlan {
    let plan: DataAIPlan
    let checks: [(sql: String, message: String)]
}

enum DataWorkflowBuilder {
    private static func q(_ value: String) -> String { DataQueryBuilder.quotedIdentifier(value) }
    private static func literal(_ value: String) -> String { DataQueryBuilder.quotedLiteral(value) }

    static func build(
        mode: DataWorkspaceMode,
        configuration c: DataWorkflowConfiguration,
        sources: [DataSource]
    ) throws -> DataWorkflowPlan {
        guard !sources.isEmpty else { throw DataWorkspaceError.noSources }
        guard let left = sources.first(where: { $0.id == c.leftID }) else {
            throw DataWorkspaceError.invalidConfiguration("Choose a main table.")
        }
        guard sources.allSatisfy({ source in
            source.columns.allSatisfy { !$0.name.lowercased().hasPrefix("_tidy_") }
        }) else {
            throw DataWorkspaceError.invalidConfiguration("Rename columns starting with _tidy_ before running a workflow; Tidy uses that prefix for result details.")
        }
        var checks: [(sql: String, message: String)] = []
        var sql: String
        var summary: String
        let table = q(left.tableName)
        if mode == .combine {
            sql = try DataQueryBuilder.combine(sources)
            summary = "Appended all \(sources.count) tables by column name. Missing columns are blank; _tidy_source records the original file."
        } else if mode == .replace {
            try requireColumn(c.valueColumn, in: left)
            guard !c.find.isEmpty else { throw DataWorkspaceError.invalidConfiguration("Enter a value to find.") }
            let value = q(c.valueColumn)
            let text = "CAST(\(value) AS VARCHAR)"
            let condition = c.exactReplacement
                ? "\(text) = \(literal(c.find))"
                : "contains(\(text), \(literal(c.find)))"
            let replacement = c.exactReplacement
                ? "CASE WHEN \(condition) THEN \(literal(c.replacement)) ELSE \(text) END"
                : "replace(\(text), \(literal(c.find)), \(literal(c.replacement)))"
            let columns = left.columns.map { $0.name == c.valueColumn ? "\(replacement) AS \(value)" : q($0.name) }
            sql = "SELECT \(columns.joined(separator: ", ")), \(value) AS \"_tidy_original\", CASE WHEN (\(replacement)) IS DISTINCT FROM \(text) THEN 'Replaced' ELSE 'Unchanged' END AS \"_tidy_status\" FROM \(table)"
            summary = "Case-sensitive replacement in \(c.valueColumn). Original values remain in _tidy_original. Source files are unchanged."
        } else if mode == .analyze {
            if c.aggregation == .profile {
                sql = left.columns.map { column in
                    let value = q(column.name)
                    return "SELECT \(literal(column.name)) AS \"Column\", COUNT(*) AS \"Rows\", COUNT(*) FILTER (WHERE \(value) IS NULL OR trim(CAST(\(value) AS VARCHAR)) = '') AS \"Missing\", COUNT(DISTINCT \(value)) AS \"Distinct values\" FROM \(table)"
                }.joined(separator: " UNION ALL ")
                summary = "Quality checks across every row. Missing includes nulls and whitespace-only values; distinct values exclude nulls."
            } else {
                if !c.groupColumn.isEmpty { try requireColumn(c.groupColumn, in: left) }
                var expression = "COUNT(*)"
                if c.aggregation.needsMetric {
                    try requireColumn(c.metricColumn, in: left)
                    let metric = q(c.metricColumn)
                    checks.append((
                        "SELECT COUNT(*) FROM \(table) WHERE \(metric) IS NOT NULL AND trim(CAST(\(metric) AS VARCHAR)) <> '' AND TRY_CAST(\(metric) AS DOUBLE) IS NULL",
                        "\(c.metricColumn) contains nonnumeric values. Clean them before calculating a numeric summary."
                    ))
                    expression = "\(c.aggregation.sql)(TRY_CAST(\(metric) AS DOUBLE))"
                }
                let group = c.groupColumn.isEmpty ? "" : "\(q(c.groupColumn)) AS \"_tidy_group\", "
                let suffix = c.groupColumn.isEmpty ? "" : " GROUP BY \(q(c.groupColumn)) ORDER BY \(q(c.groupColumn))"
                sql = "SELECT \(group)\(expression) AS \"_tidy_value\", COUNT(*) AS \"_tidy_rows\" FROM \(table)\(suffix)"
                summary = "\(c.aggregation.rawValue) across all rows\(c.groupColumn.isEmpty ? "" : " grouped by \(c.groupColumn)"). Numeric summaries exclude missing values."
            }
        } else {
            guard let right = sources.first(where: { $0.id == c.rightID }), right.id != left.id else {
                throw DataWorkspaceError.invalidConfiguration("Choose a different reference table.")
            }
            try requireColumn(c.leftKey, in: left)
            try requireColumn(c.rightKey, in: right)
            let lk = "l.\(q(c.leftKey))"
            let rk = "r.\(q(c.rightKey))"
            let condition = "CAST(\(lk) AS VARCHAR) = CAST(\(rk) AS VARCHAR)"
            if mode == .lookup || mode == .compare {
                checks.append(keyCheck(right, key: c.rightKey))
            }
            if mode == .compare { checks.append(keyCheck(left, key: c.leftKey)) }
            if mode == .lookup {
                try requireColumn(c.valueColumn, in: right)
                sql = "SELECT l.*, r.\(q(c.valueColumn)) AS \"_tidy_lookup\", CASE WHEN \(rk) IS NULL THEN 'Unmatched' ELSE 'Matched' END AS \"_tidy_status\" FROM \(table) l LEFT JOIN \(q(right.tableName)) r ON \(condition)"
                summary = "Added \(right.displayName) → \(c.valueColumn) as _tidy_lookup. Each main row is kept; unmatched keys are flagged. Matching is exact and case-sensitive."
            } else if mode == .join {
                var used = Set(left.columns.map { $0.name.lowercased() })
                let added = right.columns.map { column -> String in
                    var alias = "reference_\(column.name)"
                    while used.contains(alias.lowercased()) { alias += "_2" }
                    used.insert(alias.lowercased())
                    return "r.\(q(column.name)) AS \(q(alias))"
                }
                sql = "SELECT l.*, \(added.joined(separator: ", ")), CASE WHEN \(lk) IS NULL THEN 'Reference only' WHEN \(rk) IS NULL THEN 'Main only' ELSE 'Matched' END AS \"_tidy_status\" FROM \(table) l \(c.joinKind.sql) \(q(right.tableName)) r ON \(condition)"
                summary = "\(c.joinKind.rawValue). Reference columns use reference_. Every matching pair is included, so repeated keys can produce multiple rows. Matching is exact and case-sensitive."
            } else {
                let pairs = left.columns.compactMap { column -> (String, String)? in
                    guard column.name != c.leftKey,
                          let match = right.columns.first(where: {
                              $0.name != c.rightKey && $0.name.caseInsensitiveCompare(column.name) == .orderedSame
                          }) else { return nil }
                    return (column.name, match.name)
                }
                guard !pairs.isEmpty else {
                    throw DataWorkspaceError.invalidConfiguration("Reconciliation needs at least one shared value column besides the keys. Rename corresponding columns to match.")
                }
                let changes = pairs.map { "CAST(l.\(q($0.0)) AS VARCHAR) IS DISTINCT FROM CAST(r.\(q($0.1)) AS VARCHAR)" }.joined(separator: " OR ")
                var projections = [
                    "COALESCE(CAST(\(lk) AS VARCHAR), CAST(\(rk) AS VARCHAR)) AS \"_tidy_key\"",
                    "CASE WHEN \(lk) IS NULL THEN 'Added' WHEN \(rk) IS NULL THEN 'Removed' WHEN \(changes) THEN 'Changed' ELSE 'Unchanged' END AS \"_tidy_status\""
                ]
                for pair in pairs {
                    projections.append("l.\(q(pair.0)) AS \(q("main_" + pair.0))")
                    projections.append("r.\(q(pair.1)) AS \(q("reference_" + pair.0))")
                }
                sql = "SELECT \(projections.joined(separator: ", ")) FROM \(table) l FULL OUTER JOIN \(q(right.tableName)) r ON \(condition)"
                if c.differencesOnly { sql = "SELECT * FROM (\(sql)) differences WHERE \"_tidy_status\" <> 'Unchanged'" }
                sql += " ORDER BY \"_tidy_status\", \"_tidy_key\""
                summary = "Main = before; reference = after. Compared \(pairs.count) shared fields by exact value. Added exists only in reference; removed exists only in main. \(c.differencesOnly ? "Unchanged rows are hidden." : "All rows are shown.")"
            }
        }
        return DataWorkflowPlan(
            plan: DataAIPlan(title: "\(mode.title) result", summary: summary, sql: sql,
                             steps: ["\(left.displayName)", summary, "Preview and export the full result"]),
            checks: checks
        )
    }

    private static func requireColumn(_ name: String, in source: DataSource) throws {
        guard source.columns.contains(where: { $0.name == name }) else {
            throw DataWorkspaceError.invalidConfiguration("Choose a valid column from \(source.displayName).")
        }
    }

    private static func keyCheck(_ source: DataSource, key: String) -> (sql: String, message: String) {
        let column = q(key)
        return (
            "SELECT COUNT(*) FROM (SELECT \(column) FROM \(q(source.tableName)) GROUP BY \(column) HAVING COUNT(*) > 1 OR \(column) IS NULL OR trim(CAST(\(column) AS VARCHAR)) = '') invalid_keys",
            "\(source.displayName) → \(key) has duplicate or missing keys. Choose a unique, complete key to avoid ambiguous matches."
        )
    }
}
