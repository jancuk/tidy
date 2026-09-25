import Foundation

@MainActor
protocol SlackReplyReading {
    func scope() throws -> String
    func search(query: String, page: Int, count: Int) async throws -> SlackSearchPage
    func context(for message: SlackReplyMessage) async throws -> (messages: [SlackReplyMessage], partial: Bool)
}

actor SlackReadGate {
    static let shared = SlackReadGate()
    private var nextSlot: [String: Date] = [:]
    private var cooldown: [String: Date] = [:]

    static func spacing(for method: String) -> TimeInterval {
        if method == "slack_send_message" { return 1.1 }
        return method.contains("search") ? 3.1 : 61
    }

    func acquire(scope: String, method: String) async throws {
        let key = scope + method
        let now = Date()
        if let until = cooldown[scope], until > now { throw SlackReplyError.rateLimited(until.timeIntervalSince(now)) }
        let slot = max(now, nextSlot[key] ?? now)
        nextSlot[key] = slot.addingTimeInterval(Self.spacing(for: method))
        if slot > now { try await Task.sleep(for: .seconds(slot.timeIntervalSince(now))) }
        try Task.checkCancellation()
        if let until = cooldown[scope], until > Date() { throw SlackReplyError.rateLimited(until.timeIntervalSinceNow) }
    }

    func record(_ error: Error, scope: String) {
        if let delay = Self.retryDelay(error) { cooldown[scope] = Date().addingTimeInterval(delay) }
    }

    static func retryDelay(_ error: Error) -> TimeInterval? {
        if case MCPError.rateLimited(let seconds) = error { return max(60, seconds) }
        if case SlackReplyError.rateLimited(let seconds) = error { return max(60, seconds) }
        let message = error.localizedDescription.lowercased()
        guard message.contains("ratelimit") || message.contains("rate_limit") || message.contains("429") || message.contains("rate limit") else { return nil }
        let pattern = #"retry[_ -]?after[\"\s:]+([0-9]+)"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)),
           let range = Range(match.range(at: 1), in: message), let seconds = Double(message[range]) { return max(60, seconds) }
        return 300
    }
}

@MainActor
final class SlackMCPReader: SlackReplyReading {
    enum ReadMethod: String, CaseIterable {
        case search = "slack_search_all"
        case thread = "slack_get_thread_replies"
        case history = "slack_get_channel_history"
    }
    private var client: MCPClient?
    private var tools: [MCPTool] = []
    private var routes: [ReadMethod: MCPToolRoute] = [:]
    private var activeScope = ""

    func scope() throws -> String {
        let config = try MCPServerConfiguration.stored()
        return SlackReplyFingerprint.make(config.endpoint.absoluteString + config.apiKey)
    }

    func search(query: String, page: Int, count: Int) async throws -> SlackSearchPage {
        try SlackReplyDecoder.search(await read(.search, arguments: ["query": .string(query), "count": .number(Double(count)), "page": .number(Double(page))]), page: page, count: count)
    }

    func context(for message: SlackReplyMessage) async throws -> (messages: [SlackReplyMessage], partial: Bool) {
        let method: ReadMethod = message.isDM && message.ts == message.threadTS ? .history : .thread
        var args: [String: JSONValue] = ["channel": .string(message.channelID)]
        if method == .thread { args["threadTs"] = .string(message.threadTS) }
        for limit in [15, 7, 3, 1] {
            args["limit"] = .number(Double(limit))
            do {
                var result = try SlackReplyDecoder.context(await read(method, arguments: args), anchor: message)
                result.partial = result.partial || limit < 15
                return result
            } catch MCPError.responseTooLarge where limit > 1 {
                continue
            }
        }
        throw MCPError.responseTooLarge
    }

    private func read(_ method: ReadMethod, arguments: [String: JSONValue]) async throws -> JSONValue {
        let current = try scope()
        if client == nil || activeScope != current {
            let next = MCPClient(configuration: try .stored())
            try await next.connect()
            tools = try await next.listTools()
            routes = [:]
            client = next
            activeScope = current
        }
        guard let client else { throw SlackReplyError.message("Connect Workbench in Integration settings.") }
        let route: MCPToolRoute
        if let cached = routes[method] { route = cached }
        else if let direct = tools.first(where: { $0.name == method.rawValue }) {
            guard direct.annotations?.readOnlyHint != false, direct.annotations?.destructiveHint != true else {
                throw SlackReplyError.message("The Slack tool is not advertised as safe to read.")
            }
            route = MCPToolRoute(source: .slack, tool: direct, invocation: .direct)
            routes[method] = route
        } else {
            guard MCPToolBroker.isWorkbenchCatalog(tools) else { throw MCPError.noCompatibleTool(method.rawValue) }
            let schema = try await client.callTool(name: "get_tool_schema", arguments: ["tool": .string(method.rawValue)])
            route = MCPToolRoute(source: .slack, tool: MCPTool(name: method.rawValue, title: nil, description: nil,
                                 inputSchema: try MCPToolBroker.workbenchSchema(from: schema.displayText),
                                 annotations: MCPToolAnnotations(readOnlyHint: true, destructiveHint: false)), invocation: .workbenchCatalog)
            routes[method] = route
        }
        let required = route.tool.inputSchema.objectValue?["required"]?.arrayValue?.compactMap(\.stringValue) ?? []
        guard Set(required).isSubset(of: Set(arguments.keys)) else { throw SlackReplyError.message("The connected Slack read tool uses an unsupported schema.") }
        do {
            let result = try await MCPToolBroker.execute(route: route, arguments: arguments, client: client)
            let value = try result.structuredContent ?? MCPToolBroker.decodedValue(from: result.displayText)
            try SlackReplyDecoder.check(value)
            return value
        } catch {
            await SlackReadGate.shared.record(error, scope: client.rateLimitScope)
            throw error
        }
    }
}
