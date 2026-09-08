import Foundation

enum DataWorkspaceMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case lookup, replace, combine, join, compare, analyze

    var id: String { rawValue }
    var title: String {
        switch self {
        case .lookup: "Lookup"
        case .replace: "Replace"
        case .combine: "Append"
        case .join: "Join"
        case .compare: "Reconcile"
        case .analyze: "Analyze"
        }
    }
    var detail: String {
        switch self {
        case .lookup: "Bring a value from another table into every matching row."
        case .replace: "Find and replace values without changing your original file."
        case .combine: "Stack files into one table, aligned by column name."
        case .join: "Connect two tables using matching columns."
        case .compare: "Find added, removed, and changed records across two files."
        case .analyze: "Check data quality or summarize numbers by category."
        }
    }
    var systemImage: String {
        switch self {
        case .lookup: "magnifyingglass"
        case .replace: "arrow.triangle.2.circlepath"
        case .combine: "rectangle.stack.badge.plus"
        case .join: "point.3.connected.trianglepath.dotted"
        case .compare: "arrow.left.arrow.right.square"
        case .analyze: "chart.bar.xaxis"
        }
    }
    var example: String {
        switch self {
        case .lookup: "Add customer names to orders"
        case .replace: "Standardize statuses and labels"
        case .combine: "Consolidate monthly exports"
        case .join: "Connect orders with customers"
        case .compare: "Check invoices against payments"
        case .analyze: "Find missing values and total sales"
        }
    }
    var needsPair: Bool { self == .lookup || self == .join || self == .compare }
}

struct DataWorkflowConfiguration: Equatable, Codable, Sendable {
    var leftID: UUID?
    var rightID: UUID?
    var leftKey = ""
    var rightKey = ""
    var valueColumn = ""
    var find = ""
    var replacement = ""
    var exactReplacement = true
    var joinKind: DataJoinKind = .left
    var differencesOnly = true
    var groupColumn = ""
    var metricColumn = ""
    var aggregation: DataAggregation = .profile
}

enum DataJoinKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case left = "Keep all main rows"
    case inner = "Matching rows only"
    case full = "Keep all rows from both"
    var id: String { rawValue }
    var sql: String {
        switch self {
        case .left: "LEFT JOIN"
        case .inner: "INNER JOIN"
        case .full: "FULL OUTER JOIN"
        }
    }
}

enum DataAggregation: String, CaseIterable, Identifiable, Codable, Sendable {
    case profile = "Column quality"
    case count = "Count rows"
    case sum = "Sum"
    case average = "Average"
    case minimum = "Minimum"
    case maximum = "Maximum"
    var id: String { rawValue }
    var needsMetric: Bool { self != .profile && self != .count }
    var sql: String {
        switch self {
        case .sum: "SUM"
        case .average: "AVG"
        case .minimum: "MIN"
        case .maximum: "MAX"
        default: "COUNT"
        }
    }
}

struct DataResultCount: Identifiable, Equatable {
    let label: String
    let count: Int
    var id: String { label }
}

struct DataColumn: Identifiable, Equatable, Sendable {
    let name: String
    let type: String

    var id: String { name }
}

struct DataSource: Identifiable, Equatable, Sendable {
    let id: UUID
    let url: URL
    let tableName: String
    let displayName: String
    let rowCount: Int
    let columns: [DataColumn]
    let byteCount: Int64

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }
}

struct DataTable: Equatable, Sendable {
    let columns: [String]
    let rows: [[String?]]
    let totalRowCount: Int
    let isTruncated: Bool

    static let empty = DataTable(columns: [], rows: [], totalRowCount: 0, isTruncated: false)
}

struct DataAIPlan: Codable, Equatable, Sendable {
    let title: String
    let summary: String
    let sql: String
    let steps: [String]
}

struct DataWorkspaceMessage: Identifiable, Equatable, Sendable {
    enum Role: Equatable, Sendable {
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    let text: String

    init(id: UUID = UUID(), role: Role, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }
}

enum DataWorkspaceError: LocalizedError, Equatable {
    case invalidConfiguration(String)
    case noSources
    case needsMultipleSources(DataWorkspaceMode)
    case noSharedColumns
    case noComparisonKey
    case unsafeQuery(String)
    case invalidAIResponse

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message):
            message
        case .noSources:
            "Add at least one CSV file first."
        case .needsMultipleSources(let mode):
            "\(mode.title) needs at least two CSV files."
        case .noSharedColumns:
            "These files do not have any shared column names to combine or compare."
        case .noComparisonKey:
            "Choose a column that uniquely identifies rows in both files."
        case .unsafeQuery(let reason):
            "Tidy blocked the generated query: \(reason)"
        case .invalidAIResponse:
            "The AI provider did not return a usable data plan. Try rephrasing the request."
        }
    }
}

struct DataWorkflowRecipe: Identifiable, Codable, Equatable {
    let id: UUID
    let name: String
    let mode: DataWorkspaceMode
    let configuration: DataWorkflowConfiguration
}
