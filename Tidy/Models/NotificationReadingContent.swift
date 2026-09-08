import Foundation

enum NotificationReadingContent {
    static func containsSourceData(_ text: String) -> Bool {
        text.range(of: #"[\{\[]\s*\"|\"(?:topics|topic_count|events|messages|permalink|htmlLink|thread_ts)\"\s*:"#, options: .regularExpression) != nil
    }

    static func readableSummary(_ digest: UnifiedNotificationDigest) -> String? {
        guard containsSourceData(digest.summary) else { return digest.summary }
        return structuredSummary(digest.rawPreview) ?? structuredSummary(digest.summary)
    }

    static func structuredSummary(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data) else { return nil }
        var lines: [String] = []
        collect(value, context: "", into: &lines, depth: 0)
        var seen = Set<String>()
        let unique = lines.filter { !$0.isEmpty && seen.insert($0).inserted }
        guard !unique.isEmpty else { return "No readable items were returned by this source." }
        return unique.prefix(10).map { "- \(String($0.prefix(800)))" }.joined(separator: "\n")
    }

    private static func collect(_ value: Any, context: String, into lines: inout [String], depth: Int) {
        guard depth < 12, lines.count < 30 else { return }
        if let array = value as? [Any] {
            for item in array.prefix(30) { collect(item, context: context, into: &lines, depth: depth + 1) }
        } else if let object = value as? [String: Any] {
            let channel = (object["channel"] as? [String: Any])?["name"] as? String
            let author = object["author"] as? String ?? object["username"] as? String
            let localContext = [channel.map { "#\($0)" } ?? context, author ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
            let fields = ["subject", "title", "summary", "text", "snippet", "description"]
            var content = fields.compactMap { object[$0] as? String }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if let start = object["start"] as? String { content.append(start) }
            else if let start = object["start"] as? [String: Any], let date = start["dateTime"] as? String ?? start["date"] as? String { content.append(date) }
            if !content.isEmpty {
                lines.append((localContext.isEmpty ? "" : localContext + " · ") + content.joined(separator: " — "))
            }
            for key in ["topics", "messages", "matches", "events", "threads", "items", "results", "data", "content"] {
                if let nested = object[key], !(nested is String) { collect(nested, context: localContext, into: &lines, depth: depth + 1) }
            }
        }
    }
}
