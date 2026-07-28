import Foundation

struct AnthropicProvider: GrammarProvider {
    let id = GrammarProviderID.anthropic.rawValue
    let displayName = GrammarProviderID.anthropic.displayName

    func fixGrammar(_ text: String, language: String?) async throws -> String {
        guard let apiKey = KeychainStore.read(key: id), !apiKey.isEmpty else {
            throw GrammarProviderError.missingAPIKey(displayName)
        }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(AnthropicRequest(
            model: "claude-3-5-haiku-latest",
            max_tokens: max(128, min(4096, text.count * 2)),
            temperature: 0,
            system: GrammarProviderFactory.prompt,
            messages: [.init(role: "user", content: GrammarProviderFactory.inputPrompt(for: text))]
        ))

        let (data, response) = try await SecureHTTP.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode ?? 500 < 300 else {
            throw GrammarProviderError.invalidResponse
        }
        let decoded = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        let corrected = decoded.content
            .map(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !corrected.isEmpty else { throw GrammarProviderError.emptyCorrection }
        return corrected
    }
}

private struct AnthropicRequest: Encodable {
    let model: String
    let max_tokens: Int
    let temperature: Double
    let system: String
    let messages: [Message]

    struct Message: Encodable {
        let role: String
        let content: String
    }
}

private struct AnthropicResponse: Decodable {
    let content: [Content]

    struct Content: Decodable {
        let text: String
    }
}
