import Foundation

enum SlackReplyDestination: String, Codable, CaseIterable, Identifiable {
    case thread, conversation
    var id: String { rawValue }
}

struct SlackReplyDraft: Identifiable {
    let id = UUID()
    let topicID: String
    let scope: String
    let channelID: String
    let channelName: String
    let isDM: Bool
    let parentTS: String
    let anchorText: String
    let sourceURL: URL?
    var text: String
    var destination: SlackReplyDestination
    var otherChannelID = ""

    var targetChannelID: String { otherChannelID.isEmpty ? channelID : otherChannelID }

    init(topic: SlackReplyTopic, scope: String, text: String = "") {
        topicID = topic.id; self.scope = scope
        channelID = topic.latest.channelID; channelName = topic.latest.channelName
        isDM = topic.latest.isDM; parentTS = topic.latest.threadTS
        anchorText = topic.latest.text; sourceURL = topic.latest.sourceURL
        self.text = text
        destination = isDM && topic.latest.ts == parentTS ? .conversation : .thread
    }

    init(scope: String) {
        topicID = "outgoing"; self.scope = scope
        channelID = ""; channelName = ""; isDM = false; parentTS = ""
        anchorText = ""; sourceURL = nil; text = ""; destination = .conversation
    }

    var destinationLabel: String {
        if !otherChannelID.isEmpty { return otherChannelID.hasPrefix("D") ? "Direct message" : "New channel message" }
        if destination == .thread { return isDM ? "Thread in direct message" : "Thread in #\(channelName)" }
        return isDM ? "Direct message" : "New message in #\(channelName)"
    }
}

struct SlackSendRequest: Codable, Equatable, Identifiable {
    let id: UUID
    let topicID: String
    let scope: String
    let channelID: String
    let destinationLabel: String
    let threadTS: String?
    let text: String
    let reviewedAt: Date
}

struct SlackSendReceipt: Codable, Equatable {
    let channelID: String
    let ts: String
}

struct SlackSendRecord: Codable, Equatable, Identifiable {
    enum State: String, Codable { case sending, sent, failed, uncertain }
    let request: SlackSendRequest
    var state: State
    var receipt: SlackSendReceipt?
    var detail: String?
    var retryAfter: Date?
    var id: UUID { request.id }
}

enum SlackSendError: LocalizedError {
    case notSent(String, retryAfter: TimeInterval? = nil)
    case uncertain

    var errorDescription: String? {
        switch self {
        case .notSent(let message, _): message
        case .uncertain: "Slack did not confirm delivery. Check the conversation before sending again; Tidy will not retry automatically."
        }
    }
}
