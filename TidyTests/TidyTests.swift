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
