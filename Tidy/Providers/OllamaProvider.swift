import Foundation

struct OllamaProvider: GrammarProvider {
    let id = GrammarProviderID.ollama.rawValue
    let displayName = GrammarProviderID.ollama.displayName

    func fixGrammar(_ text: String, language: String?) async throws -> String {
        let defaults = UserDefaults.standard
        let baseURL = (defaults.string(forKey: AppDefaults.ollamaBaseURL) ?? "http://localhost:11434")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let model = (defaults.string(forKey: AppDefaults.ollamaModel) ?? "gnokit/improve-grammar")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let url = URL(string: "\(baseURL)/api/chat") else {
            throw GrammarProviderError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60 // local models can be slow
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let messages: [OllamaRequest.Message] = [
            .init(role: "system", content: GrammarProviderFactory.prompt),
            .init(role: "user", content: GrammarProviderFactory.inputPrompt(for: text))
        ]

        request.httpBody = try JSONEncoder().encode(OllamaRequest(
            model: model,
            stream: false,
            messages: messages
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 500
        guard status < 300 else {
            let body = String(data: data, encoding: .utf8) ?? "(no body)"
            throw GrammarProviderError.httpError(status: status, body: body)
        }

        let decoded = try JSONDecoder().decode(OllamaResponse.self, from: data)
        let corrected = decoded.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !corrected.isEmpty else { throw GrammarProviderError.emptyCorrection }
        return corrected
    }
}

private struct OllamaRequest: Encodable {
    let model: String
    let stream: Bool
    let messages: [Message]

    struct Message: Encodable {
        let role: String
        let content: String
    }
}

private struct OllamaResponse: Decodable {
    let message: Message

    struct Message: Decodable {
        let content: String
    }
}
