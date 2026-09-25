import Foundation

@MainActor
protocol SlackMessageWriting {
    func scope() throws -> String
    func send(_ request: SlackSendRequest) async throws -> SlackSendReceipt
}

@MainActor
final class SlackMessageWriter: SlackMessageWriting {
    static let toolName = "slack_send_message"

    func scope() throws -> String {
        let config = try MCPServerConfiguration.stored()
        return SlackReplyFingerprint.make(config.endpoint.absoluteString + config.apiKey)
    }

    func send(_ request: SlackSendRequest) async throws -> SlackSendReceipt {
        let client: MCPClient
        let invocation: MCPToolRoute.Invocation
        let arguments = Self.arguments(for: request)
        do {
            guard try scope() == request.scope else { throw SlackSendError.notSent("The Slack connection changed. Review the message again.") }
            client = MCPClient(configuration: try .stored())
            try await client.connect()
            let tools = try await client.listTools()
            let schema: JSONValue
            if let direct = tools.first(where: { $0.name == Self.toolName }) {
                schema = direct.inputSchema
                invocation = .direct
            } else {
                guard MCPToolBroker.isWorkbenchCatalog(tools) else { throw MCPError.noCompatibleTool("Slack sending") }
                let result = try await client.callTool(name: "get_tool_schema", arguments: ["tool": .string(Self.toolName)])
                schema = try MCPToolBroker.workbenchSchema(from: result.displayText)
                invocation = .workbenchCatalog
            }
            let properties = schema.objectValue?["properties"]?.objectValue ?? [:]
            let required = schema.objectValue?["required"]?.arrayValue?.compactMap(\.stringValue) ?? []
            guard Set(arguments.keys).isSubset(of: Set(properties.keys)), Set(required).isSubset(of: Set(arguments.keys)) else {
                throw SlackSendError.notSent("The connected Slack send tool has an unsupported schema.")
            }
            try await SlackReadGate.shared.acquire(scope: client.rateLimitScope, method: Self.toolName)
            try Task.checkCancellation()
            guard try scope() == request.scope else { throw SlackSendError.notSent("The Slack connection changed. Review the message again.") }
        } catch {
            throw SlackSendError.notSent(error.localizedDescription, retryAfter: SlackReadGate.retryDelay(error))
        }

        do {
            let result: MCPToolResult
            switch invocation {
            case .direct:
                result = try await client.callToolWithoutRetry(name: Self.toolName, arguments: arguments)
            case .workbenchCatalog:
                result = try await client.callToolWithoutRetry(name: "execute_tools", arguments: ["executions": .array([
                    .object(["tool": .string(Self.toolName), "args": .object(arguments)])
                ])])
            }
            let value: JSONValue
            switch invocation {
            case .direct: value = try result.structuredContent ?? MCPToolBroker.decodedValue(from: result.displayText)
            case .workbenchCatalog: value = try MCPToolBroker.workbenchExecutionResult(from: result)
            }
            return try Self.receipt(from: value, request: request)
        } catch let error as SlackSendError {
            throw error
        } catch MCPError.rateLimited(let delay) {
            await SlackReadGate.shared.record(MCPError.rateLimited(delay), scope: client.rateLimitScope)
            throw SlackSendError.notSent("Slack asked us to pause. Review and send again after the cooldown.", retryAfter: delay)
        } catch {
            // A lost response cannot prove that the server did not post the message.
            throw SlackSendError.uncertain
        }
    }

    static func arguments(for request: SlackSendRequest) -> [String: JSONValue] {
        var value: [String: JSONValue] = ["channel": .string(request.channelID), "text": .string(request.text)]
        if let thread = request.threadTS { value["threadTs"] = .string(thread) }
        return value
    }

    static func receipt(from value: JSONValue, request: SlackSendRequest) throws -> SlackSendReceipt {
        guard let object = value.objectValue else { throw SlackSendError.uncertain }
        if object["ok"] == .bool(false) {
            let error = object["error"]?.stringValue ?? "unknown_error"
            let delay = error == "ratelimited" ? Double(object["retry_after"]?.intValue ?? 60) : nil
            throw SlackSendError.notSent("Slack did not send this message: \(error).", retryAfter: delay)
        }
        guard object["ok"] == .bool(true), let channel = object["channel"]?.stringValue, channel == request.channelID,
              let ts = object["ts"]?.stringValue, let seconds = Double(ts), seconds.isFinite, seconds > 0 else {
            throw SlackSendError.uncertain
        }
        return SlackSendReceipt(channelID: channel, ts: ts)
    }
}

@MainActor
struct SlackPreviewWriter: SlackMessageWriting {
    func scope() throws -> String { "local-slack-preview" }
    func send(_ request: SlackSendRequest) async throws -> SlackSendReceipt {
        SlackSendReceipt(channelID: request.channelID, ts: String(Date().timeIntervalSince1970))
    }
}
