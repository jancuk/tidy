//
//  TidyTests.swift
//  TidyTests
//
//  Created by Azhar Amir on 17/05/26.
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
        let home = FileManager.default.homeDirectoryForCurrentUser
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let documents = home.appendingPathComponent("Documents", isDirectory: true)

        #expect(FolderContextBuilder.isPrivacySensitiveDescendant(documents, rootURL: home))
        #expect(!FolderContextBuilder.isPrivacySensitiveDescendant(documents, rootURL: documents))
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

    @Test func deepSeekRequestMatchesAnthropicCompatibleAPI() throws {
        let request = try DeepSeekProvider.makeRequest(
            text: "Reply with exactly: pong",
            apiKey: "sk-key",
            model: "deepseek-v4-flash"
        )
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let messages = try #require(body["messages"] as? [[String: Any]])

        #expect(request.url?.absoluteString == "https://api.deepseek.com/anthropic/messages")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-key")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(body["model"] as? String == "deepseek-v4-flash")
        #expect(body["max_tokens"] as? Int == 1_024)
        #expect(messages.first?["role"] as? String == "user")
        #expect((messages.first?["content"] as? String)?.contains("Reply with exactly: pong") == true)
    }

    @Test func deepSeekResponseSkipsThinkingAndReturnsText() throws {
        let data = Data(#"{"content":[{"type":"thinking","thinking":"Reasoning"},{"type":"text","text":"Corrected text"}],"stop_reason":"end_turn"}"#.utf8)

        #expect(try DeepSeekProvider.correctedText(from: data) == "Corrected text")
    }

    @Test func deepSeekResponseReportsReasoningTruncation() {
        let data = Data(#"{"content":[{"type":"thinking","thinking":"Reasoning only"}],"stop_reason":"max_tokens"}"#.utf8)

        #expect(throws: GrammarProviderError.self) {
            try DeepSeekProvider.correctedText(from: data)
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
}
