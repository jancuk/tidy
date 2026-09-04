import Foundation

enum DataWorkspaceMode: String, CaseIterable, Identifiable, Sendable {
    case analyze
    case combine
    case compare

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }

    var detail: String {
        switch self {
        case .analyze: "Ask questions, summarize trends, and find data-quality issues."
        case .combine: "Append or join CSV files into one reusable result."
        case .compare: "Find added, removed, and changed records between CSV files."
        }
    }

    var systemImage: String {
        switch self {
        case .analyze: "sparkles.rectangle.stack"
        case .combine: "rectangle.stack.badge.plus"
        case .compare: "arrow.left.arrow.right.square"
        }
    }

    var promptPlaceholder: String {
        switch self {
        case .analyze: "What would you like to learn from this data?"
        case .combine: "How should these files be combined?"
        case .compare: "What should Tidy compare between these files?"
        }
    }

    var examplePrompts: [String] {
        switch self {
        case .analyze:
            [
                "Summarize this data and highlight unusual values",
                "Show totals and averages by the most useful category",
                "Find duplicates, missing values, and possible data-quality issues"
            ]
        case .combine:
            [
                "Append these files and align matching columns",
                "Join these files using their shared ID column",
                "Combine everything and add the source filename"
            ]
        case .compare:
            [
                "Show added, removed, and changed records",
                "Compare totals between the two files",
                "Find IDs whose values changed by more than 10%"
            ]
        }
    }
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
    case noSources
    case needsMultipleSources(DataWorkspaceMode)
    case noSharedColumns
    case noComparisonKey
    case unsafeQuery(String)
    case invalidAIResponse

    var errorDescription: String? {
        switch self {
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
