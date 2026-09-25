import Foundation

enum DataFilterOperator: String, CaseIterable, Identifiable, Sendable {
    case contains = "Contains"
    case notContains = "Does not contain"
    case equals = "Equals"
    case notEquals = "Does not equal"
    case startsWith = "Starts with"
    case endsWith = "Ends with"
    case isEmpty = "Is empty"
    case isNotEmpty = "Is not empty"
    case greaterThan = "Number greater than"
    case lessThan = "Number less than"
    case atLeast = "Number at least"
    case atMost = "Number at most"

    var id: String { rawValue }
    var needsValue: Bool { self != .isEmpty && self != .isNotEmpty }
    var isNumeric: Bool { [.greaterThan, .lessThan, .atLeast, .atMost].contains(self) }
}

struct DataColumnFilter: Identifiable, Equatable, Sendable {
    var id = UUID()
    var column: String
    var operation: DataFilterOperator = .contains
    var value = ""
    var caseSensitive = false
}

enum DataSortKind: String, CaseIterable, Identifiable, Sendable {
    case text = "Text"
    case number = "Number"
    case date = "Date / time"
    var id: String { rawValue }
}

struct DataColumnSort: Identifiable, Equatable, Sendable {
    var id = UUID()
    var column: String
    var ascending = true
    var kind: DataSortKind = .text
}

struct DataTableOptions: Equatable, Sendable {
    var search = ""
    var matchAny = false
    var filters: [DataColumnFilter] = []
    var sorts: [DataColumnSort] = []
    var hiddenColumns: Set<String> = []

    var summary: String {
        var parts: [String] = []
        if !search.isEmpty { parts.append("Search active") }
        if !filters.isEmpty { parts.append("\(filters.count) \(filters.count == 1 ? "filter" : "filters")") }
        if !sorts.isEmpty { parts.append("\(sorts.count) \(sorts.count == 1 ? "sort" : "sorts")") }
        if !hiddenColumns.isEmpty { parts.append("\(hiddenColumns.count) hidden") }
        return parts.joined(separator: " · ")
    }

    var hasConditions: Bool { !search.isEmpty || !filters.isEmpty }
    var isActive: Bool { hasConditions || !sorts.isEmpty || !hiddenColumns.isEmpty }
}
