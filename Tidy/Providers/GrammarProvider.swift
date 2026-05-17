import Foundation

protocol GrammarProvider {
    var id: String { get }
    var displayName: String { get }
    func fixGrammar(_ text: String, language: String?) async throws -> String
}

enum GrammarProviderError: LocalizedError {
    case missingAPIKey(String)
    case invalidResponse
    case emptyCorrection

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider):
            "Add your \(provider) API key in Settings first."
        case .invalidResponse:
            "The grammar provider returned an unexpected response."
        case .emptyCorrection:
            "The grammar provider returned an empty correction."
        }
    }
}

enum GrammarProviderFactory {
    static func provider(for id: GrammarProviderID) -> GrammarProvider {
        switch id {
        case .gemini:
            GeminiProvider()
        case .openAI:
            OpenAIProvider()
        case .anthropic:
            AnthropicProvider()
        case .languageTool:
            LanguageToolProvider()
        }
    }

    static let prompt = """
    Correct grammar, spelling, punctuation, and clarity in the user's text.
    Preserve the original meaning, tone, formatting, line breaks, and language.
    Return ONLY the corrected text with no commentary.
    """
}
