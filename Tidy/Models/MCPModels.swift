import Foundation

enum JSONValue: Codable, Equatable, Sendable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value."
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var objectValue: [String: JSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    var arrayValue: [JSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    var intValue: Int? {
        guard case .number(let value) = self else { return nil }
        return Int(value)
    }

    var foundationValue: Any {
        switch self {
        case .object(let value):
            value.mapValues(\.foundationValue)
        case .array(let value):
            value.map(\.foundationValue)
        case .string(let value):
            value
        case .number(let value):
            value
        case .bool(let value):
            value
        case .null:
            NSNull()
        }
    }

    var prettyPrinted: String {
        guard JSONSerialization.isValidJSONObject(foundationValue),
              let data = try? JSONSerialization.data(
                withJSONObject: foundationValue,
                options: [.prettyPrinted, .sortedKeys]
              ) else {
            if case .string(let value) = self { return value }
            return ""
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

struct MCPServerConfiguration: Equatable, Sendable {
    static let apiKeyKeychainKey = "mcp.workbench.api-key"

    let endpoint: URL
    let apiKeyHeaderName: String
    let apiKey: String

    init(endpoint: URL, apiKeyHeaderName: String, apiKey: String) {
        self.endpoint = endpoint
        self.apiKeyHeaderName = apiKeyHeaderName
        self.apiKey = apiKey
    }

    init(endpointText: String, apiKeyHeaderName: String, apiKey: String) throws {
        let trimmedURL = endpointText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHeader = apiKeyHeaderName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let endpoint = URL(string: trimmedURL),
              let scheme = endpoint.scheme?.lowercased(),
              let host = endpoint.host,
              !host.isEmpty else {
            throw MCPError.invalidConfiguration("Enter a valid MCP server URL.")
        }
        let isLocal = host == "localhost" || host == "127.0.0.1" || host == "::1"
        guard scheme == "https" || (scheme == "http" && isLocal) else {
            throw MCPError.invalidConfiguration("Remote MCP servers must use HTTPS.")
        }
        guard endpoint.user == nil, endpoint.password == nil else {
            throw MCPError.invalidConfiguration("Do not put credentials in the MCP URL.")
        }
        guard endpoint.fragment == nil else {
            throw MCPError.invalidConfiguration("MCP server URLs cannot contain fragments.")
        }
        guard !trimmedHeader.isEmpty,
              trimmedHeader.unicodeScalars.allSatisfy({
                  CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-")).contains($0)
              }) else {
            throw MCPError.invalidConfiguration("Enter a valid HTTP header name.")
        }
        let reservedHeaders: Set<String> = [
            "accept", "connection", "content-length", "content-type", "cookie", "host",
            "mcp-protocol-version", "mcp-session-id", "proxy-authorization",
            "te", "trailer", "transfer-encoding", "upgrade"
        ]
        guard !reservedHeaders.contains(trimmedHeader.lowercased()) else {
            throw MCPError.invalidConfiguration("Choose a non-reserved API key header name.")
        }
        guard !trimmedKey.isEmpty else {
            throw MCPError.invalidConfiguration("Enter the MCP API key.")
        }

        self.init(endpoint: endpoint, apiKeyHeaderName: trimmedHeader, apiKey: trimmedKey)
    }

    static func stored() throws -> MCPServerConfiguration {
        try MCPServerConfiguration(
            endpointText: UserDefaults.standard.string(forKey: AppDefaults.mcpServerURL) ?? "",
            apiKeyHeaderName: UserDefaults.standard.string(forKey: AppDefaults.mcpAPIKeyHeader) ?? "",
            apiKey: KeychainStore.read(key: apiKeyKeychainKey) ?? ""
        )
    }
}

struct MCPToolAnnotations: Codable, Equatable, Sendable {
    let readOnlyHint: Bool?
    let destructiveHint: Bool?
}

struct MCPTool: Codable, Identifiable, Equatable, Sendable {
    var id: String { name }

    let name: String
    let title: String?
    let description: String?
    let inputSchema: JSONValue
    let annotations: MCPToolAnnotations?
}

struct MCPContentBlock: Codable, Equatable, Sendable {
    let type: String
    let text: String?
}

struct MCPToolResult: Equatable, Sendable {
    let content: [MCPContentBlock]
    let structuredContent: JSONValue?
    let isError: Bool

    var displayText: String {
        let text = content.compactMap(\.text).joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { return text }
        return structuredContent?.prettyPrinted ?? ""
    }
}

enum MCPIntegrationSource: String, CaseIterable, Identifiable, Sendable {
    case slack
    case gmail
    case googleCalendar
    case newRelic
    case jira

    var id: String { rawValue }

    var title: String {
        switch self {
        case .slack: "Slack"
        case .gmail: "Gmail"
        case .googleCalendar: "Google Calendar"
        case .newRelic: "New Relic"
        case .jira: "Jira"
        }
    }

    var serviceKeywords: [String] {
        switch self {
        case .slack: ["slack"]
        case .gmail: ["gmail", "email", "mail"]
        case .googleCalendar: ["google_calendar", "google calendar", "calendar"]
        case .newRelic: ["newrelic", "new_relic", "new relic"]
        case .jira: ["jira"]
        }
    }

    var workbenchCatalogQuery: String {
        switch self {
        case .slack: "slack"
        case .gmail: "gmail"
        case .googleCalendar: "calendar"
        case .newRelic: "newrelic"
        case .jira: "jira"
        }
    }

    var workbenchIntegrationNames: Set<String> {
        switch self {
        case .slack: ["slack"]
        case .gmail: ["google-gmail"]
        case .googleCalendar: ["google-calendar"]
        case .newRelic: ["newrelic"]
        case .jira: ["atlassian-jira"]
        }
    }

    var preferredToolNames: [String] {
        switch self {
        case .slack:
            ["slack_search_all"]
        case .gmail:
            ["google_gmail_list", "google_gmail_threads"]
        case .googleCalendar:
            ["google_calendar_list_events"]
        case .newRelic:
            ["newrelic_run_nrql"]
        case .jira:
            ["jira_search_issues"]
        }
    }

    var defaultQuery: String {
        switch self {
        case .slack: "after:\(Self.dateString(daysAgo: 7))"
        case .gmail: "is:unread newer_than:7d"
        case .googleCalendar:
            ""
        case .newRelic:
            "SELECT * FROM NrAiIncident WHERE event = 'open' SINCE 7 days ago LIMIT 25"
        case .jira:
            "assignee = currentUser() AND updated >= -7d ORDER BY updated DESC"
        }
    }

    private static func dateString(daysAgo: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

struct MCPFetchedContext: Sendable {
    let source: MCPIntegrationSource
    let toolName: String
    let text: String
}

enum MCPError: LocalizedError, Equatable {
    case invalidConfiguration(String)
    case transport(status: Int, body: String)
    case invalidResponse(String)
    case rpc(code: Int, message: String)
    case unsupportedProtocol(String)
    case sessionExpired
    case toolExecution(String)
    case noCompatibleTool(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message):
            message
        case .transport(let status, let body):
            body.isEmpty
                ? "MCP server returned HTTP \(status)."
                : "MCP server returned HTTP \(status) with an error response."
        case .invalidResponse(let message):
            "Invalid MCP response: \(message)"
        case .rpc(let code, let message):
            "MCP error \(code): \(message)"
        case .unsupportedProtocol(let version):
            "The MCP server selected unsupported protocol version \(version)."
        case .sessionExpired:
            "The MCP session expired."
        case .toolExecution(let message):
            "MCP tool failed: \(message)"
        case .noCompatibleTool(let source):
            "No compatible read-only \(source) tool was discovered."
        }
    }
}
