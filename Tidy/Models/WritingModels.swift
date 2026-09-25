import Foundation

struct WritingDraft: Codable, Identifiable, Equatable {
    var item: ProductivityItem
    var source: String
    var updatedAt: Date
    var baseUpdatedAt: Date?
    var id: UUID { item.id }
    var title: String { source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled draft" : MarkdownDocument.plainTitle(from: source) }
}

enum WritingStarter: String, CaseIterable, Identifiable {
    case blank, journal, email, idea, brief
    var id: String { rawValue }
    var title: String {
        switch self {
        case .blank: "Blank page"
        case .journal: "Journal"
        case .email: "Email"
        case .idea: "Explore an idea"
        case .brief: "Project brief"
        }
    }
    var detail: String {
        switch self {
        case .blank: "Follow your own thought"
        case .journal: "Make sense of your day"
        case .email: "Find the words to send"
        case .idea: "Turn a spark into a plan"
        case .brief: "Give your work direction"
        }
    }
    var icon: String {
        switch self {
        case .blank: "square.and.pencil"
        case .journal: "sun.horizon"
        case .email: "envelope"
        case .idea: "lightbulb"
        case .brief: "doc.text"
        }
    }
    var source: String {
        switch self {
        case .blank: ""
        case .journal: "# A moment for today\n\n## What's on my mind\n\n\n## One thing I appreciated\n\n\n## What I want to carry into tomorrow\n\n"
        case .email: "# Subject\n\nHi,\n\n\n\nThanks,\n"
        case .idea: "# An idea worth exploring\n\n## The idea\n\n\n## Why it matters\n\n\n## The smallest next step\n\n"
        case .brief: "# Project brief\n\n## What we're trying to achieve\n\n\n## Who this is for\n\n\n## What success looks like\n\n\n## Next steps\n\n- [ ] \n"
        }
    }
}

enum WritingMetrics {
    static func wordCount(_ source: String) -> Int {
        source.split(whereSeparator: { $0.isWhitespace }).filter { token in
            token.contains { $0.isLetter || $0.isNumber }
        }.count
    }
}
