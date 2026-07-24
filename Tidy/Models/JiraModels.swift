import Foundation

struct JiraIssue: Decodable, Identifiable, Equatable {
    let id: String
    let key: String
    let fields: Fields

    struct Fields: Decodable, Equatable {
        let summary: String
        let status: NamedField
        let priority: NamedField?
        let assignee: User?
        let issueType: NamedField
        let updated: String?

        enum CodingKeys: String, CodingKey {
            case summary
            case status
            case priority
            case assignee
            case issueType = "issuetype"
            case updated
        }
    }

    struct NamedField: Decodable, Equatable {
        let name: String
        let statusCategory: StatusCategory?
    }

    struct StatusCategory: Decodable, Equatable {
        let key: String
        let name: String?
        let colorName: String?
    }

    struct User: Decodable, Equatable {
        let accountId: String?
        let displayName: String
    }

    var updatedDate: Date? { JiraDateParser.date(from: fields.updated) }

    var statusGroup: JiraStatusGroup {
        if let key = fields.status.statusCategory?.key {
            switch key.lowercased() {
            case "new": return .toDo
            case "indeterminate": return .inProgress
            case "done": return .done
            default: break
            }
        }

        let name = fields.status.name.lowercased()
        if name.contains("done") || name.contains("closed") || name.contains("resolved") || name.contains("reject") {
            return .done
        }
        if name.contains("progress") || name.contains("review") || name.contains("test") {
            return .inProgress
        }
        return .toDo
    }
}

enum JiraStatusGroup: String, CaseIterable, Identifiable {
    case all = "All"
    case toDo = "To do"
    case inProgress = "In progress"
    case done = "Done"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .all: "square.grid.2x2"
        case .toDo: "circle"
        case .inProgress: "circle.lefthalf.filled"
        case .done: "checkmark.circle.fill"
        }
    }
}

enum JiraWorkflowStatus: String, CaseIterable, Identifiable {
    case toDo = "To Do"
    case codeReview = "Code Review"
    case readyForRelease = "Ready for Release"
    case doneReleaseReady = "Done/Release Ready"
    case inQA = "In QA"
    case inProgress = "In Progress"

    var id: String { rawValue }

    func matches(_ jiraStatusName: String) -> Bool {
        jiraStatusName.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare(rawValue) == .orderedSame
    }
}

struct JiraUser: Decodable, Equatable {
    let accountId: String
    let displayName: String
    let emailAddress: String?
}

struct JiraComment: Decodable, Identifiable, Equatable {
    let id: String
    let author: Author
    let body: JiraADFNode
    let created: String
    let updated: String

    struct Author: Decodable, Equatable {
        let accountId: String?
        let displayName: String
    }

    var text: String { body.plainText.trimmingCharacters(in: .whitespacesAndNewlines) }
    var createdDate: Date? { JiraDateParser.date(from: created) }
    var updatedDate: Date? { JiraDateParser.date(from: updated) }
    var wasEdited: Bool { created != updated }
}

struct JiraADFNode: Decodable, Equatable {
    let type: String?
    let text: String?
    let content: [JiraADFNode]?

    var plainText: String {
        if type == "hardBreak" { return "\n" }
        if let text { return text }
        let joined = (content ?? []).map(\.plainText).joined()
        return type == "paragraph" ? joined + "\n" : joined
    }
}

struct JiraNotification: Identifiable, Equatable {
    let id: String
    let issueID: String
    let issueKey: String
    let issueSummary: String
    let title: String
    let detail: String
    let priority: String
    let status: String
    let actor: String?
    let createdAt: Date
    let isFallback: Bool
}

enum JiraDateParser {
    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let standardFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func date(from value: String?) -> Date? {
        guard let value else { return nil }
        if let date = fractionalFormatter.date(from: value) ?? standardFormatter.date(from: value) {
            return date
        }

        // Jira commonly returns offsets as +0000 instead of +00:00.
        guard value.count > 5 else { return nil }
        let offsetIndex = value.index(value.endIndex, offsetBy: -5)
        let offset = value[offsetIndex...]
        guard offset.first == "+" || offset.first == "-" else { return nil }
        let normalized = value[..<value.index(value.endIndex, offsetBy: -2)] + ":" + value[value.index(value.endIndex, offsetBy: -2)...]
        return fractionalFormatter.date(from: String(normalized)) ?? standardFormatter.date(from: String(normalized))
    }
}

struct JiraConfiguration: Equatable {
    static let tokenKey = "jira-api-token"

    let siteURL: String
    let email: String
    let apiToken: String

    static var accountMetadata: JiraConfiguration {
        JiraConfiguration(
            siteURL: UserDefaults.standard.string(forKey: AppDefaults.jiraSiteURL) ?? "",
            email: UserDefaults.standard.string(forKey: AppDefaults.jiraEmail) ?? "",
            apiToken: ""
        )
    }

    static var current: JiraConfiguration {
        var configuration = accountMetadata
        configuration = JiraConfiguration(
            siteURL: configuration.siteURL,
            email: configuration.email,
            apiToken: KeychainStore.read(key: tokenKey) ?? ""
        )
        return configuration
    }

    var isComplete: Bool {
        hasAccountMetadata
            && !apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasAccountMetadata: Bool {
        !siteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
