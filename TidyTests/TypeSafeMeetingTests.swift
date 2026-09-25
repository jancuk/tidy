import Foundation
import Testing
@testable import Tidy

struct TypeSafeMeetingTests {
    private func segments(_ count: Int) -> [MeetingSegment] {
        (0..<count).map { MeetingSegment(id: "source-\($0)", chunkID: UUID(), start: Double($0), end: Double($0 + 1), speaker: "Speaker A", text: "Original passage \($0), termasuk Bahasa Indonesia.") }
    }

    @Test func requestUsesTypedQuestionsAndQuotedState() throws {
        let request = try TypeSafeMeetingService.makeRequest(segments(2), model: "", apiKey: "test-key")
        #expect(request.url?.absoluteString == "https://api.typesafe.ai/v1/systemone")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body["model"] as? String == "jev-latest")
        #expect(body["messages"] == nil)
        let questions = try #require(body["questions"] as? [String: [String: Any]])
        #expect(questions.count == 2)
        #expect(questions["0"]?["type"] as? String == "choice")
        let state = try #require(body["state"] as? [String: [[String: String]]])
        #expect(state["rows"]?.first?["text"] == segments(1)[0].text)
    }

    @Test func batchesPreserveEveryReferenceAndRejectOversizedPassages() throws {
        let input = segments(45)
        let batches = try TypeSafeMeetingService.batches(input)
        #expect(batches.map(\.count) == [20, 20, 5])
        #expect(batches.flatMap { $0 }.map(\.id) == input.map(\.id))
        var oversized = input[0]
        oversized.text = String(repeating: "x", count: 17_000)
        #expect(throws: MeetingError.self) { try TypeSafeMeetingService.batches([oversized]) }
        #expect(throws: MeetingError.self) { try TypeSafeMeetingService.batches([input[0], input[0]]) }
        #expect(throws: MeetingError.self) { try TypeSafeMeetingService.batches([]) }
    }

    @Test func rejectsMissingUnknownAndInvalidClassifications() throws {
        #expect(throws: MeetingError.self) { try TypeSafeMeetingService.decode(Data("{\"answers\":{}}".utf8), count: 1) }
        let valid = TypeSafeMockProtocol.response
        #expect(try TypeSafeMeetingService.decode(valid, count: 5).count == 5)
        #expect(throws: MeetingError.self) { try TypeSafeMeetingService.decode(valid, count: 4) }
        let invalid = String(decoding: valid, as: UTF8.self).replacingOccurrences(of: "decision", with: "invented")
        #expect(throws: MeetingError.self) { try TypeSafeMeetingService.decode(Data(invalid.utf8), count: 5) }
    }

    @Test(arguments: [0.94, 0.98])
    func acceptsRoundedProbabilityTotals(selectedProbability: Double) throws {
        let data = try classificationResponse(selectedProbability: selectedProbability)
        let answer = try #require(TypeSafeMeetingService.decode(data, count: 1).first)
        #expect(answer.choice == "decision")
        #expect(answer.probabilities["decision"] == selectedProbability)
    }

    @Test(arguments: [0.0, 0.5, 0.93, 0.99, 1.01])
    func rejectsProbabilityTotalsBeyondRounding(selectedProbability: Double) throws {
        let data = try classificationResponse(selectedProbability: selectedProbability)
        #expect(throws: MeetingError.self) { try TypeSafeMeetingService.decode(data, count: 1) }
    }

    @Test func roundingAllowanceStillRejectsMalformedClassifications() throws {
        let data = try classificationResponse(selectedProbability: 0.96)
        let payload = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let answers = try #require(payload["answers"] as? [String: [String: Any]])
        let valid = try #require(answers["0"])
        let invalidFields: [[String: Any]] = [
            ["type": "noul"],
            ["choice": "action"],
            ["confidence": 1.95],
            ["confidence": -0.1],
            ["probabilities": ["decision": 0.96, "action": 0.01, "question": 0.01, "highlight": 0.02]],
            ["probabilities": ["decision": 0.96, "action": 0.01, "question": 0.01, "highlight": 0.01, "unknown": 0.01]],
            ["probabilities": ["decision": 0.99, "action": -0.01, "question": 0.01, "highlight": 0.01, "omit": 0.0]],
            ["probabilities": ["decision": 1.001, "action": 0.0, "question": 0.0, "highlight": 0.0, "omit": 0.0]]
        ]
        for fields in invalidFields {
            let answer = valid.merging(fields) { _, replacement in replacement }
            let response = try JSONSerialization.data(withJSONObject: ["answers": ["0": answer]])
            #expect(throws: MeetingError.self) { try TypeSafeMeetingService.decode(response, count: 1) }
        }
    }

    private func classificationResponse(selectedProbability: Double) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["answers": ["0": [
            "type": "choice", "choice": "decision", "confidence": 0.95,
            "probabilities": ["decision": selectedProbability, "action": 0.01,
                              "question": 0.01, "highlight": 0.01, "omit": 0.01]
        ]]])
    }

    @Test func meetingIntegrationPreservesTextAndCitationsWithoutInventingOwners() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TypeSafeMockProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let service = MeetingAIService(session: session, typeSafeAPIKey: { "test-key" })
        let input = segments(5)
        let summary = try await service.summarize(input, provider: .typeSafe, language: "English")
        #expect(summary.decisions == [MeetingPoint(text: input[0].text, segmentIDs: [input[0].id])])
        #expect(summary.actions.first?.title == input[1].text)
        #expect(summary.actions.first?.owner == nil)
        #expect(summary.actions.first?.dueText == nil)
        #expect(summary.questions.first?.segmentIDs == [input[2].id])
        #expect(summary.overview.contains(input[3].text))
        #expect(!summary.referencedSegmentIDs.contains(input[4].id))
    }

    @Test func localOnlyBlocksJevAndModelDefaultsRemainCompatible() throws {
        #expect(throws: AppPrivacyError.self) { try MeetingSummaryProvider.typeSafe.validatePrivacy(localOnly: true) }
        try MeetingSummaryProvider.typeSafe.validatePrivacy(localOnly: false)
        #expect(MeetingSummaryProvider.typeSafe.resolvedModel("  ") == "jev-latest")
        #expect(MeetingSummaryProvider.typeSafe.resolvedModel(" jev-preview ") == "jev-preview")
        #expect(MeetingSummaryProvider.openAI.resolvedModel("") == "gpt-4.1-mini")
    }

    @Test func longMeetingCompletesWithRoundedClassificationsAcrossBatches() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TypeSafeMockProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let input = segments(2_867)
        let service = MeetingAIService(session: session, typeSafeAPIKey: { "test-key" })
        let summary = try await service.summarize(input, provider: .typeSafe, language: "Auto")
        #expect(summary.decisions.count == 574)
        #expect(summary.actions.count == 574)
        #expect(summary.questions.count == 573)
        #expect(summary.actions.last?.segmentIDs == [input[2_866].id])
        #expect(summary.overview.contains(input[2_863].text))
        #expect(!summary.referencedSegmentIDs.contains(input[2_864].id))
    }

    @Test func emptyKeyGivesActionableError() async {
        do {
            _ = try await TypeSafeMeetingService(apiKey: { "  " }).summarize(segments(1), model: "jev-latest")
            Issue.record("Expected a missing API key error")
        } catch {
            #expect(error.localizedDescription.contains("API key"))
        }
    }
}

private final class TypeSafeMockProtocol: URLProtocol {
    static var response: Data { response(count: 5) }

    static func response(count: Int) -> Data {
        let categories = ["decision", "action", "question", "highlight", "decision"]
        let answers = Dictionary(uniqueKeysWithValues: (0..<count).map { index in
            let category = categories[index % categories.count]
            let probabilities = Dictionary(uniqueKeysWithValues: ["decision", "action", "question", "highlight", "omit"].map {
                ($0, $0 == category ? (index.isMultiple(of: 2) ? 0.94 : 0.98) : 0.01)
            })
            return (String(index), ["type": "choice", "choice": category, "confidence": index % 5 == 4 ? 0.4 : 0.95, "probabilities": probabilities] as [String: Any])
        })
        return try! JSONSerialization.data(withJSONObject: ["answers": answers])
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let body: Data
        if let data = request.httpBody {
            body = data
        } else if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4_096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(contentsOf: buffer.prefix(count))
            }
            body = data
        } else {
            body = Data()
        }
        guard let payload = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let questions = payload["questions"] as? [String: Any] else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.response(count: questions.count))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
