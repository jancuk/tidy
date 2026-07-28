import AppKit
import CryptoKit
import Foundation

enum AsanaServiceError: LocalizedError, Equatable {
    case missingCredentials
    case authorizationNotStarted
    case missingAuthorizationCode
    case missingWorkspace
    case unauthorized
    case invalidResponse
    case oauthError(String)
    case httpError(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            "Enter the Asana Client ID and Client Secret in Settings → Asana, then connect your account."
        case .authorizationNotStarted:
            "Click Connect with Asana before entering the authorization code."
        case .missingAuthorizationCode:
            "Paste the authorization code shown by Asana."
        case .missingWorkspace:
            "Choose an Asana workspace in Settings → Asana first."
        case .unauthorized:
            "Asana authorization expired or was revoked. Connect your Asana account again."
        case .invalidResponse:
            "Asana returned a response Tidy could not read."
        case .oauthError(let message):
            message
        case .httpError(let status, let message):
            message.isEmpty ? "Asana request failed with HTTP \(status)." : "Asana: \(message)"
        }
    }
}

struct AsanaOAuthAuthorization: Equatable {
    let url: URL
    let codeVerifier: String
}

struct AsanaOAuthClient {
    static let redirectURI = "urn:ietf:wg:oauth:2.0:oob"
    static let requiredScopes = [
        "tasks:read",
        "tasks:write",
        "workspaces:read"
    ]

    private let session: URLSession
    private let authorizeURL = URL(string: "https://app.asana.com/-/oauth_authorize")!
    private let tokenURL = URL(string: "https://app.asana.com/-/oauth_token")!

    init(session: URLSession = .shared) {
        self.session = session
    }

    func makeAuthorization(clientID: String) throws -> AsanaOAuthAuthorization {
        let trimmedClientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedClientID.isEmpty else {
            throw AsanaServiceError.missingCredentials
        }

        let verifier = Self.randomURLSafeString(byteCount: 48)
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let state = Self.randomURLSafeString(byteCount: 24)
        var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: trimmedClientID),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "scope", value: Self.requiredScopes.joined(separator: " "))
        ]
        guard let url = components.url else {
            throw AsanaServiceError.invalidResponse
        }
        return AsanaOAuthAuthorization(url: url, codeVerifier: verifier)
    }

    func exchangeAuthorizationCode(
        _ code: String,
        clientID: String,
        clientSecret: String,
        codeVerifier: String
    ) async throws -> AsanaOAuthTokenResponse {
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCode.isEmpty else {
            throw AsanaServiceError.missingAuthorizationCode
        }
        return try await requestToken([
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "client_id", value: clientID.trimmingCharacters(in: .whitespacesAndNewlines)),
            URLQueryItem(name: "client_secret", value: clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "code", value: trimmedCode),
            URLQueryItem(name: "code_verifier", value: codeVerifier)
        ])
    }

    func refreshAccessToken(
        _ refreshToken: String,
        clientID: String,
        clientSecret: String
    ) async throws -> AsanaOAuthTokenResponse {
        try await requestToken([
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "client_id", value: clientID.trimmingCharacters(in: .whitespacesAndNewlines)),
            URLQueryItem(name: "client_secret", value: clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)),
            URLQueryItem(name: "refresh_token", value: refreshToken)
        ])
    }

    private func requestToken(_ formItems: [URLQueryItem]) async throws -> AsanaOAuthTokenResponse {
        var bodyComponents = URLComponents()
        bodyComponents.queryItems = formItems
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = bodyComponents.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await SecureHTTP.data(
            for: request,
            session: session
        )
        guard let http = response as? HTTPURLResponse else {
            throw AsanaServiceError.invalidResponse
        }
        guard 200..<300 ~= http.statusCode else {
            let response = try? JSONDecoder().decode(AsanaOAuthErrorResponse.self, from: data)
            let detail = response?.errorDescription ?? response?.error
            throw AsanaServiceError.oauthError(
                detail.map { "Asana authorization failed: \($0)" }
                    ?? "Asana authorization failed with HTTP \(http.statusCode)."
            )
        }
        do {
            return try JSONDecoder().decode(AsanaOAuthTokenResponse.self, from: data)
        } catch {
            throw AsanaServiceError.invalidResponse
        }
    }

    private static func randomURLSafeString(byteCount: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status == errSecSuccess {
            return base64URL(Data(bytes))
        }
        return UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

struct AsanaAPIClient {
    private let token: String
    private let session: URLSession
    private let baseURL = URL(string: "https://app.asana.com/api/1.0")!

    init(token: String, session: URLSession = .shared) {
        self.token = token
        self.session = session
    }

    func workspaces() async throws -> [AsanaWorkspace] {
        let request = makeRequest(
            path: "/workspaces",
            queryItems: [
                URLQueryItem(name: "limit", value: "100"),
                URLQueryItem(name: "opt_fields", value: "gid,name")
            ]
        )
        let data = try await perform(request)
        return try decode(AsanaResponse<[AsanaWorkspace]>.self, from: data).data
    }

    func tasks(workspaceGID: String) async throws -> [AsanaTask] {
        var tasks: [AsanaTask] = []
        var offset: String?

        repeat {
            var queryItems = [
                URLQueryItem(name: "assignee", value: "me"),
                URLQueryItem(name: "workspace", value: workspaceGID),
                URLQueryItem(name: "completed_since", value: "now"),
                URLQueryItem(name: "limit", value: "100"),
                URLQueryItem(
                    name: "opt_fields",
                    value: "gid,name,completed,due_on,due_at,permalink_url,notes"
                )
            ]
            if let offset {
                queryItems.append(URLQueryItem(name: "offset", value: offset))
            }

            let data = try await perform(makeRequest(path: "/tasks", queryItems: queryItems))
            let page = try decode(AsanaResponse<[AsanaTask]>.self, from: data)
            tasks.append(contentsOf: page.data)
            offset = page.nextPage?.offset
        } while offset != nil

        return tasks
    }

    func setCompleted(_ completed: Bool, taskGID: String) async throws {
        let payload = ["data": ["completed": completed]]
        var request = makeRequest(path: "/tasks/\(taskGID)", method: "PUT")
        request.httpBody = try JSONEncoder().encode(payload)
        _ = try await perform(request)
    }

    private func makeRequest(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem] = []
    ) -> URLRequest {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await SecureHTTP.data(
            for: request,
            session: session
        )
        guard let http = response as? HTTPURLResponse else {
            throw AsanaServiceError.invalidResponse
        }
        guard 200..<300 ~= http.statusCode else {
            if http.statusCode == 401 {
                throw AsanaServiceError.unauthorized
            }
            let envelope = try? JSONDecoder().decode(AsanaErrorEnvelope.self, from: data)
            let message = envelope?.errors.map(\.message).joined(separator: " ") ?? ""
            throw AsanaServiceError.httpError(status: http.statusCode, message: message)
        }
        return data
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw AsanaServiceError.invalidResponse
        }
    }
}

@MainActor
final class AsanaService: ObservableObject {
    @Published private(set) var tasks: [AsanaTask] = []
    @Published private(set) var workspaces: [AsanaWorkspace] = []
    @Published private(set) var currentUser: AsanaUser?
    @Published private(set) var selectedWorkspaceGID: String
    @Published private(set) var isLoading = false
    @Published private(set) var updatingTaskIDs: Set<String> = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isConfigured: Bool
    @Published private(set) var isAuthorizationInProgress = false
    private var pendingCodeVerifier: String?

    init() {
        selectedWorkspaceGID = UserDefaults.standard.string(forKey: AppDefaults.asanaWorkspaceGID) ?? ""
        // Avoid reading Keychain during global app-state construction. Besides
        // keeping startup fast, this prevents test hosts and unsigned previews
        // from prompting for access to a credential before Asana is opened.
        isConfigured = false
    }

    func configurationDidChange() {
        selectedWorkspaceGID = UserDefaults.standard.string(forKey: AppDefaults.asanaWorkspaceGID) ?? ""
        isConfigured = AsanaConfiguration.current.isComplete
    }

    func startAuthorization(clientID: String) throws -> URL {
        let authorization = try AsanaOAuthClient().makeAuthorization(clientID: clientID)
        pendingCodeVerifier = authorization.codeVerifier
        isAuthorizationInProgress = true
        return authorization.url
    }

    func completeAuthorization(
        code: String,
        clientID: String,
        clientSecret: String
    ) async throws -> (AsanaUser?, [AsanaWorkspace]) {
        guard let codeVerifier = pendingCodeVerifier else {
            throw AsanaServiceError.authorizationNotStarted
        }
        let token = try await AsanaOAuthClient().exchangeAuthorizationCode(
            code,
            clientID: clientID,
            clientSecret: clientSecret,
            codeVerifier: codeVerifier
        )
        try saveOAuthToken(token)
        currentUser = token.user
        pendingCodeVerifier = nil
        isAuthorizationInProgress = false
        return try await testConnection()
    }

    func testConnection() async throws -> (AsanaUser?, [AsanaWorkspace]) {
        let client = AsanaAPIClient(token: try await validAccessToken())
        let availableWorkspaces = try await client.workspaces()
        workspaces = availableWorkspaces
        return (currentUser, availableWorkspaces)
    }

    func load() async {
        guard !isLoading else { return }
        let configuration = AsanaConfiguration.current
        guard configuration.hasAppCredentials, configuration.isAuthorized else {
            isConfigured = false
            errorMessage = AsanaServiceError.missingCredentials.localizedDescription
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let client = AsanaAPIClient(token: try await validAccessToken())
            workspaces = try await client.workspaces()

            if selectedWorkspaceGID.isEmpty
                || !workspaces.contains(where: { $0.gid == selectedWorkspaceGID }) {
                selectedWorkspaceGID = workspaces.first?.gid ?? ""
                UserDefaults.standard.set(selectedWorkspaceGID, forKey: AppDefaults.asanaWorkspaceGID)
            }
            guard !selectedWorkspaceGID.isEmpty else {
                throw AsanaServiceError.missingWorkspace
            }

            tasks = try await client.tasks(workspaceGID: selectedWorkspaceGID)
                .sorted(by: Self.taskSort)
            isConfigured = true
            lastUpdated = Date()
        } catch {
            errorMessage = error.localizedDescription
            isConfigured = AsanaConfiguration.current.isComplete
        }
    }

    func selectWorkspace(_ gid: String) async {
        guard gid != selectedWorkspaceGID else { return }
        selectedWorkspaceGID = gid
        UserDefaults.standard.set(gid, forKey: AppDefaults.asanaWorkspaceGID)
        isConfigured = AsanaConfiguration.current.isComplete
        await load()
    }

    func setCompleted(_ completed: Bool, task: AsanaTask) async {
        guard !updatingTaskIDs.contains(task.id) else { return }
        guard AsanaConfiguration.current.isComplete else {
            errorMessage = AsanaServiceError.missingWorkspace.localizedDescription
            return
        }

        updatingTaskIDs.insert(task.id)
        defer { updatingTaskIDs.remove(task.id) }

        do {
            let client = AsanaAPIClient(token: try await validAccessToken())
            try await client.setCompleted(completed, taskGID: task.gid)
            if completed {
                tasks.removeAll { $0.id == task.id }
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openInAsana(_ task: AsanaTask) {
        guard let rawURL = task.permalinkURL,
              let url = URL(string: rawURL),
              SecureHTTP.isSafeWebURL(url, allowedHosts: ["app.asana.com"]) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func validAccessToken() async throws -> String {
        var configuration = AsanaConfiguration.current
        guard configuration.hasAppCredentials, configuration.isAuthorized else {
            throw AsanaServiceError.missingCredentials
        }

        let expiresAt = UserDefaults.standard.double(forKey: AppDefaults.asanaTokenExpiresAt)
        guard expiresAt > 0, Date().timeIntervalSince1970 >= expiresAt - 60 else {
            return configuration.accessToken
        }
        guard !configuration.refreshToken.isEmpty else {
            throw AsanaServiceError.unauthorized
        }

        let token = try await AsanaOAuthClient().refreshAccessToken(
            configuration.refreshToken,
            clientID: configuration.clientID,
            clientSecret: configuration.clientSecret
        )
        try saveOAuthToken(token)
        configuration = AsanaConfiguration.current
        return configuration.accessToken
    }

    private func saveOAuthToken(_ token: AsanaOAuthTokenResponse) throws {
        try KeychainStore.save(token.accessToken, key: AsanaConfiguration.accessTokenKey)
        if let refreshToken = token.refreshToken, !refreshToken.isEmpty {
            try KeychainStore.save(refreshToken, key: AsanaConfiguration.refreshTokenKey)
        }
        UserDefaults.standard.set(
            Date().addingTimeInterval(token.expiresIn).timeIntervalSince1970,
            forKey: AppDefaults.asanaTokenExpiresAt
        )
        KeychainStore.delete(key: AsanaConfiguration.legacyTokenKey)
        isConfigured = AsanaConfiguration.current.isComplete
    }

    private static func taskSort(_ lhs: AsanaTask, _ rhs: AsanaTask) -> Bool {
        switch (lhs.dueDate, rhs.dueDate) {
        case let (left?, right?):
            if left != right { return left < right }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        case (.none, .none):
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}
