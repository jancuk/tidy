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
        let description: JiraADFNode?
        let created: String?
        let updated: String?
        let resolutionDate: String?

        enum CodingKeys: String, CodingKey {
            case summary
            case status
            case priority
            case assignee
            case issueType = "issuetype"
            case description
            case created
            case updated
            case resolutionDate = "resolutiondate"
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

    var createdDate: Date? { JiraDateParser.date(from: fields.created) }
    var updatedDate: Date? { JiraDateParser.date(from: fields.updated) }
    var resolutionDate: Date? { JiraDateParser.date(from: fields.resolutionDate) }

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

    func replacingStatus(with status: NamedField) -> JiraIssue {
        JiraIssue(
            id: id,
            key: key,
            fields: Fields(
                summary: fields.summary,
                status: status,
                priority: fields.priority,
                assignee: fields.assignee,
                issueType: fields.issueType,
                description: fields.description,
                created: fields.created,
                updated: fields.updated,
                resolutionDate: fields.resolutionDate
            )
        )
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

struct JiraTransition: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let to: JiraIssue.NamedField
}

struct JiraUser: Decodable, Equatable, Identifiable {
    let accountId: String
    let displayName: String
    let emailAddress: String?

    var id: String { accountId }
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

enum JiraStandupState: String, Codable, CaseIterable, Identifiable {
    case ongoing = "Ongoing"
    case blocked = "Blocked"
    case done = "Done"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .ongoing: "arrow.triangle.2.circlepath"
        case .blocked: "exclamationmark.octagon.fill"
        case .done: "checkmark.circle.fill"
        }
    }
}

struct JiraStandupDraft: Codable, Identifiable, Equatable {
    let issueID: String
    var state: JiraStandupState
    var note: String
    var isIncluded: Bool

    var id: String { issueID }
}

struct JiraStandupUpdate: Identifiable, Equatable {
    static let marker = "Tidy Standup"

    let id: String
    let issueID: String
    let issueKey: String
    let issueSummary: String
    let authorAccountID: String?
    let authorName: String
    let state: JiraStandupState
    let note: String
    let createdAt: Date

    init?(
        comment: JiraComment,
        issue: JiraIssue
    ) {
        let lines = comment.text.components(separatedBy: .newlines)
        guard lines.first?.hasPrefix(Self.marker) == true,
              let statusLine = lines.first(where: { $0.hasPrefix("Status: ") }),
              let state = JiraStandupState(rawValue: String(statusLine.dropFirst("Status: ".count))),
              let updateLine = lines.first(where: { $0.hasPrefix("Update: ") }),
              let createdAt = comment.createdDate else {
            return nil
        }

        id = comment.id
        issueID = issue.id
        issueKey = issue.key
        issueSummary = issue.fields.summary
        authorAccountID = comment.author.accountId
        authorName = comment.author.displayName
        self.state = state
        note = String(updateLine.dropFirst("Update: ".count))
        self.createdAt = createdAt
    }

    static func commentText(
        state: JiraStandupState,
        note: String,
        date: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let day = String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
        return """
        \(marker) · \(day)
        Status: \(state.rawValue)
        Update: \(note.trimmingCharacters(in: .whitespacesAndNewlines))
        """
    }

    func isOnSameDay(as date: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(createdAt, inSameDayAs: date)
    }
}

struct JiraADFNode: Decodable, Equatable {
    let type: String?
    let text: String?
    let content: [JiraADFNode]?
    let attrs: Attributes?

    struct Attributes: Decodable, Equatable {
        let id: String?
        let text: String?
        let timestamp: String?
    }

    var plainText: String {
        if type == "hardBreak" { return "\n" }
        if type == "mention" { return attrs?.text ?? "Mention" }
        if type == "date",
           let timestamp = attrs?.timestamp,
           let rawTimestamp = TimeInterval(timestamp) {
            let seconds = rawTimestamp > 10_000_000_000 ? rawTimestamp / 1_000 : rawTimestamp
            return Date(timeIntervalSince1970: seconds).formatted(date: .abbreviated, time: .omitted)
        }
        if let text { return text }
        let joined = (content ?? []).map(\.plainText).joined()
        return type == "paragraph" ? joined + "\n" : joined
    }
}

struct JiraCommentDateToken: Identifiable, Equatable {
    let id: UUID
    let date: Date
    let marker: String

    init(id: UUID = UUID(), date: Date) {
        self.id = id
        self.date = date
        marker = date.formatted(date: .abbreviated, time: .omitted)
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
    let field: String?
    let fromValue: String?
    let toValue: String?
}

struct JiraSprintAnalytics: Equatable {
    let total: Int
    let completed: Int
    let active: Int
    let inReview: Int
    let inQA: Int
    let readyForRelease: Int
    let highPriority: Int
    let unassigned: Int
    let aging: Int
    let completedRecently: Int
    let statusCounts: [JiraStatusCount]
    let team: [JiraTeamFlowMember]
    let attentionIssues: [JiraIssue]

    var completionRate: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }

    init(
        issues: [JiraIssue],
        notifications: [JiraNotification],
        now: Date = Date(),
        agingThreshold: TimeInterval = 3 * 24 * 60 * 60
    ) {
        total = issues.count
        completed = issues.filter(\.isCompleted).count
        active = issues.filter { !$0.isCompleted && !$0.isToDo }.count
        inReview = issues.filter { JiraWorkflowStatus.codeReview.matches($0.fields.status.name) }.count
        inQA = issues.filter { JiraWorkflowStatus.inQA.matches($0.fields.status.name) }.count
        readyForRelease = issues.filter {
            JiraWorkflowStatus.readyForRelease.matches($0.fields.status.name)
        }.count
        highPriority = issues.filter(\.isHighPriority).count
        unassigned = issues.filter { $0.fields.assignee == nil }.count
        aging = issues.filter { $0.isAging(at: now, threshold: agingThreshold) }.count

        let recentCutoff = now.addingTimeInterval(-7 * 24 * 60 * 60)
        completedRecently = notifications.filter {
            $0.createdAt >= recentCutoff
                && $0.field?.caseInsensitiveCompare("status") == .orderedSame
                && (
                    JiraWorkflowStatus.readyForRelease.matches($0.toValue ?? "")
                        || JiraWorkflowStatus.doneReleaseReady.matches($0.toValue ?? "")
                )
        }.count

        statusCounts = JiraWorkflowStatus.allCases.map { status in
            JiraStatusCount(
                status: status,
                count: issues.filter { status.matches($0.fields.status.name) }.count
            )
        }

        let grouped = Dictionary(grouping: issues) { $0.fields.assignee?.displayName ?? "Unassigned" }
        team = grouped.map { name, memberIssues in
            JiraTeamFlowMember(
                name: name,
                assigned: memberIssues.count,
                active: memberIssues.filter { !$0.isCompleted && !$0.isToDo }.count,
                inReview: memberIssues.filter {
                    JiraWorkflowStatus.codeReview.matches($0.fields.status.name)
                }.count,
                inQA: memberIssues.filter {
                    JiraWorkflowStatus.inQA.matches($0.fields.status.name)
                }.count,
                completed: memberIssues.filter(\.isCompleted).count,
                atRisk: memberIssues.filter {
                    $0.isHighPriority || $0.isAging(at: now, threshold: agingThreshold)
                }.count
            )
        }
        .sorted {
            if $0.atRisk != $1.atRisk { return $0.atRisk > $1.atRisk }
            if $0.active != $1.active { return $0.active > $1.active }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        attentionIssues = issues
            .filter { !$0.isCompleted && ($0.isHighPriority || $0.isAging(at: now, threshold: agingThreshold) || $0.fields.assignee == nil) }
            .sorted {
                if $0.isHighPriority != $1.isHighPriority { return $0.isHighPriority }
                return ($0.updatedDate ?? .distantPast) < ($1.updatedDate ?? .distantPast)
            }
    }
}

struct JiraStatusCount: Identifiable, Equatable {
    let status: JiraWorkflowStatus
    let count: Int

    var id: JiraWorkflowStatus { status }
}

struct JiraTeamFlowMember: Identifiable, Equatable {
    let name: String
    let assigned: Int
    let active: Int
    let inReview: Int
    let inQA: Int
    let completed: Int
    let atRisk: Int

    var id: String { name }
}

extension JiraIssue {
    var isCompleted: Bool {
        statusGroup == .done
            || JiraWorkflowStatus.readyForRelease.matches(fields.status.name)
            || JiraWorkflowStatus.doneReleaseReady.matches(fields.status.name)
    }

    var isToDo: Bool {
        JiraWorkflowStatus.toDo.matches(fields.status.name) || statusGroup == .toDo
    }

    var isHighPriority: Bool {
        let value = fields.priority?.name.lowercased() ?? ""
        return value.contains("highest")
            || value.contains("blocker")
            || value.contains("critical")
            || value.contains("p0")
            || value.contains("high")
            || value.contains("p1")
    }

    func isAging(at now: Date, threshold: TimeInterval) -> Bool {
        guard !isCompleted, let updatedDate else { return false }
        return now.timeIntervalSince(updatedDate) >= threshold
    }
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
