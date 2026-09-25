import Foundation
import Testing
@testable import Tidy

@MainActor
struct SlackSendTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func draft() -> SlackReplyDraft {
        let message = SlackReplyMessage(channelID: "C123", channelName: "test-room", ts: "1790000000.001", threadTS: "1789999000.001",
                                        user: "UOTHER", text: "Can you clarify?", isDM: false)
        return SlackReplyDraft(topic: SlackReplyTopic(id: message.topicID, mentions: [message]), scope: "test-scope", text: "Which part needs clarification?")
    }

    @Test func reviewingAndCancellingNeverSends() throws {
        let writer = FakeSlackWriter()
        let service = SlackSendService(store: SlackOutboxStore(directory: nil), writer: writer)
        let request = try service.review(draft())
        #expect(writer.requests.isEmpty)
        #expect(service.records.isEmpty)
        service.cancelReview(request.id)
        #expect(writer.requests.isEmpty)
    }

    @Test func onlyTheExactReviewedMessageCanBeSentOnce() async throws {
        let writer = FakeSlackWriter(); let store = SlackOutboxStore(directory: nil)
        let service = SlackSendService(store: store, writer: writer)
        var edited = draft()
        let request = try service.review(edited)
        edited.text = "This has not been reviewed"
        let record = try await service.sendApproved(request.id)
        #expect(record.state == .sent)
        #expect(writer.requests == [request])
        #expect(writer.requests.first?.text == "Which part needs clarification?")
        #expect(try store.load().first?.receipt?.ts == "1790000010.001")
        await #expect(throws: (any Error).self) { try await service.sendApproved(request.id) }
        await #expect(throws: (any Error).self) { try await service.sendApproved(UUID()) }
        #expect(writer.requests.count == 1)
    }

    @Test func editingInvalidatesThePreviousReview() async throws {
        let writer = FakeSlackWriter(); let service = SlackSendService(store: SlackOutboxStore(directory: nil), writer: writer)
        let first = try service.review(draft())
        var changed = draft(); changed.text = "Updated message"
        let second = try service.review(changed)
        await #expect(throws: (any Error).self) { try await service.sendApproved(first.id) }
        _ = try await service.sendApproved(second.id)
        #expect(writer.requests.map(\.text) == ["Updated message"])
    }

    @Test func connectionChangesAndExpiredReviewsPreventSending() async throws {
        let writer = FakeSlackWriter(); var time = now
        let service = SlackSendService(store: SlackOutboxStore(directory: nil), writer: writer, clock: { time })
        let first = try service.review(draft())
        writer.currentScope = "other-workspace"
        await #expect(throws: (any Error).self) { try await service.sendApproved(first.id) }
        writer.currentScope = "test-scope"
        let second = try service.review(draft())
        time = time.addingTimeInterval(301)
        await #expect(throws: (any Error).self) { try await service.sendApproved(second.id) }
        #expect(writer.requests.isEmpty)
    }

    @Test func uncertainDeliveryIsNotRetriedAndSurvivesRestart() async throws {
        let writer = FakeSlackWriter(); writer.failure = URLError(.timedOut)
        let store = SlackOutboxStore(directory: nil)
        let service = SlackSendService(store: store, writer: writer)
        let request = try service.review(draft())
        let result = try await service.sendApproved(request.id)
        #expect(result.state == .uncertain)
        #expect(writer.requests.count == 1)
        let restored = SlackSendService(store: store, writer: writer)
        #expect(restored.hasUncertainDelivery(draft()))
        #expect(throws: (any Error).self) { try restored.review(draft()) }
        let acknowledged = try restored.review(draft(), checkedUncertainDelivery: true)
        #expect(acknowledged.id != request.id)
        #expect(writer.requests.count == 1)
    }

    @Test func interruptedSendsAreRecoveredAsUncertain() throws {
        let writer = FakeSlackWriter(); let store = SlackOutboxStore(directory: nil)
        let service = SlackSendService(store: store, writer: writer)
        let request = try service.review(draft())
        try store.save([SlackSendRecord(request: request, state: .sending)])
        let restored = SlackSendService(store: store, writer: writer)
        #expect(restored.records.first?.state == .uncertain)
        #expect(writer.requests.isEmpty)
    }

    @Test func threadAndCustomDestinationArgumentsAreExact() throws {
        let service = SlackSendService(store: SlackOutboxStore(directory: nil), writer: FakeSlackWriter())
        var value = draft()
        let thread = try service.review(value)
        #expect(SlackMessageWriter.arguments(for: thread) == ["channel": .string("C123"), "text": .string(value.text), "threadTs": .string("1789999000.001")])
        value.otherChannelID = "D456"
        let dm = try service.review(value)
        #expect(dm.threadTS == nil)
        #expect(dm.channelID == "D456")
        #expect(SlackMessageWriter.arguments(for: dm)["threadTs"] == nil)
        value.otherChannelID = ""; value.destination = .conversation
        #expect(try service.review(value).threadTS == nil)
    }

    @Test func invalidContentAndDestinationsCannotBeReviewed() throws {
        let service = SlackSendService(store: SlackOutboxStore(directory: nil), writer: FakeSlackWriter())
        var value = draft(); value.text = "  \n"
        #expect(throws: (any Error).self) { try service.review(value) }
        value.text = String(repeating: "a", count: 4001)
        #expect(throws: (any Error).self) { try service.review(value) }
        value.text = "Hello"; value.otherChannelID = "#general"
        #expect(throws: (any Error).self) { try service.review(value) }
        value.otherChannelID = "U123"
        #expect(throws: (any Error).self) { try service.review(value) }
    }

    @Test func aNewMessageDoesNotNeedAnInboxDiscussion() throws {
        let writer = FakeSlackWriter()
        let service = SlackSendService(store: SlackOutboxStore(directory: nil), writer: writer)
        var value = SlackReplyDraft(scope: "test-scope")
        value.otherChannelID = "CNEW"; value.text = "A new message"
        let request = try service.review(value)
        #expect(request.channelID == "CNEW")
        #expect(request.threadTS == nil)
        #expect(writer.requests.isEmpty)
    }

    @Test func slackSuccessRequiresMatchingChannelAndMessageID() throws {
        let service = SlackSendService(store: SlackOutboxStore(directory: nil), writer: FakeSlackWriter())
        let request = try service.review(draft())
        let good: JSONValue = .object(["ok": .bool(true), "channel": .string("C123"), "ts": .string("1790000010.001")])
        #expect(try SlackMessageWriter.receipt(from: good, request: request).channelID == "C123")
        #expect(throws: (any Error).self) { try SlackMessageWriter.receipt(from: .object(["ok": .bool(true)]), request: request) }
        #expect(throws: (any Error).self) { try SlackMessageWriter.receipt(from: .object(["ok": .bool(false), "error": .string("missing_scope")]), request: request) }
    }

    @Test func cooldownSurvivesRestartWithoutAutomaticRetry() async throws {
        let writer = FakeSlackWriter(); writer.failure = SlackSendError.notSent("Rate limited", retryAfter: 600)
        let store = SlackOutboxStore(directory: nil)
        let service = SlackSendService(store: store, writer: writer, clock: { now })
        let request = try service.review(draft())
        #expect(try await service.sendApproved(request.id).state == .failed)
        let restored = SlackSendService(store: store, writer: writer, clock: { now.addingTimeInterval(90) })
        let next = try restored.review(draft())
        await #expect(throws: (any Error).self) { try await restored.sendApproved(next.id) }
        #expect(writer.requests.count == 1)
    }

    @Test func concurrentConfirmationCannotSendTwice() async throws {
        let writer = FakeSlackWriter(); writer.suspend = true
        let service = SlackSendService(store: SlackOutboxStore(directory: nil), writer: writer)
        let request = try service.review(draft())
        let first = Task { try await service.sendApproved(request.id) }
        while writer.continuation == nil { await Task.yield() }
        await #expect(throws: (any Error).self) { try await service.sendApproved(request.id) }
        writer.continuation?.resume(); writer.continuation = nil
        #expect(try await first.value.state == .sent)
        #expect(writer.requests.count == 1)
    }

    @Test func clearingHistoryDuringSendPreservesDeliveryJournal() async throws {
        let writer = FakeSlackWriter(); writer.suspend = true
        let store = SlackOutboxStore(directory: nil)
        let service = SlackSendService(store: store, writer: writer)
        let request = try service.review(draft())
        let send = Task { try await service.sendApproved(request.id) }
        while writer.continuation == nil { await Task.yield() }
        service.reset()
        #expect(try store.load().first?.state == .sending)
        writer.continuation?.resume(); writer.continuation = nil
        #expect(try await send.value.state == .sent)
        #expect(try store.load().first?.state == .sent)
    }

    @Test func failedLocalJournalWritePreventsRemoteSend() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("not a directory".utf8).write(to: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let writer = FakeSlackWriter()
        let service = SlackSendService(store: SlackOutboxStore(directory: root), writer: writer)
        let request = try service.review(draft())
        await #expect(throws: (any Error).self) { try await service.sendApproved(request.id) }
        #expect(writer.requests.isEmpty)
    }
}

@MainActor
private final class FakeSlackWriter: SlackMessageWriting {
    var currentScope = "test-scope"
    var requests: [SlackSendRequest] = []
    var failure: Error?
    var suspend = false
    var continuation: CheckedContinuation<Void, Never>?
    func scope() throws -> String { currentScope }
    func send(_ request: SlackSendRequest) async throws -> SlackSendReceipt {
        requests.append(request)
        if suspend { await withCheckedContinuation { continuation = $0 } }
        if let failure { throw failure }
        return SlackSendReceipt(channelID: request.channelID, ts: "1790000010.001")
    }
}

@Suite(.serialized)
struct SlackSendTransportTests {
    @Test func writeTransportDoesNotReplayAfterSessionExpiry() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SlackSendURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel(); SlackSendURLProtocol.toolCalls = 0 }
        let client = MCPClient(configuration: MCPServerConfiguration(endpoint: URL(string: "https://slack-send-test.invalid/mcp")!, apiKeyHeaderName: "x-api-key", apiKey: "fixture"), session: session)
        try await client.connect()
        await #expect(throws: MCPError.sessionExpired) {
            try await client.callToolWithoutRetry(name: "slack_send_message", arguments: ["channel": .string("C123"), "text": .string("Local fixture")])
        }
        #expect(SlackSendURLProtocol.toolCalls == 1)
    }
}

private final class SlackSendURLProtocol: URLProtocol {
    static var toolCalls = 0
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let data: Data
        if let body = request.httpBody { data = body }
        else if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var result = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }; result.append(buffer, count: count)
            }
            data = result
        } else { data = Data() }
        let value = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let method = value["method"] as? String
        var status = 200
        var body: [String: Any] = [:]
        if method == "initialize" {
            body = ["jsonrpc": "2.0", "id": value["id"] ?? 1, "result": ["protocolVersion": "2025-11-25", "serverInfo": ["name": "fixture"]]]
        } else if method == "tools/call" { Self.toolCalls += 1; status = 404 }
        else { status = 202 }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json", "Mcp-Session-Id": "fixture-session"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: (try? JSONSerialization.data(withJSONObject: body)) ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
