import Foundation

struct ClipboardEntry: Identifiable, Equatable {
    let id: Int64
    let content: String
    let preview: String
    let sourceAppBundleID: String?
    let sourceAppName: String?
    let createdAt: Date
    let charCount: Int
}

struct CorrectionLogEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let original: String
    let corrected: String
    let providerID: String
    let createdAt: Date

    init(id: UUID = UUID(), original: String, corrected: String, providerID: String, createdAt: Date = Date()) {
        self.id = id
        self.original = original
        self.corrected = corrected
        self.providerID = providerID
        self.createdAt = createdAt
    }
}

enum GrammarProviderID: String, CaseIterable, Identifiable {
    case gemini
    case openAI = "openai"
    case anthropic
    case languageTool = "languagetool"
    case openCode = "opencode"
    case ollama

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gemini:
            "Gemini Flash"
        case .openAI:
            "OpenAI"
        case .anthropic:
            "Anthropic"
        case .languageTool:
            "LanguageTool"
        case .openCode:
            "OpenCode (Zen)"
        case .ollama:
            "Ollama (Local)"
        }
    }

    var requiresAPIKey: Bool {
        switch self {
        case .ollama:
            false
        default:
            true
        }
    }
}
