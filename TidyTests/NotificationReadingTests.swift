import Foundation
import Testing
@testable import Tidy

struct NotificationReadingTests {
    @Test func rendersStructuredTopicsWithoutMetadataNoise() throws {
        let raw = #"{"topics":[{"channel":{"name":"engineering"},"messages":[{"author":"Sam","text":"Please review the parser.","permalink":"https://example.com/thread","ts":"12345"}]}]}"#
        let summary = try #require(NotificationReadingContent.structuredSummary(raw))
        #expect(summary.contains("#engineering · Sam"))
        #expect(summary.contains("Please review the parser."))
        #expect(!summary.contains("permalink"))
        #expect(!summary.contains("12345"))
    }

    @Test func eventFallbackPreservesEventDateWithoutClaimingItIsUpcoming() throws {
        let summary = try #require(NotificationReadingContent.structuredSummary(#"{"events":[{"summary":"Architecture review","start":{"dateTime":"2025-11-13T10:00:00+07:00"}}]}"#))
        #expect(summary.contains("Architecture review"))
        #expect(summary.contains("2025-11-13"))
        #expect(!summary.contains("upcoming"))
    }

    @Test func damagedCachedSummaryRequiresRefreshAndKeepsOriginalAccessible() {
        let damaged = #"- { "topic_count": 10, "topics": [{ "messages":"#
        let digest = UnifiedNotificationDigest(source: .slack, summary: damaged, rawPreview: "", toolName: "search", fetchedAt: .now)
        #expect(NotificationReadingContent.containsSourceData(damaged))
        #expect(NotificationReadingContent.readableSummary(digest) == nil)
        #expect(digest.summary == damaged)
        #expect(!NotificationBriefingFallback.summarize([digest]).contains("topic_count"))
    }

    @Test func readableMarkdownIsPreserved() {
        let markdown = "**Focus now** — Review the PR.\n- **Read** [the discussion](https://example.com/thread)."
        let digest = UnifiedNotificationDigest(source: .gmail, summary: markdown, rawPreview: "", toolName: "search", fetchedAt: .now)
        #expect(NotificationReadingContent.readableSummary(digest) == markdown)
        #expect(!NotificationReadingContent.containsSourceData(markdown))
    }

    @Test func plainFallbackDoesNotBreakDomainsOrEmailAddresses() {
        let summary = NotificationFallbackSummarizer.summarize("Review https://example.com/pr/42 with sam@example.com. Bring notes to the meeting.")
        #expect(summary.contains("https://example.com/pr/42"))
        #expect(summary.contains("sam@example.com"))
    }

    @Test func structuredFallbackIsBoundedAndDoesNotInventUrgency() throws {
        let data = try JSONSerialization.data(withJSONObject: ["items": (0..<80).map { ["title": "Item \($0)", "description": String(repeating: "a", count: 2000)] }])
        let summary = NotificationFallbackSummarizer.summarize(String(decoding: data, as: UTF8.self))
        #expect(summary.count <= 8040)
        #expect(summary.split(separator: "\n").count == 10)
        #expect(!summary.contains("urgent"))
    }
}
