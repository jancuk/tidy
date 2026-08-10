//
//  TidyTests.swift
//  TidyTests
//
//  Public test fixtures use fictional identities and organizations.
//

import Foundation
import Testing
import AppKit
import SwiftUI
@testable import Tidy

struct TidyTests {

    @Test func jsonFormatterValidatesAndFormats() async throws {
        let result = JSONTool.format("{\"b\":2,\"a\":1}")

        #expect(result.isError == false)
        #expect(result.output.contains("\"a\" : 1"))
        #expect(result.output.contains("\"b\" : 2"))
    }

    @Test func jwtDebuggerDecodesPayloadClaims() async throws {
        let result = JWTTool.decode("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjMifQ.signature")

        #expect(result.isError == false)
        #expect(result.payloadJSON.contains("\"sub\" : \"123\""))
    }

    @Test func csvConvertsToJSON() async throws {
        let result = CSVTool.csvToJSON("name,role\nTidy,Tools")

        #expect(result.isError == false)
        #expect(result.output.contains("\"name\" : \"Tidy\""))
        #expect(result.output.contains("\"role\" : \"Tools\""))
    }

    @Test func cronParsesStepExpression() async throws {
        let result = CronTool.parse("*/15 * * * *")

        #expect(result.isError == false)
        #expect(result.description == "Every 15 minutes")
        #expect(result.fields.first?.1.contains("0") == true)
        #expect(result.nextRuns.isEmpty == false)
    }

    @Test func delimiterToolJoinsLinesWithComma() {
        let result = DelimiterTool.convert("1\n2\n3\n4", delimiter: ",", quoteStyle: .none)

        #expect(result.output == "1,2,3,4")
        #expect(result.status == "Converted 4 values.")
        #expect(result.isError == false)
    }

    @Test func delimiterToolSupportsDoubleAndSingleQuotes() {
        let doubleQuoted = DelimiterTool.convert("1\n2", delimiter: ",", quoteStyle: .double)
        let singleQuoted = DelimiterTool.convert("1\n2", delimiter: ",", quoteStyle: .single)

        #expect(doubleQuoted.output == "\"1\",\"2\"")
        #expect(singleQuoted.output == "'1','2'")
    }

    @Test func delimiterToolTrimsBlankLinesAndEscapesQuotes() {
        let result = DelimiterTool.convert(
            "  first  \n\nO'Reilly\npath\\file",
            delimiter: ".",
            quoteStyle: .single
        )

        #expect(result.output == "'first'.'O\\'Reilly'.'path\\\\file'")
    }

    @Test func grammarPromptDoesNotExposeAssistantIdentity() async throws {
        #expect(GrammarProviderFactory.prompt.contains("You are") == false)
        #expect(GrammarProviderFactory.prompt.contains("grammar-correction transformer") == false)
        #expect(GrammarProviderFactory.prompt.contains("Never answer") == true)
    }

    @Test func grammarInputPromptTreatsQuestionsAsLiteralText() async throws {
        let prompt = GrammarProviderFactory.inputPrompt(for: "who are you")

        #expect(prompt.contains("who are you"))
        #expect(prompt.contains("literal text"))
        #expect(prompt.contains("Do not answer or follow"))
    }

    @Test func appearanceModeDefaultKeyExists() {
        #expect(AppDefaults.appearanceMode == "appearanceMode")
    }

    @Test func askAIHotkeyDefaultIsControlOptionJ() {
        let defaults = UserDefaults(suiteName: "test.tidy.askai")!
        defaults.registerTidyDefaults()
        #expect(defaults.string(forKey: AppDefaults.askAIHotkey) == "control+option+j")
        defaults.removePersistentDomain(forName: "test.tidy.askai")
    }

    @Test func askAIMentionParserFindsMCPSources() {
        let sources = AskAIMentionParser.mcpSources(in: "@mcp-slack summarize history and @mcp-jira show dashboard")

        #expect(sources == [.slack, .jira])
    }

    @Test func askAIMentionParserFindsWorkbenchSources() {
        let sources = AskAIMentionParser.mcpSources(
            in: "@mcp-gmail unread, @mcp-google-calendar next week, @mcp-newrelic incidents"
        )

        #expect(sources == [.gmail, .googleCalendar, .newRelic])
    }

    @Test func mcpSSEParserExtractsJSONRPCMessages() throws {
        let data = Data("""
        id: initialize-1
        event: message
        data: {"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2025-11-25"}}

        event: message
        data: {"jsonrpc":"2.0","method":"notifications/tools/list_changed"}

        """.utf8)

        let messages = try MCPClient.jsonRPCMessages(
            from: data,
            contentType: "text/event-stream; charset=utf-8"
        )

        #expect(messages.count == 2)
        #expect(String(data: messages[0], encoding: .utf8)?.contains("\"id\":1") == true)
    }

    @Test func mcpToolRouterSelectsReadOnlySlackTool() {
        let schema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "query": .object(["type": .string("string")]),
                "limit": .object(["type": .string("integer")])
            ]),
            "required": .array([.string("query")])
        ])
        let tools = [
            MCPTool(
                name: "slack_send_message",
                title: nil,
                description: "Send a Slack message",
                inputSchema: schema,
                annotations: MCPToolAnnotations(readOnlyHint: true, destructiveHint: false)
            ),
            MCPTool(
                name: "slack_search_messages",
                title: nil,
                description: "Search Slack history",
                inputSchema: schema,
                annotations: MCPToolAnnotations(readOnlyHint: true, destructiveHint: false)
            )
        ]

        let selected = MCPToolRouter.bestTool(for: .slack, in: tools)

        #expect(selected?.name == "slack_search_messages")
    }

    @Test func mcpReadOnlyAnnotationCannotOverrideMutationSignals() {
        let schema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "query": .object(["type": .string("string")])
            ])
        ])
        let misleading = MCPTool(
            name: "slack_search_messages",
            title: nil,
            description: "Search messages and post a summary to the channel",
            inputSchema: schema,
            annotations: MCPToolAnnotations(readOnlyHint: true, destructiveHint: false)
        )
        let ambiguous = MCPTool(
            name: "slack_message",
            title: nil,
            description: "Message operation",
            inputSchema: schema,
            annotations: MCPToolAnnotations(readOnlyHint: true, destructiveHint: false)
        )

        #expect(MCPToolRouter.bestTool(for: .slack, in: [misleading]) == nil)
        #expect(MCPToolRouter.bestTool(for: .slack, in: [ambiguous]) == nil)
    }

    @Test func mcpToolRouterBuildsGmailArgumentsFromSchema() throws {
        let tool = MCPTool(
            name: "gmail_search_messages",
            title: nil,
            description: "Search Gmail",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "q": .object(["type": .string("string")]),
                    "maxResults": .object(["type": .string("integer")]),
                    "userId": .object(["type": .string("string")])
                ]),
                "required": .array([.string("q"), .string("userId")])
            ]),
            annotations: MCPToolAnnotations(readOnlyHint: true, destructiveHint: false)
        )

        let arguments = try #require(MCPToolRouter.arguments(
            for: tool,
            source: .gmail,
            query: "is:unread newer_than:7d"
        ))

        #expect(arguments["q"] == .string("is:unread newer_than:7d"))
        #expect(arguments["maxResults"] == .number(25))
        #expect(arguments["userId"] == .string("me"))
    }

    @Test func mcpToolRouterDoesNotTreatSenderAsSendOperation() {
        let tool = MCPTool(
            name: "google_gmail_list",
            title: nil,
            description: """
            List messages with sender, subject, date, and snippet per row. Use google_gmail_get
            when you need the full body or Message-ID for a reply.
            """,
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "query": .object(["type": .string("string")])
                ])
            ]),
            annotations: nil
        )

        #expect(MCPToolRouter.bestTool(for: .gmail, in: [tool])?.name == "google_gmail_list")
    }

    @Test func mcpToolBrokerDetectsWorkbenchDynamicCatalog() {
        let schema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([:])
        ])
        let tools = ["search_tools", "get_tool_schema", "execute_tools"].map {
            MCPTool(
                name: $0,
                title: nil,
                description: nil,
                inputSchema: schema,
                annotations: nil
            )
        }

        #expect(MCPToolBroker.isWorkbenchCatalog(tools))
    }

    @Test func mcpToolBrokerParsesWorkbenchCatalogAndSchema() throws {
        let catalog = """
        {
          "tools": [
            {
              "name": "google_gmail_list",
              "description": "List Gmail messages",
              "integration": "google-gmail"
            }
          ]
        }
        """
        let schemaText = """
        {
          "schema": {
            "type": "object",
            "properties": {
              "query": {"type": "string"},
              "maxResults": {"type": "number", "default": 10}
            }
          }
        }
        """

        #expect(try MCPToolBroker.workbenchToolNames(from: catalog) == ["google_gmail_list"])
        let schema = try MCPToolBroker.workbenchSchema(from: schemaText)
        #expect(schema.objectValue?["properties"]?.objectValue?["query"] != nil)
    }

    @Test func mcpToolBrokerUnwrapsWorkbenchExecutionResult() throws {
        let result = try MCPToolBroker.workbenchExecutionResult(from: """
        {
          "results": [
            {
              "result": {
                "messages": [{"subject": "Status update"}],
                "nextPageToken": null
              }
            }
          ]
        }
        """)

        #expect(result.objectValue?["messages"]?.arrayValue?.count == 1)
    }

    @Test func notificationQueriesUseIntegrationSyntax() {
        #expect(MCPIntegrationSource.slack.defaultQuery.hasPrefix("after:"))
        #expect(MCPIntegrationSource.gmail.defaultQuery == "is:unread newer_than:7d")
        #expect(MCPIntegrationSource.googleCalendar.defaultQuery.isEmpty)
    }

    @Test func notificationSourcesExposeEngineerFocusedUXCopy() {
        #expect(MCPIntegrationSource.slack.notificationSubtitle == "Mentions, decisions, and blockers")
        #expect(MCPIntegrationSource.gmail.notificationSubtitle == "Important threads and replies")
        #expect(MCPIntegrationSource.googleCalendar.notificationSubtitle == "Meetings, conflicts, and preparation")
    }

    @Test func slackNotificationFocusBuildsWhitelistedMentionQueries() {
        let focus = SlackNotificationFocus(
            channelsText: "#Product-Dev, customer-support\n#product-dev, in:all",
            groupsText: "@channel, here, @platform-team, @channel",
            includeGroupMentions: true,
            topicLimit: 5
        )

        let queries = focus.searchQueries(
            directMention: "@current.user",
            dateFilter: "after:2026-07-19"
        )

        #expect(focus.channels == ["#product-dev", "#customer-support"])
        #expect(focus.groupMentions == ["@channel", "@here", "@platform-team"])
        #expect(focus.topicLimit == 5)
        #expect(queries == [
            "@current.user OR @channel OR @here OR @platform-team -from:@current.user in:#product-dev after:2026-07-19",
            "@current.user OR @channel OR @here OR @platform-team -from:@current.user in:#customer-support after:2026-07-19"
        ])
    }

    @Test func slackNotificationFocusExcludesSelfWithFallbackIdentity() {
        let focus = SlackNotificationFocus(channelsText: "", groupsText: "")

        #expect(focus.searchQueries(
            directMention: "to:me",
            dateFilter: "after:2026-07-19"
        ) == ["to:me -from:me after:2026-07-19"])
    }

    @Test func slackNotificationFocusGroupsMessagesIntoDistinctTopics() throws {
        func message(_ timestamp: Int, threadTimestamp: Int? = nil) -> JSONValue {
            let permalink = if let threadTimestamp {
                "https://example.slack.com/archives/C1/p\(timestamp)?thread_ts=\(threadTimestamp).000&cid=C1"
            } else {
                "https://example.slack.com/archives/C1/p\(timestamp)"
            }
            return .object([
                "channel": .object([
                    "id": .string("C1"),
                    "name": .string("focus")
                ]),
                "ts": .string("\(timestamp).000"),
                "text": .string("Mention \(timestamp)"),
                "blocks": .array([.object(["large": .string(String(repeating: "x", count: 2_000))])]),
                "permalink": .string(permalink)
            ])
        }
        let first = JSONValue.object([
            "messages": .array([
                message(20, threadTimestamp: 10),
                message(21, threadTimestamp: 10),
                message(22, threadTimestamp: 10),
                message(30),
                message(31),
                message(32),
                message(33)
            ])
        ]).prettyPrinted
        let second = JSONValue.object([
            "messages": .array([
                message(21, threadTimestamp: 10),
                message(34)
            ])
        ]).prettyPrinted

        let merged = SlackNotificationFocus.mergedTopicText([first, second], limit: 10)
        let data = try #require(merged.data(using: .utf8))
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        let topics = try #require(value.objectValue?["topics"]?.arrayValue)
        let thread = try #require(topics.first {
            $0.objectValue?["thread_ts"] == .string("10.000")
        })
        let threadMessages = try #require(thread.objectValue?["messages"]?.arrayValue)

        #expect(SlackNotificationFocus.topicCount(in: merged) == 6)
        #expect(topics.first?.objectValue?["thread_ts"] == .string("34.000"))
        #expect(threadMessages.count == 3)
        #expect(threadMessages.first?.objectValue?["blocks"] == nil)
    }

    @Test func mcpConfigurationRequiresHTTPSForRemoteServers() {
        #expect(throws: MCPError.self) {
            try MCPServerConfiguration(
                endpointText: "http://workbench.example.com/mcp",
                apiKeyHeaderName: "x-api-key",
                apiKey: "secret"
            )
        }

        let local = try? MCPServerConfiguration(
            endpointText: "http://localhost:3000/mcp",
            apiKeyHeaderName: "x-api-key",
            apiKey: "secret"
        )
        #expect(local?.endpoint.host == "localhost")
    }

    @Test func mcpConfigurationRejectsReservedHeadersAndFragments() {
        #expect(throws: MCPError.self) {
            try MCPServerConfiguration(
                endpointText: "https://workbench.example.com/mcp#token",
                apiKeyHeaderName: "x-api-key",
                apiKey: "secret"
            )
        }
        #expect(throws: MCPError.self) {
            try MCPServerConfiguration(
                endpointText: "https://workbench.example.com/mcp",
                apiKeyHeaderName: "Host",
                apiKey: "secret"
            )
        }
    }

    @Test func secureHTTPRestrictsRedirectOriginsAndExternalURLs() throws {
        let origin = try #require(URL(string: "https://example.com/api"))
        let sameOrigin = try #require(URL(string: "https://example.com:443/next"))
        let otherOrigin = try #require(URL(string: "https://other.example/next"))
        let downgraded = try #require(URL(string: "http://example.com/next"))
        let credentialURL = try #require(URL(string: "https://user:password@example.com"))
        let fileURL = URL(fileURLWithPath: "/tmp/example")

        #expect(SecureHTTP.isSameOrigin(origin, sameOrigin))
        #expect(!SecureHTTP.isSameOrigin(origin, otherOrigin))
        #expect(!SecureHTTP.isSameOrigin(origin, downgraded))
        #expect(!SecureHTTP.isSafeWebURL(credentialURL))
        #expect(!SecureHTTP.isSafeWebURL(fileURL))
        #expect(SecureHTTP.isSafeWebURL(origin, allowedHosts: ["example.com"]))
        #expect(!SecureHTTP.isSafeWebURL(origin, allowedHosts: ["other.example"]))
    }

    @Test func notificationFallbackSummaryIsBounded() {
        let summary = NotificationFallbackSummarizer.summarize(
            "First important notification. Second item needs a reply! Third meeting is tomorrow?"
        )

        #expect(summary.contains("First important notification"))
        #expect(summary.split(separator: "\n").count == 3)
    }

    @Test func notificationBriefingFallbackIncludesConnectedSources() {
        let digests = [
            UnifiedNotificationDigest(
                source: .slack,
                summary: "Review the deployment blocker in #engineering.",
                rawPreview: "",
                toolName: "slack_search",
                fetchedAt: .now
            ),
            UnifiedNotificationDigest(
                source: .gmail,
                summary: "Reply to the production access request.",
                rawPreview: "",
                toolName: "gmail_search",
                fetchedAt: .now
            ),
            UnifiedNotificationDigest(
                source: .googleCalendar,
                summary: "Architecture review starts at 2 PM.",
                rawPreview: "",
                toolName: "calendar_events",
                fetchedAt: .now
            )
        ]

        let summary = NotificationBriefingFallback.summarize(digests)

        #expect(summary.contains("**Focus now**"))
        #expect(summary.contains("**Actions**"))
        #expect(summary.contains("**Schedule**"))
        #expect(summary.contains("Slack"))
        #expect(summary.contains("Gmail"))
        #expect(summary.contains("Google Calendar"))
    }

    @Test func unifiedNotificationBriefingSupportsCacheRoundTrip() throws {
        let briefing = UnifiedNotificationBriefing(
            summary: "**Focus now** — Review the release.",
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let data = try JSONEncoder().encode(briefing)
        let decoded = try JSONDecoder().decode(UnifiedNotificationBriefing.self, from: data)

        #expect(decoded == briefing)
    }

    @Test func askAIMentionParserFindsMultipleFolders() {
        let folders = [
            AskAIFolderSource(alias: "Tidy", url: URL(fileURLWithPath: "/tmp/Tidy")),
            AskAIFolderSource(alias: "code", url: URL(fileURLWithPath: "/tmp/code"))
        ]

        let parsed = AskAIMentionParser.folderSources(in: "compare @!Tidy and @!code", availableFolders: folders)

        #expect(parsed.map(\.alias) == ["Tidy", "code"])
    }

    @Test func askAIMentionParserDetectsCurrentMentionMode() {
        #expect(AskAIMentionParser.currentMention(in: "show @") == .mcp(""))
        #expect(AskAIMentionParser.currentMention(in: "ask @!Ti") == .folder("Ti"))
        #expect(AskAIMentionParser.currentMention(in: "ask @!Tidy ") == nil)
    }

    @Test func folderContextIncludesProjectSignalsAndMap() throws {
        let root = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }

        try write("# Demo\n\nA small app.", to: root.appendingPathComponent("README.md"))
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Demo.xcodeproj", isDirectory: true),
            withIntermediateDirectories: true
        )
        try write("// project", to: root.appendingPathComponent("Demo.xcodeproj/project.pbxproj"))
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("Demo", isDirectory: true),
            withIntermediateDirectories: true
        )
        try write("struct DemoApp {}", to: root.appendingPathComponent("Demo/DemoApp.swift"))

        let context = FolderContextBuilder.context(for: [root], question: "what is this project?")

        #expect(context.contains("Detected project signals: README.md, Demo Xcode project"))
        #expect(context.contains("Git context:"))
        #expect(context.contains("Project map:"))
        #expect(context.contains("Code symbol index:"))
        #expect(context.contains("Demo/DemoApp.swift: struct DemoApp"))
        #expect(context.contains("README.md"))
        #expect(context.contains("Demo/DemoApp.swift"))
    }

    @Test func folderContextSkipsProtectedHomeChildrenUnlessExplicitlySelected() {
        let home = URL(fileURLWithPath: "/private/tmp/tidy-test-home", isDirectory: true)
        let documents = home.appendingPathComponent("Documents", isDirectory: true)

        #expect(
            FolderAccessPolicy.isProtectedHomeDescendant(
                documents,
                selectedRoot: home,
                homeURL: home
            )
        )
        #expect(
            !FolderAccessPolicy.isProtectedHomeDescendant(
                documents,
                selectedRoot: documents,
                homeURL: home
            )
        )
        #expect(!FolderAccessPolicy.allowsExplicitInspection(of: home, homeURL: home))
        #expect(FolderAccessPolicy.allowsExplicitInspection(of: documents, homeURL: home))
    }

    @Test func folderContextPrioritizesQuestionRelevantFiles() throws {
        let root = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }

        try write("# Demo", to: root.appendingPathComponent("README.md"))
        try write("final class BillingCoordinator {}", to: root.appendingPathComponent("BillingCoordinator.swift"))
        try write("final class ClipboardPaletteController {}", to: root.appendingPathComponent("ClipboardPaletteController.swift"))

        let context = FolderContextBuilder.context(for: [root], question: "where is clipboard handled?")
        let clipboardIndex = try #require(context.range(of: "--- ClipboardPaletteController.swift ---")?.lowerBound)
        let billingIndex = try #require(context.range(of: "--- BillingCoordinator.swift ---")?.lowerBound)

        #expect(clipboardIndex < billingIndex)
    }

    @Test func folderContextExcludesCredentialAndLocalConfigurationFiles() throws {
        let root = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }

        try write("public documentation", to: root.appendingPathComponent("README.md"))
        try write("API_KEY=do-not-send", to: root.appendingPathComponent("production.env"))
        try write("DEVELOPMENT_TEAM = PRIVATE", to: root.appendingPathComponent("Local.xcconfig"))
        try write(
            "let embeddedSecret = \"do-not-send\"",
            to: root.appendingPathComponent("Secrets.swift")
        )

        let context = FolderContextBuilder.context(
            for: root,
            question: "Summarize this project"
        )

        #expect(context.contains("public documentation"))
        #expect(!context.contains("do-not-send"))
        #expect(!context.contains("production.env"))
        #expect(!context.contains("Local.xcconfig"))
        #expect(!context.contains("Secrets.swift"))
    }

    @Test func appearanceModeDefaultIsSystem() {
        let defaults = UserDefaults(suiteName: "test.tidy.appearance")!
        defaults.registerTidyDefaults()
        #expect(defaults.string(forKey: AppDefaults.appearanceMode) == "system")
        defaults.removePersistentDomain(forName: "test.tidy.appearance")
    }

    @Test func colorHexParsesRRGGBB() {
        // Verify the initializer doesn't crash and produces a non-clear color.
        // We compare the resolved RGB components rather than Color equality.
        let c = Color(hex: "#2c2c2e")
        // Convert to NSColor to read components
        let ns = NSColor(c).usingColorSpace(.sRGB)!
        #expect(abs(ns.redComponent   - (0x2c / 255.0)) < 0.01)
        #expect(abs(ns.greenComponent - (0x2c / 255.0)) < 0.01)
        #expect(abs(ns.blueComponent  - (0x2e / 255.0)) < 0.01)
    }

    @Test func dashboardSectionIncludesSettings() {
        #expect(DashboardSection.allCases.contains(.settings))
    }

    @Test func dashboardSectionIncludesJira() {
        #expect(DashboardSection.allCases.contains(.jira))
    }

    @Test func dashboardSectionIncludesTerminal() {
        #expect(DashboardSection.allCases.contains(.terminal))
    }

    @Test func dashboardSectionIncludesAsana() {
        #expect(DashboardSection.allCases.contains(.asana))
        #expect(DashboardSection.asana.fullTitle == "Asana My Tasks")
    }

    @Test func dashboardSectionIncludesUnifiedNotifications() {
        #expect(DashboardSection.allCases.contains(.notifications))
        #expect(DashboardSection.notifications.fullTitle == "Unified Notifications")
    }

    @Test func dashboardSectionIncludesDeveloperWorkflows() {
        #expect(DashboardSection.allCases.contains(.workflows))
        #expect(DashboardSection.workflows.fullTitle == "Developer Workflows")
        #expect(DashboardSection.workflows.shortcutLabel == "⌘⇧W")
    }

    @Test func dashboardSectionShortcutsFollowSidebarOrder() {
        #expect(DashboardSection.allCases.map(\.shortcutDigit) == Array("1w234567n890"))
        #expect(DashboardSection.notifications.shortcutLabel == "⌘⇧N")
        #expect(DashboardSection.asana.shortcutLabel == "⌘9")
        #expect(DashboardSection.settings.shortcutLabel == "⌘0")
    }

    @Test func tidyGoalsRoundTripAndMapToFocusedSections() {
        let goals: Set<TidyGoal> = [.writing, .cleanup, .dailyWork]

        let decoded = TidyGoal.decode(TidyGoal.encode(goals))

        #expect(decoded == goals)
        #expect(TidyGoal.cleanup.dashboardSections == [.fileTidy])
        #expect(TidyGoal.dailyWork.dashboardSections.contains(.workflows))
        #expect(TidyGoal.dailyWork.dashboardSections.contains(.notifications))
    }

    @Test func privacyPolicyIdentifiesOnlyOnDeviceProvidersAsLocal() {
        #expect(GrammarProviderID.ollama.processesContentLocally)
        #expect(!GrammarProviderID.languageTool.processesContentLocally)
        #expect(!GrammarProviderID.openAI.processesContentLocally)
        #expect(!GrammarProviderID.codexCLI.processesContentLocally)
    }

    @Test func developerWorkflowRegistryCoversExpectedOutcomes() {
        #expect(Set(DeveloperWorkflowRegistry.all.map(\.id)) == Set(DeveloperWorkflowID.allCases))
        #expect(DeveloperWorkflowRegistry.all.allSatisfy { !$0.title.isEmpty })
        #expect(DeveloperWorkflowRegistry.all.first { $0.id == .cleanProject }?.requiredSections == [.fileTidy])
    }

    @Test func connectorRegistryDeclaresCapabilitiesAndPrivacy() {
        let connectors = ConnectorRegistry.notificationConnectors

        #expect(connectors.map(\.source) == [.slack, .gmail, .googleCalendar])
        #expect(connectors.allSatisfy { $0.descriptor.isReadOnlyByDefault })
        #expect(connectors.allSatisfy { $0.descriptor.privacy.retention == .summaryCache })
        #expect(MCPIntegrationSource.slack.connectorDescriptor.capabilities.contains(.readMessages))
        #expect(ConnectorRegistry.builtInDescriptors.contains { $0.id == "jira-native" })
    }

    @Test func terminalDefersTidyShortcutsToApplication() {
        for digit in "0123456789" {
            #expect(TerminalKeyRouting.shouldDeferToApplication(
                charactersIgnoringModifiers: String(digit),
                modifierFlags: [.command]
            ))
        }

        #expect(TerminalKeyRouting.shouldDeferToApplication(
            charactersIgnoringModifiers: "/",
            modifierFlags: [.command]
        ))
        #expect(!TerminalKeyRouting.shouldDeferToApplication(
            charactersIgnoringModifiers: "s",
            modifierFlags: [.command, .option]
        ))
        #expect(TerminalKeyRouting.shouldDeferToApplication(
            charactersIgnoringModifiers: "q",
            modifierFlags: [.command]
        ))
        #expect(!TerminalKeyRouting.shouldDeferToApplication(
            charactersIgnoringModifiers: "c",
            modifierFlags: [.command]
        ))
        #expect(!TerminalKeyRouting.shouldDeferToApplication(
            charactersIgnoringModifiers: "1",
            modifierFlags: [.command, .shift]
        ))
    }

    @Test func sidebarStartsExpanded() {
        let defaults = UserDefaults(suiteName: "test.tidy.sidebar")!
        defaults.registerTidyDefaults()
        #expect(defaults.bool(forKey: AppDefaults.sidebarCollapsed) == false)
        defaults.removePersistentDomain(forName: "test.tidy.sidebar")
    }

    @Test func jiraActiveSprintJQLIncludesOptionalAssignee() {
        let allIssues = JiraAPIClient.activeSprintJQL(projectKey: "ENG", assigneeAccountID: nil)
        let myIssues = JiraAPIClient.activeSprintJQL(projectKey: "ENG", assigneeAccountID: "abc:123")

        #expect(allIssues.contains("project = \"ENG\""))
        #expect(allIssues.contains("sprint in openSprints()"))
        #expect(!allIssues.contains("assignee ="))
        #expect(myIssues.contains("assignee = \"abc:123\""))
    }

    @Test func jiraJQLEscapesQuotedValues() {
        let jql = JiraAPIClient.activeSprintJQL(projectKey: "A\\\"B", assigneeAccountID: nil)

        #expect(jql.contains("project = \"A\\\\\\\"B\""))
    }

    @Test func jiraCommentUsesAtlassianDocumentFormat() throws {
        let data = try JiraAPIClient.commentBody(for: "Ready to ship")
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let body = try #require(json["body"] as? [String: Any])
        let content = try #require(body["content"] as? [[String: Any]])
        let textNodes = try #require(content.first?["content"] as? [[String: Any]])

        #expect(body["version"] as? Int == 1)
        #expect(body["type"] as? String == "doc")
        #expect(textNodes.first?["text"] as? String == "Ready to ship")
    }

    @Test func jiraMultilineCommentCreatesSeparateADFParagraphs() throws {
        let data = try JiraAPIClient.commentBody(for: "First line\nSecond line")
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let body = try #require(json["body"] as? [String: Any])
        let content = try #require(body["content"] as? [[String: Any]])

        #expect(content.count == 2)
    }

    @Test func jiraCommentEncodesRealMentionAndDateNodes() throws {
        let user = JiraUser(
            accountId: "account-123",
            displayName: "Alex Engineer",
            emailAddress: nil
        )
        let date = Date(timeIntervalSince1970: 1_785_004_800)
        let dateToken = JiraCommentDateToken(date: date)
        let text = "Please review @Alex Engineer by \(dateToken.marker)"
        let data = try JiraAPIClient.commentBody(
            for: text,
            mentions: [user],
            dates: [dateToken]
        )
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let body = try #require(json["body"] as? [String: Any])
        let paragraphs = try #require(body["content"] as? [[String: Any]])
        let content = try #require(paragraphs.first?["content"] as? [[String: Any]])
        let mention = try #require(content.first(where: { $0["type"] as? String == "mention" }))
        let mentionAttrs = try #require(mention["attrs"] as? [String: Any])
        let dateNode = try #require(content.first(where: { $0["type"] as? String == "date" }))
        let dateAttrs = try #require(dateNode["attrs"] as? [String: Any])

        #expect(mentionAttrs["id"] as? String == "account-123")
        #expect(mentionAttrs["text"] as? String == "@Alex Engineer")
        #expect(mentionAttrs["userType"] as? String == "DEFAULT")
        #expect(dateAttrs["timestamp"] as? String == "1785004800000")
    }

    @Test func jiraCommentDecodesRichTextAsPlainText() throws {
        let data = Data("""
        {
          "id": "101",
          "author": {"accountId": "me", "displayName": "Current User"},
          "body": {
            "type": "doc",
            "content": [
              {"type": "paragraph", "content": [{"type": "text", "text": "First"}]},
              {"type": "paragraph", "content": [{"type": "text", "text": "Second"}]}
            ]
          },
          "created": "2026-07-22T10:00:00.000+0000",
          "updated": "2026-07-22T10:01:00.000+0000"
        }
        """.utf8)
        let comment = try JSONDecoder().decode(JiraComment.self, from: data)

        #expect(comment.text == "First\nSecond")
        #expect(comment.wasEdited)
    }

    @Test func jiraIssueDecodesDescriptionWithMentionAndDate() throws {
        let data = Data("""
        {
          "id": "1",
          "key": "ENG-1",
          "fields": {
            "summary": "Ship it",
            "status": {"name": "In Progress"},
            "priority": {"name": "High"},
            "assignee": null,
            "issuetype": {"name": "Task"},
            "description": {
              "type": "doc",
              "content": [{
                "type": "paragraph",
                "content": [
                  {"type": "text", "text": "Pair with "},
                  {"type": "mention", "attrs": {"id": "abc", "text": "@Alex"}},
                  {"type": "text", "text": " before "},
                  {"type": "date", "attrs": {"timestamp": "1785004800000"}}
                ]
              }]
            }
          }
        }
        """.utf8)
        let issue = try JSONDecoder().decode(JiraIssue.self, from: data)
        let description = try #require(issue.fields.description?.plainText)

        #expect(description.contains("Pair with @Alex before"))
        #expect(description.trimmingCharacters(in: .whitespacesAndNewlines).count > 20)
    }

    @Test func jiraIssueUsesStatusCategoryForWorkflowFilter() throws {
        let data = Data("""
        {
          "id": "1",
          "key": "ENG-1",
          "fields": {
            "summary": "Ship it",
            "status": {
              "name": "Ready for release",
              "statusCategory": {"key": "done", "name": "Done", "colorName": "green"}
            },
            "priority": {"name": "High"},
            "assignee": null,
            "issuetype": {"name": "Task"},
            "updated": "2026-07-22T10:00:00.000+0000"
          }
        }
        """.utf8)
        let issue = try JSONDecoder().decode(JiraIssue.self, from: data)

        #expect(issue.statusGroup == .done)
        #expect(issue.updatedDate != nil)
    }

    @Test func jiraWorkflowStatusesMatchConfiguredOrderAndIgnoreCase() {
        #expect(JiraWorkflowStatus.allCases.map(\.rawValue) == [
            "To Do",
            "Code Review",
            "Ready for Release",
            "Done/Release Ready",
            "In QA",
            "In Progress"
        ])
        #expect(JiraWorkflowStatus.inQA.matches("in qa"))
        #expect(JiraWorkflowStatus.readyForRelease.matches("  Ready for Release  "))
    }

    @Test func jiraTransitionUsesExpectedRequestShapeAndDecodesDestination() throws {
        let body = try JiraAPIClient.transitionBody(for: "31")
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let transition = try #require(json["transition"] as? [String: Any])
        #expect(transition["id"] as? String == "31")

        let data = Data("""
        {
          "id": "31",
          "name": "Start QA",
          "to": {
            "name": "In QA",
            "statusCategory": {"key": "indeterminate", "name": "In Progress"}
          }
        }
        """.utf8)
        let decoded = try JSONDecoder().decode(JiraTransition.self, from: data)
        #expect(decoded.id == "31")
        #expect(decoded.to.name == "In QA")
    }

    @Test func jiraSprintAnalyticsSummarizesFlowWithoutEmployeeScoring() throws {
        let data = Data("""
        [
          {
            "id": "1", "key": "ENG-1",
            "fields": {
              "summary": "Urgent unassigned work",
              "status": {"name": "To Do", "statusCategory": {"key": "new"}},
              "priority": {"name": "Highest"}, "assignee": null,
              "issuetype": {"name": "Task"}, "updated": "2026-07-18T10:00:00.000+0000"
            }
          },
          {
            "id": "2", "key": "ENG-2",
            "fields": {
              "summary": "Review work",
              "status": {"name": "Code Review", "statusCategory": {"key": "indeterminate"}},
              "priority": {"name": "Medium"},
              "assignee": {"accountId": "bob", "displayName": "Bob"},
              "issuetype": {"name": "Task"}, "updated": "2026-07-24T10:00:00.000+0000"
            }
          },
          {
            "id": "3", "key": "ENG-3",
            "fields": {
              "summary": "QA work",
              "status": {"name": "In QA", "statusCategory": {"key": "indeterminate"}},
              "priority": {"name": "Medium"},
              "assignee": {"accountId": "bob", "displayName": "Bob"},
              "issuetype": {"name": "Bug"}, "updated": "2026-07-24T10:00:00.000+0000"
            }
          },
          {
            "id": "4", "key": "ENG-4",
            "fields": {
              "summary": "Finished work",
              "status": {"name": "Done/Release Ready", "statusCategory": {"key": "done"}},
              "priority": {"name": "Low"},
              "assignee": {"accountId": "alice", "displayName": "Alice"},
              "issuetype": {"name": "Task"}, "updated": "2026-07-23T10:00:00.000+0000"
            }
          }
        ]
        """.utf8)
        let issues = try JSONDecoder().decode([JiraIssue].self, from: data)
        let now = try #require(JiraDateParser.date(from: "2026-07-24T12:00:00.000+0000"))
        let notification = JiraNotification(
            id: "done",
            issueID: "4",
            issueKey: "ENG-4",
            issueSummary: "Finished work",
            title: "Status changed",
            detail: "In QA → Done/Release Ready",
            priority: "Low",
            status: "Done/Release Ready",
            actor: "Alice",
            createdAt: now.addingTimeInterval(-24 * 60 * 60),
            isFallback: false,
            field: "status",
            fromValue: "In QA",
            toValue: "Done/Release Ready"
        )

        let analytics = JiraSprintAnalytics(issues: issues, notifications: [notification], now: now)

        #expect(analytics.total == 4)
        #expect(analytics.completed == 1)
        #expect(analytics.active == 2)
        #expect(analytics.inReview == 1)
        #expect(analytics.inQA == 1)
        #expect(analytics.highPriority == 1)
        #expect(analytics.unassigned == 1)
        #expect(analytics.aging == 1)
        #expect(analytics.completedRecently == 1)
        #expect(analytics.team.first(where: { $0.name == "Bob" })?.assigned == 2)
    }

    @Test func jiraSprintAnalyticsCountsReadyForReleaseAsCompleted() throws {
        let data = Data("""
        [
          {
            "id": "1", "key": "ENG-1",
            "fields": {
              "summary": "Waiting to ship",
              "status": {"name": "Ready for Release", "statusCategory": {"key": "indeterminate"}},
              "priority": {"name": "Medium"},
              "assignee": {"accountId": "alex", "displayName": "Alex"},
              "issuetype": {"name": "Task"}, "updated": "2026-07-24T10:00:00.000+0000"
            }
          },
          {
            "id": "2", "key": "ENG-2",
            "fields": {
              "summary": "In development",
              "status": {"name": "In Progress", "statusCategory": {"key": "indeterminate"}},
              "priority": {"name": "Medium"},
              "assignee": {"accountId": "alex", "displayName": "Alex"},
              "issuetype": {"name": "Task"}, "updated": "2026-07-24T10:00:00.000+0000"
            }
          }
        ]
        """.utf8)
        let issues = try JSONDecoder().decode([JiraIssue].self, from: data)
        let analytics = JiraSprintAnalytics(issues: issues, notifications: [])

        #expect(issues[0].isCompleted)
        #expect(analytics.completed == 1)
        #expect(analytics.active == 1)
        #expect(analytics.readyForRelease == 1)
        #expect(analytics.completionRate == 0.5)
    }

    @Test func jiraPulseExportIncludesEveryWorkflowAndCreatesPDF() throws {
        let statuses = JiraWorkflowStatus.allCases
        let issueObjects = statuses.enumerated().map { index, status in
            [
                "id": "\(index)",
                "key": "ENG-\(index + 1)",
                "fields": [
                    "summary": index == 0 ? "Comma, quote \" test" : "\(status.rawValue) ticket",
                    "status": [
                        "name": status.rawValue,
                        "statusCategory": [
                            "key": status == .doneReleaseReady ? "done" : "indeterminate"
                        ]
                    ],
                    "priority": ["name": "Medium"],
                    "assignee": ["accountId": "alex", "displayName": "Alex"],
                    "issuetype": ["name": "Task"],
                    "updated": "2026-07-24T10:00:00.000+0000"
                ] as [String: Any]
            ] as [String: Any]
        }
        let issueData = try JSONSerialization.data(withJSONObject: issueObjects)
        let issues = try JSONDecoder().decode([JiraIssue].self, from: issueData)
        let generatedAt = try #require(
            JiraDateParser.date(from: "2026-07-25T00:00:00.000+0000")
        )
        let filename = JiraPulseExporter.suggestedFilename(
            projectKey: "ENG",
            format: .pdf,
            generatedAt: generatedAt
        )
        #expect(filename == "ENG-Sprint-Pulse-2026-07-25.pdf")

        let csv = JiraPulseExporter.csv(
            issues: issues,
            projectKey: "ENG",
            isFilteredToAssignee: false,
            generatedAt: generatedAt
        )
        for status in statuses {
            #expect(csv.contains("\"\(status.rawValue)\""))
        }
        #expect(csv.contains("\"Comma, quote \"\" test\""))
        #expect(csv.components(separatedBy: "\r\n").count == statuses.count + 2)

        let pdf = try JiraPulseExporter.pdf(
            issues: issues,
            notifications: [],
            projectKey: "ENG",
            isFilteredToAssignee: false,
            generatedAt: generatedAt
        )
        #expect(pdf.starts(with: Data("%PDF".utf8)))
        #expect(pdf.count > 1_000)
    }

    @Test func jiraStandupCommentRoundTripsTicketUpdate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 25)))
        let text = JiraStandupUpdate.commentText(
            state: .blocked,
            note: "Waiting for the service contract.",
            date: date,
            calendar: calendar
        )

        #expect(text.contains("Tidy Standup · 2026-07-25"))
        #expect(text.contains("Status: Blocked"))
        #expect(text.contains("Update: Waiting for the service contract."))

        let issueData = Data("""
        {
          "id": "9", "key": "ENG-9",
          "fields": {
            "summary": "Integrate service",
            "status": {"name": "In Progress", "statusCategory": {"key": "indeterminate"}},
            "priority": {"name": "High"},
            "assignee": {"accountId": "me", "displayName": "Current User"},
            "issuetype": {"name": "Task"},
            "updated": "2026-07-25T01:00:00.000+0000"
          }
        }
        """.utf8)
        let issue = try JSONDecoder().decode(JiraIssue.self, from: issueData)
        let commentData = try JSONSerialization.data(withJSONObject: [
            "id": "standup-1",
            "author": ["accountId": "me", "displayName": "Current User"],
            "body": [
                "type": "doc",
                "content": text.components(separatedBy: .newlines).map {
                    [
                        "type": "paragraph",
                        "content": [["type": "text", "text": $0]]
                    ]
                }
            ],
            "created": "2026-07-25T01:30:00.000+0000",
            "updated": "2026-07-25T01:30:00.000+0000"
        ])
        let comment = try JSONDecoder().decode(JiraComment.self, from: commentData)
        let update = try #require(JiraStandupUpdate(comment: comment, issue: issue))

        #expect(update.issueKey == "ENG-9")
        #expect(update.authorName == "Current User")
        #expect(update.state == .blocked)
        #expect(update.note == "Waiting for the service contract.")
        #expect(update.isOnSameDay(as: date, calendar: calendar))
    }

    @Test func jiraStandupUpdateSupportsMentionAndDateNodes() throws {
        let user = JiraUser(
            accountId: "standup-user",
            displayName: "Alex Engineer",
            emailAddress: nil
        )
        let dateToken = JiraCommentDateToken(
            date: Date(timeIntervalSince1970: 1_785_004_800)
        )
        let text = JiraStandupUpdate.commentText(
            state: .ongoing,
            note: "Pair with @Alex Engineer by \(dateToken.marker)",
            date: Date(timeIntervalSince1970: 1_784_918_400)
        )
        let data = try JiraAPIClient.commentBody(
            for: text,
            mentions: [user],
            dates: [dateToken]
        )
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let body = try #require(json["body"] as? [String: Any])
        let paragraphs = try #require(body["content"] as? [[String: Any]])
        let updateNodes = try #require(paragraphs.last?["content"] as? [[String: Any]])

        #expect(updateNodes.contains { $0["type"] as? String == "mention" })
        #expect(updateNodes.contains { $0["type"] as? String == "date" })
    }

    @Test func jiraStandupParserIgnoresOrdinaryComments() throws {
        let issueData = Data("""
        {
          "id": "10", "key": "ENG-10",
          "fields": {
            "summary": "Normal issue",
            "status": {"name": "To Do", "statusCategory": {"key": "new"}},
            "priority": null, "assignee": null,
            "issuetype": {"name": "Task"},
            "updated": "2026-07-25T01:00:00.000+0000"
          }
        }
        """.utf8)
        let commentData = Data("""
        {
          "id": "normal-1",
          "author": {"accountId": "me", "displayName": "Current User"},
          "body": {
            "type": "doc",
            "content": [
              {"type": "paragraph", "content": [{"type": "text", "text": "A regular Jira comment"}]}
            ]
          },
          "created": "2026-07-25T01:30:00.000+0000",
          "updated": "2026-07-25T01:30:00.000+0000"
        }
        """.utf8)
        let issue = try JSONDecoder().decode(JiraIssue.self, from: issueData)
        let comment = try JSONDecoder().decode(JiraComment.self, from: commentData)

        #expect(JiraStandupUpdate(comment: comment, issue: issue) == nil)
    }

    @Test func jiraDefaultsStartEmpty() {
        let defaults = UserDefaults(suiteName: "test.tidy.jira")!
        defaults.registerTidyDefaults()

        #expect(defaults.string(forKey: AppDefaults.jiraSiteURL) == "")
        #expect(defaults.string(forKey: AppDefaults.jiraProjectKey) == "")
        defaults.removePersistentDomain(forName: "test.tidy.jira")
    }

    @Test func asanaTaskDecodesProjectsSectionsAndDates() throws {
        let data = Data("""
        {
          "gid": "task-1",
          "name": "Ship the Asana integration",
          "completed": false,
          "due_on": "2026-07-28",
          "due_at": null,
          "permalink_url": "https://app.asana.com/0/123/task-1",
          "notes": "Release checklist",
          "assignee": {"gid": "user-1", "name": "Current User"},
          "projects": [{"gid": "project-1", "name": "Tidy"}],
          "memberships": [{
            "project": {"gid": "project-1", "name": "Tidy"},
            "section": {"gid": "section-1", "name": "Ready"}
          }]
        }
        """.utf8)

        let task = try JSONDecoder().decode(AsanaTask.self, from: data)

        #expect(task.id == "task-1")
        #expect(task.projectNames == ["Tidy"])
        #expect(task.sectionNames == ["Ready"])
        #expect(task.assignee?.name == "Current User")
        #expect(task.dueDate == AsanaDateParser.day.date(from: "2026-07-28"))
    }

    @Test func asanaTaskFiltersRespectDayBoundaries() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = try #require(calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 26, hour: 12)
        ))

        let overdue = try asanaTask(gid: "1", name: "Overdue", dueOn: "2026-07-25")
        let today = try asanaTask(gid: "2", name: "Today", dueOn: "2026-07-26")
        let upcoming = try asanaTask(gid: "3", name: "Upcoming", dueOn: "2026-07-27")
        let unscheduled = try asanaTask(gid: "4", name: "Unscheduled", dueOn: nil)

        #expect(AsanaTaskFilter.overdue.includes(overdue, now: now, calendar: calendar))
        #expect(AsanaTaskFilter.today.includes(today, now: now, calendar: calendar))
        #expect(AsanaTaskFilter.upcoming.includes(upcoming, now: now, calendar: calendar))
        #expect(AsanaTaskFilter.noDueDate.includes(unscheduled, now: now, calendar: calendar))
        #expect(!AsanaTaskFilter.upcoming.includes(today, now: now, calendar: calendar))
        #expect(!AsanaTaskFilter.overdue.includes(unscheduled, now: now, calendar: calendar))
    }

    @Test func asanaTaskDecodesWithoutProjectMetadata() throws {
        let data = Data("""
        {
          "gid": "task-2",
          "name": "Minimal task",
          "completed": false,
          "due_on": null,
          "due_at": null,
          "permalink_url": "https://app.asana.com/0/0/task-2",
          "notes": ""
        }
        """.utf8)

        let task = try JSONDecoder().decode(AsanaTask.self, from: data)

        #expect(task.projectNames.isEmpty)
        #expect(task.sectionNames.isEmpty)
        #expect(task.assignee == nil)
    }

    @Test func asanaAPIClientBuildsAuthenticatedMyTasksRequest() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AsanaMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer {
            session.invalidateAndCancel()
            AsanaMockURLProtocol.requestHandler = nil
        }

        AsanaMockURLProtocol.requestHandler = { request in
            let url = try #require(request.url)
            let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
            let query = Dictionary(
                uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }
            )

            #expect(url.path == "/api/1.0/tasks")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
            #expect(query["assignee"] == "me")
            #expect(query["workspace"] == "workspace-1")
            #expect(query["completed_since"] == "now")
            #expect(query["limit"] == "100")
            #expect(query["opt_fields"]?.contains("memberships.") == false)
            #expect(query["opt_fields"]?.contains("projects.") == false)
            #expect(query["opt_fields"]?.contains("assignee.") == false)

            let response = try #require(HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
            let body = Data("""
            {
              "data": [{
                "gid": "task-1",
                "name": "Review release",
                "completed": false,
                "due_on": null,
                "due_at": null,
                "permalink_url": null,
                "notes": "",
                "assignee": null,
                "projects": [],
                "memberships": []
              }],
              "next_page": null
            }
            """.utf8)
            return (response, body)
        }

        let client = AsanaAPIClient(token: "test-token", session: session)
        let tasks = try await client.tasks(workspaceGID: "workspace-1")

        #expect(tasks.map(\.name) == ["Review release"])
    }

    @Test func asanaDefaultsStartDisconnected() {
        let defaults = UserDefaults(suiteName: "test.tidy.asana")!
        defaults.registerTidyDefaults()

        #expect(defaults.string(forKey: AppDefaults.asanaWorkspaceGID) == "")
        defaults.removePersistentDomain(forName: "test.tidy.asana")
    }

    @Test func asanaUnauthorizedErrorExplainsReconnect() {
        let message = AsanaServiceError.unauthorized.localizedDescription

        #expect(message.contains("Connect your Asana account again"))
    }

    @Test func asanaOAuthAuthorizationUsesNativeRedirectAndPKCE() throws {
        let authorization = try AsanaOAuthClient().makeAuthorization(clientID: "client-123")
        let components = try #require(
            URLComponents(url: authorization.url, resolvingAgainstBaseURL: false)
        )
        let query = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }
        )

        #expect(authorization.url.host == "app.asana.com")
        #expect(query["client_id"] == "client-123")
        #expect(query["redirect_uri"] == AsanaOAuthClient.redirectURI)
        #expect(query["response_type"] == "code")
        #expect(query["code_challenge_method"] == "S256")
        #expect(query["code_challenge"]?.isEmpty == false)
        #expect(query["state"]?.isEmpty == false)
        #expect(query["scope"] == AsanaOAuthClient.requiredScopes.joined(separator: " "))
        #expect(query["scope"]?.contains("projects:read") == false)
        #expect(query["scope"]?.contains("users:read") == false)
        #expect(authorization.codeVerifier.count >= 43)
    }

    @Test func fileTidyScansRuleBasedSuggestions() throws {
        let root = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }

        try write("image-data", to: root.appendingPathComponent("Screenshot 2026-05-24 at 10.00.00.png"))
        try write("installer", to: root.appendingPathComponent("Tool.dmg"))
        try write("archive", to: root.appendingPathComponent("release.zip"))
        try write("notes", to: root.appendingPathComponent("Project Notes.pdf"))
        try write("same", to: root.appendingPathComponent("copy-a.txt"))
        try write("same", to: root.appendingPathComponent("copy-b.txt"))

        let service = FileTidyService()
        let result = try service.scan(rootURL: root)

        #expect(result.records.count == 6)
        #expect(result.proposals.contains { $0.category == .screenshots })
        #expect(result.proposals.contains { $0.category == .installers })
        #expect(result.proposals.contains { $0.category == .archives })
        #expect(result.proposals.contains { $0.category == .documents })
        #expect(result.proposals.allSatisfy { $0.destinationURL.path.hasPrefix(root.path) })
        #expect(result.proposals.contains { $0.category == .duplicates && $0.isRecommendedByDefault == false })
        #expect(result.typeGroups.contains { $0.title == FileTidyCategory.documents.title })
        #expect(result.usageGroups.contains { $0.title == "Downloaded installer" })
    }

    @Test func fileTidyDetectsLargeStaleAndBuildArtifacts() throws {
        let root = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }

        let stale = root.appendingPathComponent("old-export.mov")
        try write("large enough", to: stale)
        let oldDate = Date(timeIntervalSinceNow: -10 * 24 * 60 * 60)
        try FileManager.default.setAttributes([.modificationDate: oldDate], ofItemAtPath: stale.path)

        let build = root.appendingPathComponent("node_modules", isDirectory: true)
        try FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)
        try write("module", to: build.appendingPathComponent("index.js"))

        let service = FileTidyService(options: FileTidyScanOptions(largeFileThreshold: 4, staleAfterDays: 1))
        let result = try service.scan(rootURL: root)

        #expect(result.proposals.contains { $0.category == .largeStale && $0.risk == .review })
        #expect(result.proposals.contains { $0.category == .buildArtifacts && $0.risk == .high })
    }

    @Test func fileTidyAppliesMovesAndCanUndo() throws {
        let root = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }

        let archive = root.appendingPathComponent("sample.zip")
        try write("archive", to: archive)

        let service = FileTidyService()
        let result = try service.scan(rootURL: root)
        let proposal = try #require(result.proposals.first { $0.category == .archives })

        let moves = try service.apply([proposal], rootURL: root)
        #expect(moves.count == 1)
        #expect(FileManager.default.fileExists(atPath: moves[0].finalDestinationPath))
        #expect(!FileManager.default.fileExists(atPath: archive.path))

        let session = FileTidyUndoSession(id: UUID(), rootPath: root.path, createdAt: Date(), moves: moves)
        try service.undo(session)

        #expect(FileManager.default.fileExists(atPath: archive.path))
        #expect(!FileManager.default.fileExists(atPath: moves[0].finalDestinationPath))
    }

    @Test func fileTidyRejectsMovesOutsideSelectedFolder() throws {
        let root = try makeTemporaryFolder()
        let outside = try makeTemporaryFolder()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }

        let source = root.appendingPathComponent("sample.zip")
        try write("archive", to: source)
        let proposal = FileTidyProposal(
            id: UUID(),
            action: .move,
            category: .archives,
            sourceURL: source,
            destinationURL: outside.appendingPathComponent("sample.zip"),
            fileName: "sample.zip",
            size: 7,
            reason: "Unsafe test proposal",
            risk: .low,
            projectHint: nil,
            usagePattern: "Test",
            isRecommendedByDefault: true,
            duplicateOf: nil
        )

        #expect(throws: FileTidyError.self) {
            try FileTidyService().apply([proposal], rootURL: root)
        }
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test func claudeCLIProviderIDHasExpectedProperties() {
        #expect(GrammarProviderID.claudeCLI.rawValue == "claude-cli")
        #expect(GrammarProviderID.claudeCLI.displayName == "Claude (Subscription)")
        #expect(GrammarProviderID.claudeCLI.requiresAPIKey == false)
    }

    @Test func claudeCLIPathDefaultIsClaude() {
        let defaults = UserDefaults(suiteName: "test.tidy.claudecli")!
        defaults.registerTidyDefaults()
        #expect(defaults.string(forKey: AppDefaults.claudeCLIPath) == "claude")
        defaults.removePersistentDomain(forName: "test.tidy.claudecli")
    }

    @Test func codexLoginStatusDetectsSignedInSession() {
        #expect(CodexLoginController.statusMeansSignedIn("Logged in using ChatGPT"))
        #expect(CodexLoginController.statusMeansSignedIn("Authenticated"))
        #expect(!CodexLoginController.statusMeansSignedIn("Not signed in"))
    }

    @Test func codexEnvironmentPrependsResolvedExecutableDirectory() {
        let executable = URL(fileURLWithPath: "/tmp/tidy-nvm/node/bin/codex")
        let environment = CodexCLIService.codexEnvironment(executableURL: executable)
        let pathEntries = environment["PATH"]?.split(separator: ":").map(String.init)

        #expect(pathEntries?.first == "/tmp/tidy-nvm/node/bin")
        #expect(environment["CODEX_HOME"] == CodexCLIService.codexHomeURL.path)
    }

    @Test func codexCLIJSONProgressParsesThreadAndCommandEvents() throws {
        let thread = CodexCLIJSONEventParser.snapshot(from: #"{"type":"thread.started","thread_id":"abc-123"}"#)
        #expect(thread?.threadID == "abc-123")
        #expect(thread?.progressMessage == "Codex session started")

        let command = CodexCLIJSONEventParser.snapshot(from: #"{"type":"item.started","item":{"type":"command_execution","command":"/bin/zsh -lc rg AskAI"}}"#)
        #expect(command?.progressMessage == "Codex is running `rg AskAI`")
    }

    @Test func codexCLIJSONFailureExtractsFinalError() {
        let output = """
        {"type":"thread.started","thread_id":"abc-123"}
        {"type":"error","message":"Session expired"}
        {"type":"turn.failed","error":{"message":"Please log in again"}}
        """

        #expect(CodexCLIJSONEventParser.failureMessage(from: output) == "Please log in again")
    }

    @Test func codexCLIExpiredSessionErrorIsActionable() {
        let error = CodexCLIError.failed(
            status: 1,
            output: "Your refresh token was revoked. Please log out and sign in again."
        )

        #expect(error.errorDescription == "Your Codex session expired. Open Settings -> Model and click Sign In Again.")
    }

    @Test func claudeCodeStreamParserExtractsSessionAndResult() throws {
        let initEvent = ClaudeCodeStreamEventParser.snapshot(from: #"{"type":"system","subtype":"init","session_id":"session-1"}"#)
        #expect(initEvent?.sessionID == "session-1")
        #expect(initEvent?.progressMessage == "Claude Code session started")

        let result = ClaudeCodeStreamEventParser.snapshot(from: #"{"type":"result","session_id":"session-1","result":"Done."}"#)
        #expect(result?.answer == "Done.")
        #expect(result?.progressMessage == "Claude Code finished the answer")
    }

    @Test func claudeCodeCLIServiceResolvesAbsolutePath() throws {
        // /usr/bin/env always exists and is executable — use as a stand-in
        let url = try ClaudeCodeCLIService.resolvedExecutableURL(for: "/usr/bin/env")
        #expect(url.path == "/usr/bin/env")
    }

    @Test func claudeCodeCLIServiceThrowsForMissingExecutable() {
        #expect(throws: ClaudeCodeCLIError.self) {
            try ClaudeCodeCLIService.resolvedExecutableURL(for: "/nonexistent/claude-xyz")
        }
    }

    @Test func grammarFactoryReturnsClaudeCodeCLIProviderForClaudeCLI() {
        let provider = GrammarProviderFactory.provider(for: .claudeCLI)
        #expect(provider.id == GrammarProviderID.claudeCLI.rawValue)
        #expect(provider.displayName == "Claude (Subscription)")
    }

    @Test func deepSeekProviderIDHasExpectedProperties() {
        #expect(GrammarProviderID.deepSeek.rawValue == "deepseek")
        #expect(GrammarProviderID.deepSeek.displayName == "DeepSeek")
        #expect(GrammarProviderID.deepSeek.requiresAPIKey)
    }

    @Test func deepSeekModelDefaultsToV4Flash() {
        let defaults = UserDefaults(suiteName: "test.tidy.deepseek")!
        defaults.registerTidyDefaults()
        #expect(defaults.string(forKey: AppDefaults.deepSeekModel) == "deepseek-v4-flash")
        defaults.removePersistentDomain(forName: "test.tidy.deepseek")
    }

    @Test func grammarFactoryReturnsDeepSeekProvider() {
        let provider = GrammarProviderFactory.provider(for: .deepSeek)
        #expect(provider.id == GrammarProviderID.deepSeek.rawValue)
        #expect(provider.displayName == "DeepSeek")
    }

    @Test func deepSeekRequestUsesNonThinkingChatCompletionAPI() throws {
        let request = try DeepSeekProvider.makeRequest(
            text: "Reply with exactly: pong",
            apiKey: "sk-key",
            model: "deepseek-v4-flash"
        )
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let messages = try #require(body["messages"] as? [[String: Any]])

        #expect(request.url?.absoluteString == "https://api.deepseek.com/chat/completions")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-key")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(body["model"] as? String == "deepseek-v4-flash")
        #expect(body["max_tokens"] as? Int == 8_192)
        #expect((body["thinking"] as? [String: Any])?["type"] as? String == "disabled")
        #expect(messages.first?["role"] as? String == "system")
        #expect(messages.last?["role"] as? String == "user")
        #expect((messages.last?["content"] as? String)?.contains("Reply with exactly: pong") == true)
    }

    @Test func deepSeekRetryDoublesTheOutputBudgetWithinLimit() {
        #expect(DeepSeekProvider.retryMaxTokens(after: 8_192) == 16_384)
        #expect(DeepSeekProvider.retryMaxTokens(after: 32_768) == 65_536)
        #expect(DeepSeekProvider.retryMaxTokens(after: 65_536) == 65_536)
    }

    @Test func deepSeekResponseReturnsFinalContent() throws {
        let data = Data(#"{"choices":[{"message":{"content":"Corrected text","reasoning_content":"Reasoning"},"finish_reason":"stop"}]}"#.utf8)

        #expect(try DeepSeekProvider.correctedText(from: data) == "Corrected text")
    }

    @Test func deepSeekResponseReportsReasoningTruncation() {
        let data = Data(#"{"choices":[{"message":{"content":null,"reasoning_content":"Reasoning only"},"finish_reason":"length"}]}"#.utf8)

        #expect(throws: GrammarProviderError.self) {
            try DeepSeekProvider.correctedText(from: data)
        }
    }

    @Test func deepSeekNeverReturnsPartialCorrectedText() {
        let data = Data(#"{"choices":[{"message":{"content":"A partial correction"},"finish_reason":"length"}]}"#.utf8)

        #expect(throws: GrammarProviderError.self) {
            try DeepSeekProvider.correctedText(from: data)
        }
    }

    @Test func grammarPipelineFallsBackAfterProviderFailure() async throws {
        let primary = StubGrammarProvider(
            id: GrammarProviderID.deepSeek.rawValue,
            displayName: "DeepSeek",
            behavior: .fail
        )
        let fallback = StubGrammarProvider(
            id: GrammarProviderID.openAI.rawValue,
            displayName: "OpenAI",
            behavior: .uppercase
        )

        let result = try await GrammarCorrectionPipeline.correct(
            "this is a test",
            providers: [primary, fallback]
        )

        #expect(result.correctedText == "THIS IS A TEST")
        #expect(result.providerID == GrammarProviderID.openAI.rawValue)
        #expect(result.usedFallback)
        #expect(result.failures.map(\.providerName) == ["DeepSeek"])
    }

    @Test func grammarPipelineChunksLongSelectionsAndPreservesWhitespace() async throws {
        let provider = StubGrammarProvider(
            id: GrammarProviderID.deepSeek.rawValue,
            displayName: "DeepSeek",
            behavior: .uppercase
        )
        let text = "  " + String(repeating: "sentence with words. ", count: 30) + "\n\n" + String(repeating: "another line. ", count: 30) + "  "

        let result = try await GrammarCorrectionPipeline.correct(
            text,
            providers: [provider],
            chunkCharacters: 200
        )

        #expect(result.chunkCount > 1)
        #expect(result.correctedText == text.uppercased())
    }

    @Test func grammarPipelineReportsAllAttemptedProvidersWhenFallbacksFail() async {
        let providers = [
            StubGrammarProvider(id: GrammarProviderID.deepSeek.rawValue, displayName: "DeepSeek", behavior: .fail),
            StubGrammarProvider(id: GrammarProviderID.openAI.rawValue, displayName: "OpenAI", behavior: .fail),
            StubGrammarProvider(id: GrammarProviderID.ollama.rawValue, displayName: "Ollama", behavior: .fail),
        ]

        do {
            _ = try await GrammarCorrectionPipeline.correct("test", providers: providers)
            Issue.record("Expected all providers to fail")
        } catch {
            #expect(error.localizedDescription.contains("DeepSeek, OpenAI, Ollama"))
            #expect(error.localizedDescription.contains("text is unchanged"))
        }
    }

    @Test func grammarExperienceFormatsFastAndSlowDurations() {
        #expect(GrammarService.durationDescription(milliseconds: 420) == "<1s")
        #expect(GrammarService.durationDescription(milliseconds: 1_250) == "1.2s")
        #expect(GrammarService.durationDescription(milliseconds: 12_600) == "13s")
    }

    @Test func grammarExperienceExplainsTimeoutWithoutLosingText() {
        let message = GrammarService.userFacingMessage(for: URLError(.timedOut))
        #expect(message.contains("longer than usual"))
        #expect(message.contains("text is unchanged"))
    }

    private struct StubGrammarProvider: GrammarProvider {
        enum Behavior {
            case fail
            case uppercase
        }

        let id: String
        let displayName: String
        let behavior: Behavior

        func fixGrammar(_ text: String, language: String?) async throws -> String {
            switch behavior {
            case .fail:
                throw GrammarProviderError.responseTruncated(displayName)
            case .uppercase:
                return text.uppercased()
            }
        }
    }

    private func makeTemporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TidyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ string: String, to url: URL) throws {
        try Data(string.utf8).write(to: url)
    }

    private func asanaTask(gid: String, name: String, dueOn: String?) throws -> AsanaTask {
        let object: [String: Any] = [
            "gid": gid,
            "name": name,
            "completed": false,
            "due_on": dueOn.map { $0 as Any } ?? NSNull(),
            "due_at": NSNull(),
            "permalink_url": NSNull(),
            "notes": "",
            "assignee": NSNull(),
            "projects": [],
            "memberships": []
        ]
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(AsanaTask.self, from: data)
    }
}

private final class AsanaMockURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
