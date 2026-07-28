import Foundation

private struct MCPRPCEnvelope: Decodable {
    struct RPCError: Decodable {
        let code: Int
        let message: String
    }

    let id: JSONValue?
    let result: JSONValue?
    let error: RPCError?
}

actor MCPClient {
    static let preferredProtocolVersion = "2025-11-25"
    static let supportedProtocolVersions = Set([
        "2025-11-25",
        "2025-06-18",
        "2025-03-26"
    ])

    private let configuration: MCPServerConfiguration
    private let session: URLSession
    private var sessionID: String?
    private var negotiatedProtocolVersion: String?
    private var nextRequestID = 1

    init(
        configuration: MCPServerConfiguration,
        session: URLSession = .shared
    ) {
        self.configuration = configuration
        self.session = session
    }

    @discardableResult
    func connect() async throws -> String {
        sessionID = nil
        negotiatedProtocolVersion = nil

        let id = takeRequestID()
        let payload: JSONValue = .object([
            "jsonrpc": .string("2.0"),
            "id": .number(Double(id)),
            "method": .string("initialize"),
            "params": .object([
                "protocolVersion": .string(Self.preferredProtocolVersion),
                "capabilities": .object([:]),
                "clientInfo": .object([
                    "name": .string("Tidy"),
                    "title": .string("Tidy for macOS"),
                    "version": .string(
                        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
                    )
                ])
            ])
        ])

        let response = try await post(payload, expectedRequestID: id, includeProtocolHeader: false)
        guard let result = response.envelope?.result?.objectValue,
              let version = result["protocolVersion"]?.stringValue else {
            throw MCPError.invalidResponse("initialize result did not include protocolVersion.")
        }
        guard Self.supportedProtocolVersions.contains(version) else {
            throw MCPError.unsupportedProtocol(version)
        }
        negotiatedProtocolVersion = version
        sessionID = Self.validSessionID(response.sessionID)

        let initialized: JSONValue = .object([
            "jsonrpc": .string("2.0"),
            "method": .string("notifications/initialized")
        ])
        _ = try await post(initialized, expectedRequestID: nil, includeProtocolHeader: true)
        return Self.safeDisplayText(
            result["serverInfo"]?.objectValue?["name"]?.stringValue,
            fallback: "MCP server",
            limit: 120
        )
    }

    func listTools() async throws -> [MCPTool] {
        try await ensureConnected()
        do {
            return try await listToolsOnce()
        } catch MCPError.sessionExpired {
            try await connect()
            return try await listToolsOnce()
        }
    }

    func callTool(name: String, arguments: [String: JSONValue]) async throws -> MCPToolResult {
        try await ensureConnected()
        do {
            return try await callToolOnce(name: name, arguments: arguments)
        } catch MCPError.sessionExpired {
            try await connect()
            return try await callToolOnce(name: name, arguments: arguments)
        }
    }

    private func ensureConnected() async throws {
        if negotiatedProtocolVersion == nil {
            try await connect()
        }
    }

    private func listToolsOnce() async throws -> [MCPTool] {
        var tools: [MCPTool] = []
        var cursor: String?

        for _ in 0..<100 {
            let id = takeRequestID()
            var params: [String: JSONValue] = [:]
            if let cursor { params["cursor"] = .string(cursor) }
            let payload: JSONValue = .object([
                "jsonrpc": .string("2.0"),
                "id": .number(Double(id)),
                "method": .string("tools/list"),
                "params": .object(params)
            ])
            let response = try await post(payload, expectedRequestID: id, includeProtocolHeader: true)
            guard let result = response.envelope?.result?.objectValue,
                  let rawTools = result["tools"]?.arrayValue else {
                throw MCPError.invalidResponse("tools/list result did not include tools.")
            }

            let data = try JSONEncoder().encode(rawTools)
            tools.append(contentsOf: try JSONDecoder().decode([MCPTool].self, from: data))
            cursor = result["nextCursor"]?.stringValue
            if cursor == nil { return tools }
        }

        throw MCPError.invalidResponse("tools/list returned too many pages.")
    }

    private func callToolOnce(
        name: String,
        arguments: [String: JSONValue]
    ) async throws -> MCPToolResult {
        let id = takeRequestID()
        let payload: JSONValue = .object([
            "jsonrpc": .string("2.0"),
            "id": .number(Double(id)),
            "method": .string("tools/call"),
            "params": .object([
                "name": .string(name),
                "arguments": .object(arguments)
            ])
        ])
        let response = try await post(payload, expectedRequestID: id, includeProtocolHeader: true)
        guard let result = response.envelope?.result?.objectValue else {
            throw MCPError.invalidResponse("tools/call result was missing.")
        }

        let content: [MCPContentBlock]
        if let values = result["content"]?.arrayValue {
            content = try JSONDecoder().decode(
                [MCPContentBlock].self,
                from: JSONEncoder().encode(values)
            )
        } else {
            content = []
        }
        let toolResult = MCPToolResult(
            content: content,
            structuredContent: result["structuredContent"],
            isError: result["isError"]?.boolValue ?? false
        )
        if toolResult.isError {
            throw MCPError.toolExecution(
                toolResult.displayText.isEmpty ? "The server reported an unknown tool error." : toolResult.displayText
            )
        }
        return toolResult
    }

    private func takeRequestID() -> Int {
        defer { nextRequestID += 1 }
        return nextRequestID
    }

    private func post(
        _ payload: JSONValue,
        expectedRequestID: Int?,
        includeProtocolHeader: Bool
    ) async throws -> (envelope: MCPRPCEnvelope?, sessionID: String?) {
        var request = URLRequest(url: configuration.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(configuration.apiKey, forHTTPHeaderField: configuration.apiKeyHeaderName)
        if includeProtocolHeader, let negotiatedProtocolVersion {
            request.setValue(negotiatedProtocolVersion, forHTTPHeaderField: "MCP-Protocol-Version")
        }
        if let sessionID {
            request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id")
        }
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, urlResponse) = try await SecureHTTP.data(
            for: request,
            session: session
        )
        guard let httpResponse = urlResponse as? HTTPURLResponse else {
            throw MCPError.invalidResponse("The server did not return HTTP metadata.")
        }
        if httpResponse.statusCode == 404, sessionID != nil {
            throw MCPError.sessionExpired
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw MCPError.transport(
                status: httpResponse.statusCode,
                body: String(data: data, encoding: .utf8) ?? "(no body)"
            )
        }
        guard expectedRequestID != nil else {
            return (
                nil,
                Self.validSessionID(httpResponse.value(forHTTPHeaderField: "Mcp-Session-Id"))
            )
        }

        let messages = try Self.jsonRPCMessages(
            from: data,
            contentType: httpResponse.value(forHTTPHeaderField: "Content-Type")
        )
        let envelopes = try messages.map { try JSONDecoder().decode(MCPRPCEnvelope.self, from: $0) }
        guard let envelope = envelopes.first(where: {
            $0.id?.intValue == expectedRequestID
        }) else {
            throw MCPError.invalidResponse("No JSON-RPC response matched request \(expectedRequestID!).")
        }
        if let error = envelope.error {
            throw MCPError.rpc(code: error.code, message: error.message)
        }
        return (
            envelope,
            Self.validSessionID(httpResponse.value(forHTTPHeaderField: "Mcp-Session-Id"))
        )
    }

    static func jsonRPCMessages(from data: Data, contentType: String?) throws -> [Data] {
        guard !data.isEmpty else { return [] }
        if contentType?.lowercased().contains("text/event-stream") != true {
            return [data]
        }
        guard let body = String(data: data, encoding: .utf8) else {
            throw MCPError.invalidResponse("SSE response was not UTF-8.")
        }

        var messages: [Data] = []
        var dataLines: [String] = []
        func flush() {
            guard !dataLines.isEmpty else { return }
            let joined = dataLines.joined(separator: "\n")
            if !joined.isEmpty, let value = joined.data(using: .utf8) {
                messages.append(value)
            }
            dataLines.removeAll(keepingCapacity: true)
        }

        for line in body.components(separatedBy: .newlines) {
            if line.isEmpty {
                flush()
            } else if line.hasPrefix("data:") {
                var value = String(line.dropFirst(5))
                if value.hasPrefix(" ") { value.removeFirst() }
                dataLines.append(value)
            }
        }
        flush()
        return messages
    }

    private static func validSessionID(_ value: String?) -> String? {
        guard let value,
              !value.isEmpty,
              value.utf8.count <= 1_024,
              value.unicodeScalars.allSatisfy({
                  !CharacterSet.controlCharacters.contains($0)
              }) else {
            return nil
        }
        return value
    }

    private static func safeDisplayText(
        _ value: String?,
        fallback: String,
        limit: Int
    ) -> String {
        guard let value else { return fallback }
        let sanitized = value.unicodeScalars
            .filter { !CharacterSet.controlCharacters.contains($0) }
            .map(String.init)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? fallback : String(sanitized.prefix(limit))
    }
}

enum MCPToolRouter {
    private static let readActionTerms = [
        "search", "list", "get", "fetch", "read", "find", "lookup", "history"
    ]
    private static let readContextTerms = [
        "notification", "unread", "message", "event", "incident", "alert", "thread"
    ]
    private static let mutatingTerms = [
        "send", "create", "update", "delete", "remove", "post", "reply", "write",
        "schedule", "cancel", "archive", "modify", "move", "invite", "publish",
        "submit", "complete", "close", "resolve", "acknowledge", "approve", "reject",
        "assign", "transition", "upload", "share", "react"
    ]
    private static let mutatingInflections = [
        "sends", "sending", "sent", "creates", "creating", "created", "updates",
        "updating", "updated", "deletes", "deleting", "deleted", "posts", "posting",
        "posted", "replies", "replying", "writes", "writing", "schedules",
        "scheduling", "cancels", "cancelling", "archives", "archiving", "modifies",
        "modifying", "moves", "moving", "invites", "inviting", "publishes",
        "publishing", "submits", "submitting", "completes", "completing", "closes",
        "closing", "resolves", "resolving", "approves", "approving", "rejects",
        "rejecting", "assigns", "assigning", "transitions", "uploading", "uploads",
        "sharing", "shares", "reacting", "reacts"
    ]
    private static let knownReadOnlyToolNames = Set(
        MCPIntegrationSource.allCases.flatMap(\.preferredToolNames)
    )

    static func bestTool(
        for source: MCPIntegrationSource,
        in tools: [MCPTool]
    ) -> MCPTool? {
        tools
            .compactMap { tool -> (MCPTool, Int)? in
                let text = "\(tool.name) \(tool.title ?? "") \(tool.description ?? "")".lowercased()
                guard source.serviceKeywords.contains(where: text.contains),
                      isSafeReadTool(tool, searchableText: text),
                      arguments(for: tool, source: source, query: source.defaultQuery) != nil else {
                    return nil
                }

                var score = source.serviceKeywords.reduce(0) { $0 + (text.contains($1) ? 20 : 0) }
                score += (readActionTerms + readContextTerms)
                    .reduce(0) { $0 + (text.contains($1) ? 3 : 0) }
                if source.preferredToolNames.contains(tool.name) { score += 100 }
                if tool.annotations?.readOnlyHint == true { score += 20 }
                if text.contains("notification") || text.contains("unread") { score += 8 }
                return (tool, score)
            }
            .max(by: { $0.1 < $1.1 })?
            .0
    }

    static func arguments(
        for tool: MCPTool,
        source: MCPIntegrationSource,
        query: String
    ) -> [String: JSONValue]? {
        guard let schema = tool.inputSchema.objectValue else { return nil }
        let properties = schema["properties"]?.objectValue ?? [:]
        let required = Set(schema["required"]?.arrayValue?.compactMap(\.stringValue) ?? [])
        var arguments: [String: JSONValue] = [:]

        for (name, property) in properties {
            if let value = inferredValue(for: name, schema: property, source: source, query: query) {
                arguments[name] = value
            }
        }
        guard required.isSubset(of: Set(arguments.keys)) else { return nil }
        return arguments
    }

    static func mappingSummary(
        tools: [MCPTool],
        sources: [MCPIntegrationSource] = MCPIntegrationSource.allCases
    ) -> [MCPIntegrationSource: String] {
        Dictionary(uniqueKeysWithValues: sources.map { source in
            (source, bestTool(for: source, in: tools)?.name ?? "Not detected")
        })
    }

    fileprivate static func isSafeReadTool(_ tool: MCPTool, searchableText: String) -> Bool {
        if tool.annotations?.destructiveHint == true
            || tool.annotations?.readOnlyHint == false {
            return false
        }
        let nameWords = Set(
            tool.name.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        )
        let allWords = Set(
            searchableText
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        )
        let prohibitedTerms = Set(mutatingTerms + mutatingInflections)
        guard prohibitedTerms.isDisjoint(with: nameWords) else {
            return false
        }
        if knownReadOnlyToolNames.contains(tool.name) {
            return true
        }
        guard prohibitedTerms.isDisjoint(with: allWords) else { return false }

        return readActionTerms.contains(where: nameWords.contains)
    }

    private static func inferredValue(
        for name: String,
        schema: JSONValue,
        source: MCPIntegrationSource,
        query: String
    ) -> JSONValue? {
        let normalized = name
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
        let schemaObject = schema.objectValue ?? [:]
        let type = schemaObject["type"]?.stringValue

        if ["query", "q", "search", "searchquery", "filter", "prompt"].contains(normalized) {
            return .string(query)
        }
        if ["limit", "count", "pagesize", "maxresults", "maxitems", "first"].contains(normalized) {
            return .number(source == .slack && normalized == "count" ? 10 : 25)
        }
        if ["unread", "unreadonly", "onlyunread"].contains(normalized) {
            return .bool(true)
        }
        if ["includeread"].contains(normalized) {
            return .bool(false)
        }
        if ["userid", "user", "mailbox", "mailboxid"].contains(normalized) {
            return .string("me")
        }
        if ["calendarid", "calendar"].contains(normalized) {
            return .string("primary")
        }

        let now = Date()
        let formatter = ISO8601DateFormatter()
        if ["start", "starttime", "timemin", "from", "after", "since"].contains(normalized) {
            let start = source == .googleCalendar
                ? now
                : Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
            return .string(formatter.string(from: start))
        }
        if ["end", "endtime", "timemax", "to", "before", "until"].contains(normalized) {
            let end = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
            return .string(formatter.string(from: end))
        }

        if let defaultValue = schemaObject["default"] {
            return defaultValue
        }
        if type == "boolean", normalized.contains("include") {
            return .bool(false)
        }
        return nil
    }
}

struct MCPToolRoute: Sendable {
    enum Invocation: Sendable {
        case direct
        case workbenchCatalog
    }

    let source: MCPIntegrationSource
    let tool: MCPTool
    let invocation: Invocation
}

enum MCPToolBroker {
    private struct WorkbenchDescriptor {
        let name: String
        let description: String?
        let integration: String?
    }

    static func resolve(
        source: MCPIntegrationSource,
        advertisedTools: [MCPTool],
        client: MCPClient
    ) async throws -> MCPToolRoute {
        if let direct = MCPToolRouter.bestTool(for: source, in: advertisedTools) {
            return MCPToolRoute(source: source, tool: direct, invocation: .direct)
        }
        guard isWorkbenchCatalog(advertisedTools) else {
            throw MCPError.noCompatibleTool(source.title)
        }

        let searchResult = try await client.callTool(
            name: "search_tools",
            arguments: ["query": .string(source.workbenchCatalogQuery)]
        )
        var descriptors = try workbenchDescriptors(from: searchResult.displayText)
            .filter { descriptor in
                if let integration = descriptor.integration {
                    return source.workbenchIntegrationNames.contains(integration)
                }
                let text = "\(descriptor.name) \(descriptor.description ?? "")".lowercased()
                return source.serviceKeywords.contains(where: text.contains)
            }

        descriptors.sort {
            descriptorRank($0, source: source) > descriptorRank($1, source: source)
        }

        var compatibleTools: [MCPTool] = []
        for descriptor in descriptors.prefix(12) {
            let provisional = MCPTool(
                name: descriptor.name,
                title: nil,
                description: descriptor.description,
                inputSchema: .object([:]),
                annotations: nil
            )
            let searchableText = "\(descriptor.name) \(descriptor.description ?? "")".lowercased()
            guard MCPToolRouter.isSafeReadTool(provisional, searchableText: searchableText) else {
                continue
            }

            let schemaResult = try await client.callTool(
                name: "get_tool_schema",
                arguments: ["tool": .string(descriptor.name)]
            )
            let schema = try workbenchSchema(from: schemaResult.displayText)
            let tool = MCPTool(
                name: descriptor.name,
                title: nil,
                description: descriptor.description,
                inputSchema: schema,
                annotations: MCPToolAnnotations(readOnlyHint: true, destructiveHint: false)
            )
            guard MCPToolRouter.arguments(
                for: tool,
                source: source,
                query: source.defaultQuery
            ) != nil else {
                continue
            }
            compatibleTools.append(tool)

            if source.preferredToolNames.contains(tool.name) {
                return MCPToolRoute(
                    source: source,
                    tool: tool,
                    invocation: .workbenchCatalog
                )
            }
        }

        guard let best = MCPToolRouter.bestTool(for: source, in: compatibleTools) else {
            throw MCPError.noCompatibleTool(source.title)
        }
        return MCPToolRoute(source: source, tool: best, invocation: .workbenchCatalog)
    }

    static func resolveNamedTool(
        _ name: String,
        source: MCPIntegrationSource,
        advertisedTools: [MCPTool],
        client: MCPClient
    ) async throws -> MCPToolRoute {
        if let direct = advertisedTools.first(where: { $0.name == name }) {
            let searchableText = "\(direct.name) \(direct.title ?? "") \(direct.description ?? "")"
                .lowercased()
            guard MCPToolRouter.isSafeReadTool(direct, searchableText: searchableText) else {
                throw MCPError.noCompatibleTool(source.title)
            }
            return MCPToolRoute(source: source, tool: direct, invocation: .direct)
        }
        guard isWorkbenchCatalog(advertisedTools) else {
            throw MCPError.noCompatibleTool(source.title)
        }

        let provisional = MCPTool(
            name: name,
            title: nil,
            description: nil,
            inputSchema: .object([:]),
            annotations: nil
        )
        guard MCPToolRouter.isSafeReadTool(provisional, searchableText: name.lowercased()) else {
            throw MCPError.noCompatibleTool(source.title)
        }
        let schemaResult = try await client.callTool(
            name: "get_tool_schema",
            arguments: ["tool": .string(name)]
        )
        return MCPToolRoute(
            source: source,
            tool: MCPTool(
                name: name,
                title: nil,
                description: nil,
                inputSchema: try workbenchSchema(from: schemaResult.displayText),
                annotations: MCPToolAnnotations(readOnlyHint: true, destructiveHint: false)
            ),
            invocation: .workbenchCatalog
        )
    }

    static func execute(
        route: MCPToolRoute,
        arguments: [String: JSONValue],
        client: MCPClient
    ) async throws -> MCPToolResult {
        switch route.invocation {
        case .direct:
            return try await client.callTool(name: route.tool.name, arguments: arguments)
        case .workbenchCatalog:
            let wrapperResult = try await client.callTool(
                name: "execute_tools",
                arguments: [
                    "executions": .array([
                        .object([
                            "tool": .string(route.tool.name),
                            "args": .object(arguments)
                        ])
                    ])
                ]
            )
            let unwrapped = try workbenchExecutionResult(from: wrapperResult.displayText)
            return MCPToolResult(
                content: [
                    MCPContentBlock(type: "text", text: compactText(unwrapped, source: route.source))
                ],
                structuredContent: unwrapped,
                isError: false
            )
        }
    }

    static func mappingSummary(
        client: MCPClient,
        advertisedTools: [MCPTool],
        sources: [MCPIntegrationSource] = MCPIntegrationSource.allCases
    ) async -> [MCPIntegrationSource: String] {
        var mappings: [MCPIntegrationSource: String] = [:]
        for source in sources {
            do {
                mappings[source] = try await resolve(
                    source: source,
                    advertisedTools: advertisedTools,
                    client: client
                ).tool.name
            } catch {
                mappings[source] = "Not detected"
            }
        }
        return mappings
    }

    static func isWorkbenchCatalog(_ tools: [MCPTool]) -> Bool {
        let names = Set(tools.map(\.name))
        return names.isSuperset(of: ["search_tools", "get_tool_schema", "execute_tools"])
    }

    static func workbenchToolNames(from text: String) throws -> [String] {
        try workbenchDescriptors(from: text).map(\.name)
    }

    static func workbenchSchema(from text: String) throws -> JSONValue {
        let value = try decodedJSON(text)
        guard let schema = value.objectValue?["schema"] else {
            throw MCPError.invalidResponse("get_tool_schema did not return a schema.")
        }
        return schema
    }

    static func workbenchExecutionResult(from text: String) throws -> JSONValue {
        let value = try decodedJSON(text)
        guard let first = value.objectValue?["results"]?.arrayValue?.first?.objectValue else {
            throw MCPError.invalidResponse("execute_tools did not return a result.")
        }
        if let error = first["error"] {
            throw MCPError.toolExecution(error.prettyPrinted)
        }
        guard let result = first["result"] else {
            throw MCPError.invalidResponse("execute_tools result entry was empty.")
        }
        return result
    }

    static func decodedValue(from text: String) throws -> JSONValue {
        try decodedJSON(text)
    }

    private static func workbenchDescriptors(from text: String) throws -> [WorkbenchDescriptor] {
        let value = try decodedJSON(text)
        guard let rawTools = value.objectValue?["tools"]?.arrayValue else {
            throw MCPError.invalidResponse("search_tools did not return tools.")
        }
        return rawTools.compactMap { value in
            guard let object = value.objectValue,
                  let name = object["name"]?.stringValue else {
                return nil
            }
            return WorkbenchDescriptor(
                name: name,
                description: object["description"]?.stringValue,
                integration: object["integration"]?.stringValue
            )
        }
    }

    private static func decodedJSON(_ text: String) throws -> JSONValue {
        guard let data = text.data(using: .utf8) else {
            throw MCPError.invalidResponse("Workbench returned non-UTF-8 content.")
        }
        do {
            return try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw MCPError.invalidResponse("Workbench returned malformed JSON content.")
        }
    }

    private static func descriptorRank(
        _ descriptor: WorkbenchDescriptor,
        source: MCPIntegrationSource
    ) -> Int {
        if let index = source.preferredToolNames.firstIndex(of: descriptor.name) {
            return 1_000 - index
        }
        let text = "\(descriptor.name) \(descriptor.description ?? "")".lowercased()
        var score = source.serviceKeywords.reduce(0) { $0 + (text.contains($1) ? 20 : 0) }
        score += ["search", "list", "get", "read", "history", "message", "event"]
            .reduce(0) { $0 + (text.contains($1) ? 3 : 0) }
        return score
    }

    private static func compactText(
        _ value: JSONValue,
        source: MCPIntegrationSource
    ) -> String {
        guard let object = value.objectValue else { return value.prettyPrinted }
        switch source {
        case .slack:
            guard let messages = object["messages"]?.objectValue else {
                return value.prettyPrinted
            }
            return JSONValue.object([
                "total": messages["total"] ?? .number(0),
                "messages": messages["matches"] ?? .array([])
            ]).prettyPrinted
        case .gmail:
            return JSONValue.object([
                "messages": object["messages"] ?? .array([]),
                "nextPageToken": object["nextPageToken"] ?? .null
            ]).prettyPrinted
        case .googleCalendar:
            return JSONValue.object([
                "events": object["events"] ?? .array([]),
                "nextPageToken": object["nextPageToken"] ?? .null
            ]).prettyPrinted
        case .newRelic, .jira:
            return value.prettyPrinted
        }
    }
}

enum MCPContextLoader {
    static func load(
        sources: Set<AskAIMCPSource>,
        question: String
    ) async -> String {
        guard !sources.isEmpty else { return "" }

        do {
            let configuration = try MCPServerConfiguration.stored()
            let client = MCPClient(configuration: configuration)
            try await client.connect()
            let tools = try await client.listTools()
            var sections: [String] = []

            for source in sources.sorted(by: { $0.rawValue < $1.rawValue }) {
                do {
                    let route = try await MCPToolBroker.resolve(
                        source: source.integrationSource,
                        advertisedTools: tools,
                        client: client
                    )
                    guard let arguments = MCPToolRouter.arguments(
                        for: route.tool,
                        source: source.integrationSource,
                        query: question
                    ) else {
                        throw MCPError.noCompatibleTool(source.title)
                    }
                    let result = try await MCPToolBroker.execute(
                        route: route,
                        arguments: arguments,
                        client: client
                    )
                    let text = String(result.displayText.prefix(12_000))
                    sections.append("\(source.title) via \(route.tool.name):\n\(text)")
                } catch {
                    sections.append("\(source.title): \(error.localizedDescription)")
                }
            }
            return sections.joined(separator: "\n\n")
        } catch {
            return "MCP connection failed: \(error.localizedDescription)"
        }
    }
}
