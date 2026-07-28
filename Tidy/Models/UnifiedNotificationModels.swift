import Foundation

struct UnifiedNotificationDigest: Identifiable, Codable, Equatable {
    let source: MCPIntegrationSource
    let summary: String
    let rawPreview: String
    let toolName: String
    let fetchedAt: Date

    var id: String { source.rawValue }
}

extension MCPIntegrationSource: Codable {
    var notificationSystemImage: String {
        switch self {
        case .slack: "bubble.left.and.bubble.right.fill"
        case .gmail: "envelope.fill"
        case .googleCalendar: "calendar"
        case .newRelic: "waveform.path.ecg"
        case .jira: "shippingbox.fill"
        }
    }
}

struct MCPConnectionTestResult {
    let serverName: String
    let tools: [MCPTool]
    let mappings: [MCPIntegrationSource: String]
}

struct SlackNotificationFocus: Equatable, Sendable {
    static let maximumChannels = 20
    static let maximumGroups = 20
    static let allowedTopicLimits = [5, 10]

    let channels: [String]
    let groupMentions: [String]
    let includeGroupMentions: Bool
    let topicLimit: Int

    init(
        channelsText: String,
        groupsText: String,
        includeGroupMentions: Bool = false,
        topicLimit: Int = 10
    ) {
        channels = Self.normalizedTokens(
            channelsText,
            prefix: "#",
            maximumCount: Self.maximumChannels
        )
        groupMentions = Self.normalizedTokens(
            groupsText,
            prefix: "@",
            maximumCount: Self.maximumGroups
        )
        self.includeGroupMentions = includeGroupMentions
        self.topicLimit = Self.allowedTopicLimits.contains(topicLimit) ? topicLimit : 10
    }

    static func stored(in defaults: UserDefaults = .standard) -> SlackNotificationFocus {
        SlackNotificationFocus(
            channelsText: defaults.string(forKey: AppDefaults.slackNotificationChannels) ?? "",
            groupsText: defaults.string(forKey: AppDefaults.slackNotificationGroups) ?? "",
            includeGroupMentions: defaults.bool(forKey: AppDefaults.slackIncludeGroupMentions),
            topicLimit: defaults.integer(forKey: AppDefaults.slackNotificationTopicLimit)
        )
    }

    func searchQueries(
        directMention: String,
        dateFilter: String
    ) -> [String] {
        let direct = Self.normalizedTokens(
            directMention,
            prefix: "@",
            maximumCount: 1
        ).first ?? "to:me"
        let mentions = includeGroupMentions ? [direct] + groupMentions : [direct]
        let mentionExpression = mentions
            .uniqued()
            .joined(separator: " OR ")
        let senderExclusion = direct == "to:me"
            ? "-from:me"
            : "-from:\(direct)"
        let suffix = dateFilter.trimmingCharacters(in: .whitespacesAndNewlines)

        if channels.isEmpty {
            return [[mentionExpression, senderExclusion, suffix]
                .filter { !$0.isEmpty }
                .joined(separator: " ")]
        }
        return channels.map { channel in
            [mentionExpression, senderExclusion, "in:\(channel)", suffix]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
    }

    static func mergedTopicText(
        _ resultTexts: [String],
        limit: Int
    ) -> String {
        var messagesByID: [String: JSONValue] = [:]

        for text in resultTexts {
            guard let data = text.data(using: .utf8),
                  let value = try? JSONDecoder().decode(JSONValue.self, from: data),
                  let object = value.objectValue else {
                continue
            }
            let messages: [JSONValue]
            if let directMessages = object["messages"]?.arrayValue {
                messages = directMessages
            } else {
                messages = object["messages"]?.objectValue?["matches"]?.arrayValue ?? []
            }

            for message in messages {
                guard let messageObject = message.objectValue else { continue }
                let channel = messageObject["channel"]?.objectValue?["id"]?.stringValue
                    ?? messageObject["channel"]?.objectValue?["name"]?.stringValue
                    ?? ""
                let timestamp = messageObject["ts"]?.stringValue ?? ""
                let fallback = messageObject["permalink"]?.stringValue ?? message.prettyPrinted
                let identifier = timestamp.isEmpty ? fallback : "\(channel)|\(timestamp)"
                messagesByID[identifier] = message
            }
        }

        var messagesByTopic: [String: [JSONValue]] = [:]
        var topicLatestTimestamp: [String: Double] = [:]
        var topicChannel: [String: JSONValue] = [:]
        var topicRootTimestamp: [String: String] = [:]

        for message in messagesByID.values {
            guard let object = message.objectValue else { continue }
            let channel = object["channel"]?.objectValue
            let channelID = channel?["id"]?.stringValue
                ?? channel?["name"]?.stringValue
                ?? ""
            let rootTimestamp = Self.topicRootTimestamp(in: object)
            let topicID = "\(channelID)|\(rootTimestamp)"
            messagesByTopic[topicID, default: []].append(Self.compactedMessage(object))
            topicLatestTimestamp[topicID] = max(
                topicLatestTimestamp[topicID] ?? 0,
                Self.timestamp(in: message)
            )
            topicChannel[topicID] = .object([
                "id": channel?["id"] ?? .null,
                "name": channel?["name"] ?? .null
            ])
            topicRootTimestamp[topicID] = rootTimestamp
        }

        let sortedTopicIDs = messagesByTopic.keys.sorted {
            topicLatestTimestamp[$0, default: 0] > topicLatestTimestamp[$1, default: 0]
        }
        let selectedTopicIDs = Array(sortedTopicIDs.prefix(max(0, limit)))
        let topics = selectedTopicIDs.map { topicID -> JSONValue in
            let messages = (messagesByTopic[topicID] ?? [])
                .sorted { Self.timestamp(in: $0) < Self.timestamp(in: $1) }
            return .object([
                "channel": topicChannel[topicID] ?? .null,
                "thread_ts": .string(topicRootTimestamp[topicID] ?? ""),
                "latest_mention_ts": .number(topicLatestTimestamp[topicID] ?? 0),
                "messages": .array(Array(messages.suffix(3)))
            ])
        }

        return JSONValue.object([
            "topic_limit": .number(Double(limit)),
            "topic_count": .number(Double(topics.count)),
            "topics": .array(topics)
        ]).prettyPrinted
    }

    static func topicCount(in mergedText: String) -> Int {
        guard let data = mergedText.data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            return 0
        }
        return value.objectValue?["topics"]?.arrayValue?.count ?? 0
    }

    private static func normalizedTokens(
        _ text: String,
        prefix: Character,
        maximumCount: Int
    ) -> [String] {
        let allowed = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: "-_."))
        let normalized = text
            .components(separatedBy: CharacterSet(charactersIn: ",;\n"))
            .map { token in
                token
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "#@"))
                    .lowercased()
            }
            .filter { token in
                !token.isEmpty && token.unicodeScalars.allSatisfy(allowed.contains)
            }
            .map { "\(prefix)\($0)" }
            .uniqued()
        return Array(normalized.prefix(maximumCount))
    }

    private static func timestamp(in message: JSONValue) -> Double {
        guard let value = message.objectValue?["ts"] else { return 0 }
        if let string = value.stringValue {
            return Double(string) ?? 0
        }
        if case .number(let number) = value {
            return number
        }
        return 0
    }

    private static func topicRootTimestamp(
        in message: [String: JSONValue]
    ) -> String {
        if let threadTimestamp = message["thread_ts"]?.stringValue, !threadTimestamp.isEmpty {
            return threadTimestamp
        }
        if let permalink = message["permalink"]?.stringValue,
           let components = URLComponents(string: permalink),
           let threadTimestamp = components.queryItems?
               .first(where: { $0.name == "thread_ts" })?
               .value,
           !threadTimestamp.isEmpty {
            return threadTimestamp
        }
        return message["ts"]?.stringValue ?? ""
    }

    private static func compactedMessage(
        _ message: [String: JSONValue]
    ) -> JSONValue {
        let text = message["text"]?.stringValue ?? ""
        return .object([
            "author": message["username"] ?? message["user"] ?? .null,
            "ts": message["ts"] ?? .null,
            "text": .string(String(text.prefix(800))),
            "permalink": message["permalink"] ?? .null
        ])
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}
