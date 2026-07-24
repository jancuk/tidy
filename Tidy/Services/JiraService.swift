import Foundation

enum JiraServiceError: LocalizedError, Equatable {
    case incompleteConfiguration
    case invalidSiteURL
    case invalidProjectKey
    case invalidResponse
    case httpError(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .incompleteConfiguration:
            "Add your Jira site, email, and API token in Settings → Jira first."
        case .invalidSiteURL:
            "Enter a valid HTTPS Jira site URL, such as https://company.atlassian.net."
        case .invalidProjectKey:
            "Enter a Jira project key, such as ENG."
        case .invalidResponse:
            "Jira returned a response Tidy could not read."
        case .httpError(let status, let message):
            message.isEmpty ? "Jira request failed (HTTP \(status))." : "Jira request failed (HTTP \(status)): \(message)"
        }
    }
}

struct JiraAPIClient {
    let configuration: JiraConfiguration
    var session: URLSession = .shared

    func currentUser() async throws -> JiraUser {
        let request = try makeRequest(path: "/rest/api/3/myself")
        let data = try await perform(request, expectedStatus: 200)
        do {
            return try JSONDecoder().decode(JiraUser.self, from: data)
        } catch {
            throw JiraServiceError.invalidResponse
        }
    }

    func activeSprintIssues(projectKey: String, assigneeAccountID: String?) async throws -> [JiraIssue] {
        let project = projectKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !project.isEmpty else { throw JiraServiceError.invalidProjectKey }

        let jql = Self.activeSprintJQL(projectKey: project, assigneeAccountID: assigneeAccountID)
        var issues: [JiraIssue] = []
        var nextPageToken: String?

        repeat {
            let body = JiraSearchRequest(
                jql: jql,
                fields: ["summary", "status", "priority", "assignee", "issuetype", "updated"],
                maxResults: 100,
                nextPageToken: nextPageToken
            )
            var request = try makeRequest(path: "/rest/api/3/search/jql", method: "POST")
            request.httpBody = try JSONEncoder().encode(body)

            let data = try await perform(request, expectedStatus: 200)
            let page: JiraSearchResponse
            do {
                page = try JSONDecoder().decode(JiraSearchResponse.self, from: data)
            } catch {
                throw JiraServiceError.invalidResponse
            }
            issues.append(contentsOf: page.issues)
            let previousToken = nextPageToken
            nextPageToken = page.isLast == true ? nil : page.nextPageToken
            if nextPageToken == previousToken { nextPageToken = nil }
        } while nextPageToken != nil

        return issues
    }

    func comments(for issueKey: String) async throws -> [JiraComment] {
        let encodedKey = issueKey.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? issueKey
        var comments: [JiraComment] = []
        var startAt = 0
        var total = Int.max

        while startAt < total {
            let request = try makeRequest(
                path: "/rest/api/3/issue/\(encodedKey)/comment",
                queryItems: [
                    URLQueryItem(name: "startAt", value: String(startAt)),
                    URLQueryItem(name: "maxResults", value: "100"),
                    URLQueryItem(name: "orderBy", value: "created")
                ]
            )
            let data = try await perform(request, expectedStatus: 200)
            let page: JiraCommentsResponse
            do {
                page = try JSONDecoder().decode(JiraCommentsResponse.self, from: data)
            } catch {
                throw JiraServiceError.invalidResponse
            }
            comments.append(contentsOf: page.comments)
            total = page.total ?? comments.count
            guard !page.comments.isEmpty else { break }
            startAt += page.comments.count
        }
        return comments
    }

    func addComment(_ text: String, to issueKey: String) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let encodedKey = issueKey.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? issueKey
        var request = try makeRequest(path: "/rest/api/3/issue/\(encodedKey)/comment", method: "POST")
        request.httpBody = try JSONEncoder().encode(JiraCommentRequest(text: trimmed))
        _ = try await perform(request, expectedStatus: 201)
    }

    func updateComment(_ text: String, commentID: String, issueKey: String) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let encodedKey = issueKey.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? issueKey
        let encodedCommentID = commentID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? commentID
        var request = try makeRequest(
            path: "/rest/api/3/issue/\(encodedKey)/comment/\(encodedCommentID)",
            method: "PUT"
        )
        request.httpBody = try JSONEncoder().encode(JiraCommentRequest(text: trimmed))
        _ = try await perform(request, expectedStatus: 200)
    }

    func recentChanges(for issues: [JiraIssue]) async throws -> [JiraNotification] {
        guard !issues.isEmpty else { return [] }
        var request = try makeRequest(path: "/rest/api/3/changelog/bulkfetch", method: "POST")
        request.httpBody = try JSONEncoder().encode(JiraBulkChangelogRequest(
            issueIdsOrKeys: issues.map(\.key),
            fieldIds: ["status", "priority", "assignee"],
            maxResults: 500
        ))
        let data = try await perform(request, expectedStatus: 200)
        let response: JiraBulkChangelogResponse
        do {
            response = try JSONDecoder().decode(JiraBulkChangelogResponse.self, from: data)
        } catch {
            throw JiraServiceError.invalidResponse
        }

        let issueByID = Dictionary(uniqueKeysWithValues: issues.map { ($0.id, $0) })
        let allNotifications = response.issueChangeLogs.flatMap { issueLog -> [JiraNotification] in
            guard let issue = issueByID[issueLog.issueId] else { return [] }
            return issueLog.changeHistories.flatMap { history in
                history.items.map { item in
                    JiraNotification(
                        id: "\(issue.id)-\(history.id)-\(item.fieldId ?? item.field)",
                        issueID: issue.id,
                        issueKey: issue.key,
                        issueSummary: issue.fields.summary,
                        title: Self.changeTitle(for: item.field),
                        detail: Self.changeDetail(from: item.fromString, to: item.toString),
                        priority: issue.fields.priority?.name ?? "No priority",
                        status: issue.fields.status.name,
                        actor: history.author?.displayName,
                        createdAt: history.created.date,
                        isFallback: false
                    )
                }
            }
        }
        .sorted { $0.createdAt > $1.createdAt }

        let recentCutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        let recentNotifications = allNotifications.filter { $0.createdAt >= recentCutoff }
        return Array((recentNotifications.isEmpty ? allNotifications : recentNotifications).prefix(100))
    }

    func issueURL(for issueKey: String) throws -> URL {
        let root = try baseURL()
        return root.appending(path: "browse").appending(path: issueKey)
    }

    static func activeSprintJQL(projectKey: String, assigneeAccountID: String?) -> String {
        var clauses = [
            "project = \"\(escapeJQL(projectKey))\"",
            "sprint in openSprints()"
        ]
        if let assignee = assigneeAccountID?.trimmingCharacters(in: .whitespacesAndNewlines), !assignee.isEmpty {
            clauses.append("assignee = \"\(escapeJQL(assignee))\"")
        }
        return clauses.joined(separator: " AND ") + " ORDER BY priority DESC, updated DESC"
    }

    static func commentBody(for text: String) throws -> Data {
        try JSONEncoder().encode(JiraCommentRequest(text: text))
    }

    static func fallbackNotifications(for issues: [JiraIssue]) -> [JiraNotification] {
        issues.compactMap { issue in
            guard let updated = issue.updatedDate else { return nil }
            return JiraNotification(
                id: "updated-\(issue.id)-\(Int(updated.timeIntervalSince1970))",
                issueID: issue.id,
                issueKey: issue.key,
                issueSummary: issue.fields.summary,
                title: "Ticket updated",
                detail: "\(issue.fields.status.name) · \(issue.fields.priority?.name ?? "No priority")",
                priority: issue.fields.priority?.name ?? "No priority",
                status: issue.fields.status.name,
                actor: nil,
                createdAt: updated,
                isFallback: true
            )
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    private static func escapeJQL(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func changeTitle(for field: String) -> String {
        switch field.lowercased() {
        case "status": "Status changed"
        case "priority": "Priority changed"
        case "assignee": "Assignee changed"
        default: "\(field.capitalized) changed"
        }
    }

    private static func changeDetail(from: String?, to: String?) -> String {
        let oldValue = from?.nilIfBlank ?? "None"
        let newValue = to?.nilIfBlank ?? "None"
        return "\(oldValue) → \(newValue)"
    }

    private func makeRequest(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = []
    ) throws -> URLRequest {
        guard configuration.isComplete else { throw JiraServiceError.incompleteConfiguration }
        let pathURL = try baseURL().appending(path: path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        guard var components = URLComponents(url: pathURL, resolvingAgainstBaseURL: false) else {
            throw JiraServiceError.invalidSiteURL
        }
        if !queryItems.isEmpty { components.queryItems = queryItems }
        guard let url = components.url else { throw JiraServiceError.invalidSiteURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let credentials = Data("\(configuration.email):\(configuration.apiToken)".utf8).base64EncodedString()
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func baseURL() throws -> URL {
        var raw = configuration.siteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while raw.hasSuffix("/") { raw.removeLast() }
        if !raw.contains("://") { raw = "https://\(raw)" }
        guard let components = URLComponents(string: raw),
              components.scheme?.lowercased() == "https",
              components.host != nil,
              let url = components.url else {
            throw JiraServiceError.invalidSiteURL
        }
        return url
    }

    private func perform(_ request: URLRequest, expectedStatus: Int) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw JiraServiceError.invalidResponse }
        guard http.statusCode == expectedStatus else {
            throw JiraServiceError.httpError(status: http.statusCode, message: Self.errorMessage(from: data))
        }
        return data
    }

    private static func errorMessage(from data: Data) -> String {
        guard let payload = try? JSONDecoder().decode(JiraErrorResponse.self, from: data) else {
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        let fieldErrors = payload.errors?.values.sorted().joined(separator: " ") ?? ""
        return (payload.errorMessages ?? []).joined(separator: " ") + (fieldErrors.isEmpty ? "" : " \(fieldErrors)")
    }
}

@MainActor
final class JiraService: ObservableObject {
    @Published private(set) var issues: [JiraIssue] = []
    @Published private(set) var notifications: [JiraNotification] = []
    @Published private(set) var unreadNotificationIDs: Set<String> = []
    @Published private(set) var commentsByIssueID: [String: [JiraComment]] = [:]
    @Published private(set) var loadingCommentIssueIDs: Set<String> = []
    @Published private(set) var commentErrorsByIssueID: [String: String] = [:]
    @Published private(set) var currentUser: JiraUser?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var configurationRevision = 0
    @Published private(set) var requestedIssueID: String?
    @Published private(set) var notificationCenterRequest = 0
    @Published private(set) var isConfigured: Bool
    private var cachedConfiguration: JiraConfiguration?
    private var configurationTask: Task<JiraConfiguration, Never>?

    var unreadCount: Int { unreadNotificationIDs.count }

    init() {
        isConfigured = JiraConfiguration.accountMetadata.hasAccountMetadata
    }

    func configurationDidChange() {
        cachedConfiguration = nil
        configurationTask = nil
        isConfigured = JiraConfiguration.accountMetadata.hasAccountMetadata
        configurationRevision += 1
        Task { await refreshConfigurationStatus() }
    }

    @discardableResult
    func refreshConfigurationStatus() async -> Bool {
        let configuration = await loadConfiguration()
        isConfigured = configuration.isComplete
        return isConfigured
    }

    func loadActiveSprintIssues(projectKey: String, assigneeAccountID: String?) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let client = JiraAPIClient(configuration: try await completeConfiguration())
            let fetchedIssues = try await client.activeSprintIssues(
                projectKey: projectKey,
                assigneeAccountID: assigneeAccountID
            )
            issues = fetchedIssues
            if currentUser == nil { currentUser = try? await client.currentUser() }
            notifications = (try? await client.recentChanges(for: fetchedIssues))
                ?? JiraAPIClient.fallbackNotifications(for: fetchedIssues)
            updateUnreadNotifications()
            lastUpdated = Date()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func testConnection() async throws -> JiraUser {
        let configuration = try await completeConfiguration()
        let user = try await JiraAPIClient(configuration: configuration).currentUser()
        currentUser = user
        return user
    }

    func addComment(_ text: String, to issue: JiraIssue) async throws {
        let configuration = try await completeConfiguration()
        try await JiraAPIClient(configuration: configuration).addComment(text, to: issue.key)
        await loadComments(for: issue)
    }

    func updateComment(_ text: String, comment: JiraComment, on issue: JiraIssue) async throws {
        let configuration = try await completeConfiguration()
        try await JiraAPIClient(configuration: configuration).updateComment(
            text,
            commentID: comment.id,
            issueKey: issue.key
        )
        await loadComments(for: issue)
    }

    func loadComments(for issue: JiraIssue) async {
        loadingCommentIssueIDs.insert(issue.id)
        commentErrorsByIssueID[issue.id] = nil
        defer { loadingCommentIssueIDs.remove(issue.id) }

        do {
            let client = JiraAPIClient(configuration: try await completeConfiguration())
            if currentUser == nil { currentUser = try? await client.currentUser() }
            commentsByIssueID[issue.id] = try await client.comments(for: issue.key)
        } catch {
            commentErrorsByIssueID[issue.id] = error.localizedDescription
        }
    }

    func comments(for issue: JiraIssue) -> [JiraComment] {
        commentsByIssueID[issue.id] ?? []
    }

    func requestIssue(_ issueID: String) {
        requestedIssueID = nil
        requestedIssueID = issueID
    }

    func requestNotificationCenter() {
        notificationCenterRequest += 1
    }

    func markNotificationRead(_ notification: JiraNotification) {
        unreadNotificationIDs.remove(notification.id)
    }

    func markAllNotificationsRead() {
        unreadNotificationIDs.removeAll()
        UserDefaults.standard.set(Date(), forKey: AppDefaults.jiraNotificationsLastSeenAt)
    }

    func issueURL(for issue: JiraIssue) -> URL? {
        try? JiraAPIClient(configuration: .accountMetadata).issueURL(for: issue.key)
    }

    private func loadConfiguration() async -> JiraConfiguration {
        if let cachedConfiguration { return cachedConfiguration }
        if let configurationTask { return await configurationTask.value }

        let task = Task.detached(priority: .userInitiated) {
            JiraConfiguration.current
        }
        configurationTask = task
        let configuration = await task.value
        configurationTask = nil
        if configuration.isComplete { cachedConfiguration = configuration }
        return configuration
    }

    private func completeConfiguration() async throws -> JiraConfiguration {
        let configuration = await loadConfiguration()
        isConfigured = configuration.isComplete
        guard configuration.isComplete else { throw JiraServiceError.incompleteConfiguration }
        return configuration
    }

    private func updateUnreadNotifications() {
        guard let lastSeen = UserDefaults.standard.object(forKey: AppDefaults.jiraNotificationsLastSeenAt) as? Date else {
            UserDefaults.standard.set(Date(), forKey: AppDefaults.jiraNotificationsLastSeenAt)
            unreadNotificationIDs = []
            return
        }
        unreadNotificationIDs = Set(notifications.filter { $0.createdAt > lastSeen }.map(\.id))
    }
}

private struct JiraSearchRequest: Encodable {
    let jql: String
    let fields: [String]
    let maxResults: Int
    let nextPageToken: String?
}

private struct JiraSearchResponse: Decodable {
    let issues: [JiraIssue]
    let nextPageToken: String?
    let isLast: Bool?
}

private struct JiraCommentsResponse: Decodable {
    let comments: [JiraComment]
    let total: Int?
}

private struct JiraBulkChangelogRequest: Encodable {
    let issueIdsOrKeys: [String]
    let fieldIds: [String]
    let maxResults: Int
}

private struct JiraBulkChangelogResponse: Decodable {
    let issueChangeLogs: [IssueChangeLog]

    struct IssueChangeLog: Decodable {
        let issueId: String
        let changeHistories: [ChangeHistory]
    }

    struct ChangeHistory: Decodable {
        let id: String
        let author: JiraComment.Author?
        let created: JiraFlexibleTimestamp
        let items: [ChangeItem]
    }

    struct ChangeItem: Decodable {
        let field: String
        let fieldId: String?
        let fromString: String?
        let toString: String?
    }
}

private struct JiraFlexibleTimestamp: Decodable {
    let date: Date

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self), let parsed = JiraDateParser.date(from: value) {
            date = parsed
            return
        }
        if let value = try? container.decode(Double.self) {
            date = Date(timeIntervalSince1970: value > 10_000_000_000 ? value / 1_000 : value)
            return
        }
        date = .distantPast
    }
}

private struct JiraCommentRequest: Encodable {
    let body: Document

    init(text: String) {
        body = Document(
            version: 1,
            type: "doc",
            content: text.components(separatedBy: .newlines).map {
                Paragraph(
                    type: "paragraph",
                    content: $0.isEmpty ? [] : [TextNode(type: "text", text: $0)]
                )
            }
        )
    }

    struct Document: Encodable {
        let version: Int
        let type: String
        let content: [Paragraph]
    }

    struct Paragraph: Encodable {
        let type: String
        let content: [TextNode]
    }

    struct TextNode: Encodable {
        let type: String
        let text: String
    }
}

private struct JiraErrorResponse: Decodable {
    let errorMessages: [String]?
    let errors: [String: String]?
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
