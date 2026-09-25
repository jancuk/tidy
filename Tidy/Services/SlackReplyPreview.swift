import Foundation

@MainActor
struct SlackReplyPreviewReader: SlackReplyReading {
    func scope() throws -> String { "local-slack-preview" }
    func search(query: String, page: Int, count: Int) async throws -> SlackSearchPage {
        SlackSearchPage(messages: page == 1 ? Self.messages : [], hasMore: false)
    }
    func context(for message: SlackReplyMessage) async throws -> (messages: [SlackReplyMessage], partial: Bool) {
        var earlier = message
        earlier.ts = String(message.date.addingTimeInterval(-120).timeIntervalSince1970)
        earlier.text = "The smaller rollout passed staging. We still need to confirm the empty-input behavior before release."
        return ([earlier, message], false)
    }
    static var messages: [SlackReplyMessage] {
        [SlackReplyMessage(channelID: "CDEMO", channelName: "product-engineering", ts: String(Date().addingTimeInterval(-600).timeIntervalSince1970),
                           threadTS: "1000000000.000001", user: "Rina", text: "@alex.lee can you review the empty-input behavior before we choose a release window?",
                           permalink: nil, isDM: false),
         SlackReplyMessage(channelID: "DDEMO", channelName: "Direct message", ts: String(Date().addingTimeInterval(-1200).timeIntervalSince1970),
                           threadTS: "1000000000.000002", user: "Dion", text: "Can you help clarify which checks we need for the rollout?", permalink: nil, isDM: true)]
    }
}

@MainActor
struct SlackReplyPreviewGenerator: SlackReplyGenerating {
    func analyze(_ topics: [SlackReplyTopic], settings: SlackReplySettings) async throws -> [SlackReplyAnalysis] { topics.map(Self.analysis) }
    func refine(_ topic: SlackReplyTopic, instruction: String, settings: SlackReplySettings) async throws -> SlackReplyOption {
        SlackReplyOption(title: "Custom reply", text: "Bisa share contoh input kosong dan hasil yang diharapkan? Itu akan membantu memperjelas pengecekan sebelum rollout.")
    }
    func recap(_ topics: [SlackReplyTopic], day: String) async throws -> String {
        "## Discussion highlights\nThe team discussed rollout checks and empty-input handling.\n\n## Decisions\nNo final release window was recorded.\n\n## Open follow-ups\nClarify the expected empty-input behavior before release."
    }
    static func analysis(_ topic: SlackReplyTopic) -> SlackReplyAnalysis {
        SlackReplyAnalysis(topicID: topic.id, summary: "The team is preparing a smaller rollout. Staging checks passed, but empty-input behavior still needs clarification before choosing a release window.",
                           needsReply: true, options: [
                            SlackReplyOption(title: "Keep it concise", text: "Could you share the expected behavior for empty input and a sample payload? That would help pin down the remaining check."),
                            SlackReplyOption(title: "Clarify the next step", text: "It sounds like empty-input handling is the remaining question. Are we expecting a validation error or an empty result? Let's confirm that before deciding the release window.")])
    }
}
