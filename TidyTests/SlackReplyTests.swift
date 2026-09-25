import Foundation
import Testing
@testable import Tidy

@MainActor
struct SlackReplyTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private func message(_ ts: String = "1790000000.000001", text: String = "@alex.lee can you review this?", root: String = "1789999000.000001", user: String = "UOTHER") -> SlackReplyMessage {
        SlackReplyMessage(channelID: "C1", channelName: "engineering", ts: ts, threadTS: root, user: user, text: text,
                          permalink: "https://example.slack.com/archives/C1/p1790000000000001", isDM: false)
    }
    private func workspace(reader: FakeSlackReader? = nil, generator: FakeSlackGenerator? = nil, store: SlackReplyStore? = nil) throws -> SlackReplyService {
        let store = store ?? SlackReplyStore(directory: nil)
        var snapshot = SlackReplySnapshot()
        snapshot.settings.enabled = true
        snapshot.settings.userID = "UME"
        try store.save(snapshot)
        return SlackReplyService(store: store, reader: reader ?? FakeSlackReader(), generator: generator ?? FakeSlackGenerator(), clock: { now })
    }

    @Test func defaultCadenceIsHourlyAndSearchInputCannotInjectOperators() throws {
        let settings = SlackReplySettings()
        #expect(settings.refreshMinutes == 60)
        #expect(settings.autoRefresh)
        #expect(settings.names.isEmpty)
        #expect(try settings.validated().names.isEmpty)
        var invalid = settings
        invalid.enabled = true
        #expect(throws: SlackReplyError.self) { try invalid.validated() }
        invalid.aliases = "alex after:2000-01-01"
        #expect(throws: SlackReplyError.self) { try invalid.validated() }
        invalid.aliases = "@alex.lee, Alex Lee"
        #expect(try invalid.validated().names == ["Alex Lee", "alex.lee"])
        #expect(invalid.queries(since: now).count == 2)
    }

    @Test func searchDecoderRecognizesThreadPermalinksAndPagination() throws {
        let raw = #"{"ok":true,"messages":{"matches":[{"channel":{"id":"C1","name":"eng"},"ts":"1790000000.001","user":"U1","text":"hello","permalink":"https://example.slack.com/archives/C1/p1790000000001?thread_ts=1789999000.001"}],"paging":{"pages":3}}}"#
        let page = try SlackReplyDecoder.search(JSONDecoder().decode(JSONValue.self, from: Data(raw.utf8)), page: 1)
        #expect(page.hasMore)
        #expect(page.messages.first?.threadTS == "1789999000.001")
        #expect(page.messages.first?.sourceURL?.host == "example.slack.com")
        var unsafe = page.messages[0]; unsafe.permalink = "https://slack.com.evil.example/path"
        #expect(unsafe.sourceURL == nil)
    }

    @Test func contextDecoderReportsPartialHistoryWithoutInventingCompleteness() throws {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"ok":true,"messages":[{"ts":"1790000000.000001","text":"Hello","user":"UME"}],"response_metadata":{"next_cursor":"more"}}"#.utf8))
        let result = try SlackReplyDecoder.context(value, anchor: message())
        #expect(result.partial)
        #expect(result.messages.first?.channelID == "C1")
        #expect(result.messages.first?.user == "UME")
    }

    @Test func refreshBatchesGenerationAndReusesContext() async throws {
        let reader = FakeSlackReader(); reader.rows = [message(), message("1790000001.000001", root: "1789998000.000001")]
        let generator = FakeSlackGenerator()
        let workspace = try workspace(reader: reader, generator: generator)
        await workspace.refresh(force: true)
        #expect(reader.searches.count == 2)
        #expect(reader.contextReads == 2)
        #expect(generator.batches == [2])
        #expect(workspace.activeTopics.allSatisfy { $0.analysisIsCurrent })
        await workspace.refresh(force: true)
        #expect(reader.searches.count == 2)
        await workspace.generate(for: workspace.activeTopics[0].id, custom: "Ask a clarifying question")
        #expect(reader.contextReads == 2)
        #expect(workspace.activeTopics[0].customOption?.text == "What should happen for empty input?")
    }

    @Test func scanHasFourRequestBudgetAndKeepsPendingPages() async throws {
        let reader = FakeSlackReader(); reader.more = true
        let workspace = try workspace(reader: reader)
        await workspace.refresh(force: true)
        #expect(reader.searches.count == 4)
        #expect(workspace.snapshot.pendingSearches.map(\.page) == [3, 3])
        #expect(workspace.snapshot.lastRefresh == nil)
    }

    @Test func oversizedSearchPagesShrinkWithinTheSameFourCallBudget() async throws {
        let reader = FakeSlackReader(); reader.maxResponseCount = 5; reader.more = true; reader.rows = [message()]
        let store = SlackReplyStore(directory: nil)
        var snapshot = SlackReplySnapshot()
        snapshot.settings.enabled = true
        snapshot.pendingSearches = [SlackSearchJob(query: "mentions", page: 3)]
        try store.save(snapshot)
        let service = SlackReplyService(store: store, reader: reader, generator: FakeSlackGenerator(), clock: { now })
        await service.refresh(force: true)
        #expect(reader.counts == [10, 5, 5, 5])
        #expect(reader.pages == [3, 1, 2, 3])
        #expect(service.activeTopics.count == 1)
        #expect(service.snapshot.pendingSearches == [SlackSearchJob(query: "mentions", page: 4, count: 5)])
        #expect(try store.load().pendingSearches == service.snapshot.pendingSearches)
        #expect(service.snapshot.lastRefresh == nil)
    }

    @Test func oldSearchJobsRestartWhenMigratingToSmallerPages() throws {
        let job = try JSONDecoder().decode(SlackSearchJob.self, from: Data(#"{"query":"mentions","page":4}"#.utf8))
        #expect(job == SlackSearchJob(query: "mentions"))
        let current = SlackSearchJob(query: "mentions", page: 4, count: 5)
        #expect(try JSONDecoder().decode(SlackSearchJob.self, from: JSONEncoder().encode(current)) == current)
    }

    @Test func truncatedWorkbenchTextIsAnExplicitOversizedResponse() throws {
        let truncated = "{\"results\":[{\"result\":\n…[result truncated: 118773 chars total, showing first 60000. Narrow the request (limit/fields/pagination) to get complete data.]"
        #expect(throws: MCPError.responseTooLarge) { try MCPToolBroker.workbenchExecutionResult(from: truncated) }
        let structured: JSONValue = .object(["results": .array([.object(["result": .object(["ok": .bool(true)])])])])
        let response = MCPToolResult(content: [MCPContentBlock(type: "text", text: truncated)], structuredContent: structured, isError: false)
        #expect(try MCPToolBroker.workbenchExecutionResult(from: response).objectValue?["ok"] == .bool(true))
        let valid = #"{"results":[{"result":{"text":"[result truncated: is quoted message text"}}]}"#
        #expect(try MCPToolBroker.workbenchExecutionResult(from: valid).objectValue?["text"] != nil)
    }

    @Test func paginationFallbackUsesTheRequestedPageSize() throws {
        let value = try JSONDecoder().decode(JSONValue.self, from: Data(#"{"ok":true,"messages":{"matches":[{"channel":"C1","ts":"1790000000.001","text":"hello"}]}}"#.utf8))
        #expect(try SlackReplyDecoder.search(value, page: 1, count: 1).hasMore)
        #expect(try !SlackReplyDecoder.search(value, page: 1, count: 5).hasMore)
    }

    @Test func clearPersistsAndNewMentionResurfacesWithoutCountingACopyAsReply() throws {
        let store = SlackReplyStore(directory: nil)
        var snapshot = SlackReplySnapshot()
        snapshot.settings.userID = "UME"
        SlackReplyService.merge([message()], into: &snapshot, userID: "UME")
        try store.save(snapshot)
        let workspace = SlackReplyService(store: store, reader: FakeSlackReader(), generator: FakeSlackGenerator(), clock: { now })
        let id = snapshot.topics[0].id
        workspace.copied(id)
        #expect(workspace.activeTopics[0].observedReply(userID: "UME") == nil)
        workspace.clear([id])
        #expect(workspace.activeTopics.isEmpty)
        var reloaded = try store.load()
        SlackReplyService.merge([message()], into: &reloaded, userID: "UME")
        #expect(reloaded.topics[0].isDismissed)
        SlackReplyService.merge([message("1790000020.000001")], into: &reloaded, userID: "UME")
        #expect(!reloaded.topics[0].isDismissed)
        #expect(reloaded.topics.count == 1)
        #expect(reloaded.topics[0].analysis == nil)
    }

    @Test func failurePreservesCachedItemsAndHonorsRetryAfterAcrossRestart() async throws {
        let reader = FakeSlackReader(); reader.failure = SlackReplyError.rateLimited(600)
        let store = SlackReplyStore(directory: nil)
        let workspace = try workspace(reader: reader, store: store)
        await workspace.refresh(force: true)
        #expect(workspace.snapshot.retryAfter == now.addingTimeInterval(600))
        let restored = SlackReplyService(store: store, reader: reader, generator: FakeSlackGenerator(), clock: { now.addingTimeInterval(90) })
        await restored.refresh(force: true)
        #expect(reader.searches.count == 1)
        #expect(restored.snapshot.retryAfter == now.addingTimeInterval(600))
    }

    @Test func missingContextDoesNotProducePretendContextAwareReplies() async throws {
        let reader = FakeSlackReader(); reader.rows = [message()]; reader.contextFailure = true
        let generator = FakeSlackGenerator()
        let workspace = try workspace(reader: reader, generator: generator)
        await workspace.refresh(force: true)
        #expect(generator.batches.isEmpty)
        #expect(workspace.activeTopics.count == 1)
        #expect(workspace.activeTopics[0].lastError != nil)
    }

    @Test func explicitReadMethodsExcludeAllRemoteMutations() {
        #expect(Set(SlackMCPReader.ReadMethod.allCases.map(\.rawValue)) == ["slack_search_all", "slack_get_thread_replies", "slack_get_channel_history"])
        #expect(SlackReadGate.spacing(for: "slack_get_thread_replies") >= 60)
        #expect(SlackReadGate.spacing(for: "slack_search_all") >= 3)
        #expect(SlackReadGate.retryDelay(MCPError.rateLimited(120)) == 120)
        #expect(SlackReadGate.retryDelay(MCPError.toolExecution(#"{"error":"ratelimited","retry_after":180}"#)) == 180)
    }

    @Test func providerFailureKeepsFetchedMessagesAndDoesNotClaimSuggestionsExist() async throws {
        let reader = FakeSlackReader(); reader.rows = [message()]
        let generator = FakeSlackGenerator(); generator.fail = true
        let workspace = try workspace(reader: reader, generator: generator)
        await workspace.refresh(force: true)
        #expect(workspace.activeTopics.count == 1)
        #expect(workspace.activeTopics[0].analysis == nil)
        #expect(workspace.errorMessage != nil)
    }

    @Test func clearDuringGenerationCannotResurrectSuggestions() async throws {
        let reader = FakeSlackReader(); reader.rows = [message()]
        let generator = FakeSlackGenerator(); generator.suspend = true
        let workspace = try workspace(reader: reader, generator: generator)
        let work = Task { await workspace.refresh(force: true) }
        while generator.continuation == nil { await Task.yield() }
        workspace.clear(Set(workspace.activeTopics.map(\.id)))
        generator.continuation?.resume(); generator.continuation = nil
        await work.value
        #expect(workspace.activeTopics.isEmpty)
        #expect(workspace.clearedTopics[0].analysis == nil)
    }

    @Test func corruptCacheBlocksWritesAndKeepsOriginalBytes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TidySlack-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("slack-replies.json")
        let bytes = Data("preserve this inbox".utf8); try bytes.write(to: url)
        let service = SlackReplyService(store: SlackReplyStore(directory: directory), reader: FakeSlackReader(), generator: FakeSlackGenerator())
        #expect(!service.storageReady)
        service.clear([])
        #expect(try Data(contentsOf: url) == bytes)
    }

    @Test func disablingAutoRefreshPreventsBackgroundReads() async throws {
        let reader = FakeSlackReader()
        let store = SlackReplyStore(directory: nil)
        var state = SlackReplySnapshot(); state.settings.enabled = true; state.settings.autoRefresh = false
        try store.save(state)
        let workspace = SlackReplyService(store: store, reader: reader, generator: FakeSlackGenerator())
        await workspace.refresh()
        #expect(reader.searches.isEmpty)
        await workspace.refresh(force: true)
        #expect(reader.searches.count == 2)
    }

    @Test func recapUsesSavedContextAndCachesUnchangedDay() async throws {
        let reader = FakeSlackReader(); reader.rows = [message()]
        let generator = FakeSlackGenerator()
        let workspace = try workspace(reader: reader, generator: generator)
        await workspace.refresh(force: true)
        let reads = reader.searches.count + reader.contextReads
        await workspace.dailyRecap(for: now)
        await workspace.dailyRecap(for: now)
        #expect(generator.recaps == 1)
        #expect(reader.searches.count + reader.contextReads == reads)
        #expect(workspace.snapshot.recaps.count == 1)
    }
}

@MainActor
private final class FakeSlackReader: SlackReplyReading {
    var rows: [SlackReplyMessage] = []
    var more = false
    var failure: Error?
    var contextFailure = false
    var searches: [String] = []
    var pages: [Int] = []
    var counts: [Int] = []
    var maxResponseCount = Int.max
    var contextReads = 0
    func scope() throws -> String { "test-workspace" }
    func search(query: String, page: Int, count: Int) async throws -> SlackSearchPage {
        searches.append(query)
        pages.append(page); counts.append(count)
        if count > maxResponseCount { throw MCPError.responseTooLarge }
        if let failure { throw failure }
        return SlackSearchPage(messages: rows, hasMore: more)
    }
    func context(for message: SlackReplyMessage) async throws -> (messages: [SlackReplyMessage], partial: Bool) {
        contextReads += 1
        if contextFailure { throw SlackReplyError.message("No access") }
        return ([message], false)
    }
}

@MainActor
private final class FakeSlackGenerator: SlackReplyGenerating {
    var batches: [Int] = []
    var recaps = 0
    var fail = false
    var suspend = false
    var continuation: CheckedContinuation<Void, Never>?
    func analyze(_ topics: [SlackReplyTopic], settings: SlackReplySettings) async throws -> [SlackReplyAnalysis] {
        batches.append(topics.count)
        if suspend { await withCheckedContinuation { continuation = $0 } }
        if fail { throw SlackReplyError.message("Provider unavailable") }
        return topics.map { SlackReplyAnalysis(topicID: $0.id, summary: "A review was requested.", needsReply: true,
                                               options: [SlackReplyOption(title: "Direct", text: "Which behavior should I review?"), SlackReplyOption(title: "Alternative", text: "Could you share the expected behavior?")]) }
    }
    func refine(_ topic: SlackReplyTopic, instruction: String, settings: SlackReplySettings) async throws -> SlackReplyOption {
        SlackReplyOption(title: "Custom", text: "What should happen for empty input?")
    }
    func recap(_ topics: [SlackReplyTopic], day: String) async throws -> String { recaps += 1; return "A review was requested. No decision was recorded." }
}
