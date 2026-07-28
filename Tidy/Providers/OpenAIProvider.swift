import Foundation

struct OpenAIProvider: GrammarProvider {
    let id = GrammarProviderID.openAI.rawValue
    let displayName = GrammarProviderID.openAI.displayName

    func fixGrammar(_ text: String, language: String?) async throws -> String {
        guard let apiKey = KeychainStore.read(key: id), !apiKey.isEmpty else {
            throw GrammarProviderError.missingAPIKey(displayName)
        }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(OpenAIRequest(
            model: "gpt-4.1-mini",
            input: [
                .init(role: "system", content: [.init(type: "input_text", text: GrammarProviderFactory.prompt)]),
                .init(role: "user", content: [.init(type: "input_text", text: GrammarProviderFactory.inputPrompt(for: text))])
            ],
            temperature: 0
        ))

        let (data, response) = try await SecureHTTP.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode ?? 500 < 300 else {
            throw GrammarProviderError.invalidResponse
        }
        let decoded = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        let corrected = decoded.output
            .flatMap { $0.content ?? [] }
            .compactMap(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !corrected.isEmpty else { throw GrammarProviderError.emptyCorrection }
        return corrected
    }
}

private struct OpenAIRequest: Encodable {
    let model: String
    let input: [Message]
    let temperature: Double

    struct Message: Encodable {
        let role: String
        let content: [Content]
    }

    struct Content: Encodable {
        let type: String
        let text: String
    }
}

private struct OpenAIResponse: Decodable {
    let output: [Output]

    struct Output: Decodable {
        let content: [Content]?
    }

    struct Content: Decodable {
        let text: String?
    }
}
