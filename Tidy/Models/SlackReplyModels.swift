import CryptoKit
import Foundation

struct SlackReplySettings: Codable, Equatable {
    var enabled = false
    var aliases = ""
    var userID = ""
    var includeDirectMessages = true
    var autoRefresh = true
    var refreshMinutes = 60

    var names: [String] {
        Array(Set(aliases.components(separatedBy: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        }.filter { !$0.isEmpty })).sorted()
    }

    func validated() throws -> Self {
        var value = self
        value.userID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._- "))
        guard (!enabled || !names.isEmpty), names.count <= 5, names.allSatisfy({ $0.count <= 80 && $0.unicodeScalars.allSatisfy(allowed.contains) }),
              value.userID.isEmpty || value.userID.range(of: "^[UW][A-Z0-9]+$", options: .regularExpression) != nil,
              [15, 30, 60, 120, 240].contains(refreshMinutes) else {
            throw SlackReplyError.message("Use up to five comma-separated names or handles, a Slack member ID such as U123ABC, and a listed refresh interval.")
        }
        value.aliases = names.joined(separator: ", ")
        return value
    }

    func queries(since: Date) -> [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let date = "after:\(formatter.string(from: since))"
        let terms = names.map { $0.contains(" ") ? "\"\($0)\"" : "@\($0)" }
            + (userID.isEmpty ? [] : ["<@\(userID)>"])
        var queries = ["(\(terms.joined(separator: " OR "))) -from:me \(date)"]
        if includeDirectMessages { queries.append("to:me is:dm -from:me \(date)") }
        return queries
    }
}

struct SlackReplyMessage: Codable, Equatable, Identifiable {
    var channelID: String
    var channelName: String
    var ts: String
    var threadTS: String
    var user: String
    var text: String
    var permalink: String?
    var isDM: Bool
    var id: String { channelID + ":" + ts }
    var topicID: String { channelID + ":" + threadTS }
    var date: Date { Date(timeIntervalSince1970: Double(ts) ?? 0) }
    var sourceURL: URL? {
        guard let permalink, let url = URL(string: permalink), url.scheme == "https",
              let host = url.host, host == "slack.com" || host.hasSuffix(".slack.com") else { return nil }
        return url
    }
}

struct SlackReplyOption: Codable, Equatable, Identifiable {
    var title: String
    var text: String
    var id: String { title + text }
}

struct SlackReplyAnalysis: Codable, Equatable {
    var topicID: String
    var summary: String
    var needsReply: Bool
    var options: [SlackReplyOption]
}

struct SlackReplyTopic: Codable, Equatable, Identifiable {
    var id: String
    var mentions: [SlackReplyMessage]
    var context: [SlackReplyMessage] = []
    var contextFetchedAt: Date?
    var contextAttemptAt: Date?
    var contextIsPartial = true
    var analysis: SlackReplyAnalysis?
    var analysisFingerprint: String?
    var customOption: SlackReplyOption?
    var customInstruction: String?
    var dismissedThrough: String?
    var copiedAt: Date?
    var lastError: String?

    var latest: SlackReplyMessage { mentions.max { $0.date < $1.date }! }
    var isDismissed: Bool { (Double(dismissedThrough ?? "0") ?? 0) >= (Double(latest.ts) ?? 0) }
    var fingerprint: String {
        SlackReplyFingerprint.make((mentions + context).map { $0.id + $0.text }.joined(separator: "\n"))
    }
    var analysisIsCurrent: Bool { analysis != nil && analysisFingerprint == fingerprint }
    func observedReply(userID: String) -> SlackReplyMessage? {
        guard !userID.isEmpty else { return nil }
        return context.filter { $0.user == userID && $0.date > latest.date }.min { $0.date < $1.date }
    }
}

struct SlackSearchJob: Codable, Equatable {
    var query: String
    var page = 1
    var count = 10

    init(query: String, page: Int = 1, count: Int = 10) {
        self.query = query; self.page = page; self.count = count
    }

    private enum CodingKeys: String, CodingKey { case query, page, count }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        query = try container.decode(String.self, forKey: .query)
        let savedCount = try container.decodeIfPresent(Int.self, forKey: .count)
        count = max(1, min(10, savedCount ?? 10))
        // A changed page size must restart the query to avoid skipping matches.
        page = savedCount == count ? max(1, try container.decode(Int.self, forKey: .page)) : 1
    }
}

struct SlackDailyRecap: Codable, Equatable {
    var day: String
    var text: String
    var fingerprint: String
    var generatedAt: Date
}

struct SlackReplySnapshot: Codable, Equatable {
    var version = 1
    var settings = SlackReplySettings()
    var scope = ""
    var topics: [SlackReplyTopic] = []
    var pendingSearches: [SlackSearchJob] = []
    var lastRefresh: Date?
    var scanStartedAt: Date?
    var lastAttempt: Date?
    var retryAfter: Date?
    var recaps: [SlackDailyRecap] = []
}

enum SlackReplyFingerprint {
    static func make(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

enum SlackReplyError: LocalizedError, Equatable {
    case message(String)
    case rateLimited(TimeInterval)
    var errorDescription: String? {
        switch self {
        case .message(let message): message
        case .rateLimited(let seconds): "Slack asked us to pause. Retry in \(Int(ceil(seconds / 60))) minute(s). Saved conversations are still available."
        }
    }
}

struct SlackSearchPage {
    var messages: [SlackReplyMessage]
    var hasMore: Bool
}

enum SlackReplyDecoder {
    static func check(_ value: JSONValue) throws {
        guard let object = value.objectValue else { throw SlackReplyError.message("Slack returned an unreadable response.") }
        if object["ok"]?.boolValue == false || object["error"] != nil {
            let message = object["error"]?.stringValue ?? "Unknown Slack error"
            if message.lowercased().contains("ratelimit") || message.lowercased().contains("rate_limit") {
                throw SlackReplyError.rateLimited(Double(object["retry_after"]?.intValue ?? 60))
            }
            throw SlackReplyError.message("Slack could not read this discussion: \(message)")
        }
    }

    static func search(_ value: JSONValue, page: Int, count: Int = 10) throws -> SlackSearchPage {
        try check(value)
        let object = value.objectValue!
        let envelope = object["messages"]?.objectValue
        guard let rows = envelope?["matches"]?.arrayValue ?? object["messages"]?.arrayValue else {
            throw SlackReplyError.message("The Slack search tool did not return structured message matches.")
        }
        let pages = envelope?["paging"]?.objectValue?["pages"]?.intValue
            ?? envelope?["pagination"]?.objectValue?["page_count"]?.intValue
        return SlackSearchPage(messages: rows.compactMap { message($0) }, hasMore: pages.map { page < $0 } ?? (rows.count >= count))
    }

    static func context(_ value: JSONValue, anchor: SlackReplyMessage) throws -> (messages: [SlackReplyMessage], partial: Bool) {
        try check(value)
        guard let rows = value.objectValue?["messages"]?.arrayValue else {
            throw SlackReplyError.message("The Slack read tool did not return structured discussion messages.")
        }
        let messages = rows.compactMap { message($0, anchor: anchor) }.sorted { $0.date < $1.date }
        let hasCursor = !(value.objectValue?["response_metadata"]?.objectValue?["next_cursor"]?.stringValue ?? "").isEmpty
        return (messages, value.objectValue?["has_more"]?.boolValue == true || hasCursor || messages.count >= 15)
    }

    static func message(_ value: JSONValue, anchor: SlackReplyMessage? = nil) -> SlackReplyMessage? {
        guard let object = value.objectValue, let ts = object["ts"]?.stringValue,
              let timestamp = Double(ts), timestamp.isFinite, timestamp > 0,
              let text = object["text"]?.stringValue, !text.isEmpty else { return nil }
        let channel = object["channel"]?.objectValue
        guard let channelID = channel?["id"]?.stringValue ?? object["channel"]?.stringValue ?? anchor?.channelID,
              !channelID.isEmpty else { return nil }
        let permalink = object["permalink"]?.stringValue
        let linkRoot = permalink.flatMap { URLComponents(string: $0)?.queryItems?.first { $0.name == "thread_ts" }?.value }
        return SlackReplyMessage(channelID: channelID, channelName: channel?["name"]?.stringValue ?? anchor?.channelName ?? channelID,
                                 ts: ts, threadTS: object["thread_ts"]?.stringValue ?? linkRoot ?? anchor?.threadTS ?? ts,
                                 user: object["user"]?.stringValue ?? object["username"]?.stringValue ?? "Unknown member",
                                 text: String(text.prefix(6000)), permalink: permalink ?? anchor?.permalink,
                                 isDM: channel?["is_im"]?.boolValue == true || channelID.hasPrefix("D") || anchor?.isDM == true)
    }
}
