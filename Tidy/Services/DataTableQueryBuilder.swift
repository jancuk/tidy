import Foundation

enum DataTableQueryBuilder {
    static func build(baseSQL: String, columns: [String], options: DataTableOptions, includeOrder: Bool = true) throws -> String {
        let available = Set(columns)
        func column(_ name: String) throws -> String {
            guard available.contains(name) else {
                throw DataWorkspaceError.invalidConfiguration("Column ‘\(name)’ is no longer available. Reset the table controls.")
            }
            return DataQueryBuilder.quotedIdentifier(name)
        }
        var predicates: [String] = []
        if !options.search.isEmpty {
            let term = DataQueryBuilder.quotedLiteral(options.search)
            let search = columns.map {
                "contains(lower(COALESCE(CAST(\(DataQueryBuilder.quotedIdentifier($0)) AS VARCHAR), '')), lower(\(term)))"
            }.joined(separator: " OR ")
            if !search.isEmpty { predicates.append("(\(search))") }
        }
        let filters = try options.filters.map { filter -> String in
            let identifier = try column(filter.column)
            let raw = "COALESCE(CAST(\(identifier) AS VARCHAR), '')"
            let literal = DataQueryBuilder.quotedLiteral(filter.value)
            let text = filter.caseSensitive ? raw : "lower(\(raw))"
            let value = filter.caseSensitive ? literal : "lower(\(literal))"
            if filter.operation.isNumeric {
                guard let number = Double(filter.value), number.isFinite else {
                    throw DataWorkspaceError.invalidConfiguration("Enter a finite number for the ‘\(filter.column)’ filter.")
                }
                let comparison: String
                switch filter.operation {
                case .greaterThan: comparison = ">"
                case .lessThan: comparison = "<"
                case .atLeast: comparison = ">="
                default: comparison = "<="
                }
                return "TRY_CAST(\(identifier) AS DOUBLE) \(comparison) \(number)"
            }
            switch filter.operation {
            case .contains: return "contains(\(text), \(value))"
            case .notContains: return "NOT contains(\(text), \(value))"
            case .equals: return "\(text) = \(value)"
            case .notEquals: return "\(text) <> \(value)"
            case .startsWith: return "starts_with(\(text), \(value))"
            case .endsWith: return "ends_with(\(text), \(value))"
            case .isEmpty: return "\(raw) = ''"
            case .isNotEmpty: return "\(raw) <> ''"
            default: preconditionFailure("Numeric filters are handled above")
            }
        }
        if !filters.isEmpty { predicates.append("(" + filters.joined(separator: options.matchAny ? " OR " : " AND ") + ")") }
        var sql = "SELECT * FROM (\(baseSQL)) AS tidy_view"
        if !predicates.isEmpty { sql += " WHERE " + predicates.joined(separator: " AND ") }
        let sorts = try options.sorts.map { sort -> String in
            let identifier = try column(sort.column)
            let expression: String
            switch sort.kind {
            case .text: expression = "lower(NULLIF(CAST(\(identifier) AS VARCHAR), ''))"
            case .number: expression = "TRY_CAST(\(identifier) AS DOUBLE)"
            case .date: expression = "TRY_CAST(\(identifier) AS TIMESTAMP)"
            }
            return expression + (sort.ascending ? " ASC" : " DESC") + " NULLS LAST"
        }
        if includeOrder && !sorts.isEmpty {
            // Break ties consistently so rows do not jump between pages.
            let ties = columns.map { DataQueryBuilder.quotedIdentifier($0) + " ASC NULLS LAST" }
            sql += " ORDER BY " + (sorts + ties).joined(separator: ", ")
        }
        return sql
    }
}
