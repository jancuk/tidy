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

struct JiraStandupPostResult {
    let postedIssueIDs: Set<String>
    let errorsByIssueKey: [String: String]
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
                fields: [
                    "summary", "status", "priority", "assignee", "issuetype",
                    "description", "created", "updated", "resolutiondate"
                ],
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

    func assignableUsers(for issueKey: String, matching query: String) async throws -> [JiraUser] {
        let encodedKey = issueKey.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? issueKey
        let request = try makeRequest(
            path: "/rest/api/3/user/assignable/search",
            queryItems: [
                URLQueryItem(name: "issueKey", value: encodedKey),
                URLQueryItem(name: "query", value: query),
                URLQueryItem(name: "startAt", value: "0"),
                URLQueryItem(name: "maxResults", value: "8")
            ]
        )
        let data = try await perform(request, expectedStatus: 200)
        do {
            return try JSONDecoder().decode([JiraUser].self, from: data)
        } catch {
            throw JiraServiceError.invalidResponse
        }
    }

    func addComment(
        _ text: String,
        to issueKey: String,
        mentions: [JiraUser] = [],
        dates: [JiraCommentDateToken] = []
    ) async throws -> JiraComment {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw JiraServiceError.invalidResponse }

        let encodedKey = issueKey.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? issueKey
        var request = try makeRequest(path: "/rest/api/3/issue/\(encodedKey)/comment", method: "POST")
        request.httpBody = try JSONEncoder().encode(
            JiraCommentRequest(text: trimmed, mentions: mentions, dates: dates)
        )
        let data = try await perform(request, expectedStatus: 201)
        do {
            return try JSONDecoder().decode(JiraComment.self, from: data)
        } catch {
            throw JiraServiceError.invalidResponse
        }
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

    func transitions(for issueKey: String) async throws -> [JiraTransition] {
        let encodedKey = issueKey.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? issueKey
        let request = try makeRequest(path: "/rest/api/3/issue/\(encodedKey)/transitions")
        let data = try await perform(request, expectedStatus: 200)
        do {
            return try JSONDecoder().decode(JiraTransitionsResponse.self, from: data).transitions
        } catch {
            throw JiraServiceError.invalidResponse
        }
    }

    func recentComments(for issueKey: String, maxResults: Int = 50) async throws -> [JiraComment] {
        let encodedKey = issueKey.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? issueKey
        let request = try makeRequest(
            path: "/rest/api/3/issue/\(encodedKey)/comment",
            queryItems: [
                URLQueryItem(name: "startAt", value: "0"),
                URLQueryItem(name: "maxResults", value: String(maxResults)),
                URLQueryItem(name: "orderBy", value: "-created")
            ]
        )
        let data = try await perform(request, expectedStatus: 200)
        do {
            return try JSONDecoder().decode(JiraCommentsResponse.self, from: data).comments
        } catch {
            throw JiraServiceError.invalidResponse
        }
    }

    func standupUpdates(
        for issues: [JiraIssue],
        on date: Date = Date(),
        calendar: Calendar = .current,
        batchSize: Int = 8
    ) async -> [JiraStandupUpdate] {
        var updates: [JiraStandupUpdate] = []
        let candidates = issues
            .filter { issue in
                guard let updatedDate = issue.updatedDate else { return false }
                return calendar.isDate(updatedDate, inSameDayAs: date)
            }
            .sorted { ($0.updatedDate ?? .distantPast) > ($1.updatedDate ?? .distantPast) }

        for start in stride(from: 0, to: candidates.count, by: batchSize) {
            let end = min(start + batchSize, candidates.count)
            let batch = Array(candidates[start..<end])
            let batchUpdates = await withTaskGroup(of: [JiraStandupUpdate].self) { group in
                for issue in batch {
                    group.addTask {
                        let comments = (try? await recentComments(for: issue.key)) ?? []
                        return comments.compactMap { comment in
                            JiraStandupUpdate(comment: comment, issue: issue)
                        }
                        .filter { $0.isOnSameDay(as: date) }
                    }
                }

                var found: [JiraStandupUpdate] = []
                for await issueUpdates in group {
                    found.append(contentsOf: issueUpdates)
                }
                return found
            }
            updates.append(contentsOf: batchUpdates)
        }

        return updates.sorted { $0.createdAt > $1.createdAt }
    }

    func transition(_ issueKey: String, using transitionID: String) async throws {
        let encodedKey = issueKey.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? issueKey
        var request = try makeRequest(path: "/rest/api/3/issue/\(encodedKey)/transitions", method: "POST")
        request.httpBody = try Self.transitionBody(for: transitionID)
        _ = try await perform(request, expectedStatus: 204)
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
                        isFallback: false,
                        field: item.field,
                        fromValue: item.fromString,
                        toValue: item.toString
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

    static func commentBody(
        for text: String,
        mentions: [JiraUser],
        dates: [JiraCommentDateToken]
    ) throws -> Data {
        try JSONEncoder().encode(
            JiraCommentRequest(text: text, mentions: mentions, dates: dates)
        )
    }

    static func transitionBody(for transitionID: String) throws -> Data {
        try JSONEncoder().encode(JiraTransitionRequest(transition: .init(id: transitionID)))
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
                isFallback: true,
                field: nil,
                fromValue: nil,
                toValue: nil
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
        let (data, response) = try await SecureHTTP.data(
            for: request,
            session: session
        )
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
    @Published private(set) var transitionsByIssueID: [String: [JiraTransition]] = [:]
    @Published private(set) var loadingTransitionIssueIDs: Set<String> = []
    @Published private(set) var transitioningIssueIDs: Set<String> = []
    @Published private(set) var transitionErrorsByIssueID: [String: String] = [:]
    @Published private(set) var standupUpdates: [JiraStandupUpdate] = []
    @Published private(set) var isLoadingStandup = false
    @Published private(set) var postingStandupIssueIDs: Set<String> = []
    @Published private(set) var standupErrorMessage: String?
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

    func addComment(
        _ text: String,
        to issue: JiraIssue,
        mentions: [JiraUser] = [],
        dates: [JiraCommentDateToken] = []
    ) async throws {
        let configuration = try await completeConfiguration()
        _ = try await JiraAPIClient(configuration: configuration).addComment(
            text,
            to: issue.key,
            mentions: mentions,
            dates: dates
        )
        await loadComments(for: issue)
    }

    func searchMentionUsers(matching query: String, for issue: JiraIssue) async throws -> [JiraUser] {
        let configuration = try await completeConfiguration()
        return try await JiraAPIClient(configuration: configuration)
            .assignableUsers(for: issue.key, matching: query)
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

    func loadTransitions(for issue: JiraIssue) async {
        loadingTransitionIssueIDs.insert(issue.id)
        transitionErrorsByIssueID[issue.id] = nil
        defer { loadingTransitionIssueIDs.remove(issue.id) }

        do {
            let client = JiraAPIClient(configuration: try await completeConfiguration())
            transitionsByIssueID[issue.id] = try await client.transitions(for: issue.key)
        } catch {
            transitionErrorsByIssueID[issue.id] = error.localizedDescription
        }
    }

    func transition(_ issue: JiraIssue, using transition: JiraTransition) async throws {
        transitioningIssueIDs.insert(issue.id)
        transitionErrorsByIssueID[issue.id] = nil
        defer { transitioningIssueIDs.remove(issue.id) }

        do {
            let client = JiraAPIClient(configuration: try await completeConfiguration())
            try await client.transition(issue.key, using: transition.id)
            if let index = issues.firstIndex(where: { $0.id == issue.id }) {
                issues[index] = issues[index].replacingStatus(with: transition.to)
            }
            await loadTransitions(for: issue.replacingStatus(with: transition.to))
        } catch {
            transitionErrorsByIssueID[issue.id] = error.localizedDescription
            throw error
        }
    }

    func transitions(for issue: JiraIssue) -> [JiraTransition] {
        transitionsByIssueID[issue.id] ?? []
    }

    func loadStandupUpdates(for issues: [JiraIssue], on date: Date = Date()) async {
        isLoadingStandup = true
        standupErrorMessage = nil
        defer { isLoadingStandup = false }

        do {
            let client = JiraAPIClient(configuration: try await completeConfiguration())
            standupUpdates = await client.standupUpdates(for: issues, on: date)
        } catch {
            standupErrorMessage = error.localizedDescription
        }
    }

    func postStandup(
        drafts: [JiraStandupDraft],
        for issues: [JiraIssue],
        mentionsByIssueID: [String: [JiraUser]] = [:],
        datesByIssueID: [String: [JiraCommentDateToken]] = [:],
        on date: Date = Date()
    ) async throws -> JiraStandupPostResult {
        let issueByID = Dictionary(uniqueKeysWithValues: issues.map { ($0.id, $0) })
        let selected = drafts.filter {
            $0.isIncluded && !$0.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !selected.isEmpty else {
            return JiraStandupPostResult(postedIssueIDs: [], errorsByIssueKey: [:])
        }

        let client = JiraAPIClient(configuration: try await completeConfiguration())
        var postedIssueIDs: Set<String> = []
        var errorsByIssueKey: [String: String] = [:]

        for draft in selected {
            guard let issue = issueByID[draft.issueID] else { continue }
            postingStandupIssueIDs.insert(issue.id)
            let text = JiraStandupUpdate.commentText(
                state: draft.state,
                note: draft.note,
                date: date
            )
            do {
                let comment = try await client.addComment(
                    text,
                    to: issue.key,
                    mentions: mentionsByIssueID[issue.id] ?? [],
                    dates: datesByIssueID[issue.id] ?? []
                )
                if let update = JiraStandupUpdate(comment: comment, issue: issue) {
                    standupUpdates.removeAll { $0.id == update.id }
                    standupUpdates.insert(update, at: 0)
                }
                commentsByIssueID[issue.id, default: []].append(comment)
                postedIssueIDs.insert(issue.id)
            } catch {
                errorsByIssueKey[issue.key] = error.localizedDescription
            }
            postingStandupIssueIDs.remove(issue.id)
        }

        return JiraStandupPostResult(
            postedIssueIDs: postedIssueIDs,
            errorsByIssueKey: errorsByIssueKey
        )
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

private struct JiraTransitionsResponse: Decodable {
    let transitions: [JiraTransition]
}

private struct JiraTransitionRequest: Encodable {
    let transition: Transition

    struct Transition: Encodable {
        let id: String
    }
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

    init(
        text: String,
        mentions: [JiraUser] = [],
        dates: [JiraCommentDateToken] = []
    ) {
        body = Document(
            version: 1,
            type: "doc",
            content: text.components(separatedBy: .newlines).map {
                Paragraph(
                    type: "paragraph",
                    content: Self.inlineNodes(in: $0, mentions: mentions, dates: dates)
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
        let content: [InlineNode]
    }

    struct InlineNode: Encodable {
        let type: String
        let text: String?
        let attrs: Attributes?

        static func text(_ value: String) -> InlineNode {
            InlineNode(type: "text", text: value, attrs: nil)
        }

        static func mention(_ user: JiraUser) -> InlineNode {
            InlineNode(
                type: "mention",
                text: nil,
                attrs: Attributes(
                    id: user.accountId,
                    text: "@\(user.displayName)",
                    userType: "DEFAULT",
                    timestamp: nil
                )
            )
        }

        static func date(_ token: JiraCommentDateToken) -> InlineNode {
            InlineNode(
                type: "date",
                text: nil,
                attrs: Attributes(
                    id: nil,
                    text: nil,
                    userType: nil,
                    timestamp: String(Int(token.date.timeIntervalSince1970 * 1_000))
                )
            )
        }
    }

    struct Attributes: Encodable {
        let id: String?
        let text: String?
        let userType: String?
        let timestamp: String?
    }

    private enum Match {
        case mention(JiraUser)
        case date(JiraCommentDateToken)
    }

    private static func inlineNodes(
        in line: String,
        mentions: [JiraUser],
        dates: [JiraCommentDateToken]
    ) -> [InlineNode] {
        guard !line.isEmpty else { return [] }
        var remaining = line[...]
        var nodes: [InlineNode] = []

        while !remaining.isEmpty {
            var bestRange: Range<Substring.Index>?
            var bestMatch: Match?
            var bestDistance = Int.max
            var bestMarkerLength = 0

            for user in mentions {
                let marker = "@\(user.displayName)"
                guard let range = remaining.range(of: marker) else { continue }
                let distance = remaining.distance(from: remaining.startIndex, to: range.lowerBound)
                if distance < bestDistance || (distance == bestDistance && marker.count > bestMarkerLength) {
                    bestRange = range
                    bestMatch = .mention(user)
                    bestDistance = distance
                    bestMarkerLength = marker.count
                }
            }

            for token in dates {
                guard let range = remaining.range(of: token.marker) else { continue }
                let distance = remaining.distance(from: remaining.startIndex, to: range.lowerBound)
                if distance < bestDistance || (distance == bestDistance && token.marker.count > bestMarkerLength) {
                    bestRange = range
                    bestMatch = .date(token)
                    bestDistance = distance
                    bestMarkerLength = token.marker.count
                }
            }

            guard let range = bestRange, let match = bestMatch else {
                nodes.append(.text(String(remaining)))
                break
            }

            let prefix = String(remaining[..<range.lowerBound])
            if !prefix.isEmpty { nodes.append(.text(prefix)) }
            switch match {
            case .mention(let user):
                nodes.append(.mention(user))
            case .date(let token):
                nodes.append(.date(token))
            }
            remaining = remaining[range.upperBound...]
        }

        return nodes
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
