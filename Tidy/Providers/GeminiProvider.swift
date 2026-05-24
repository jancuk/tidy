import Foundation

struct GeminiProvider: GrammarProvider {
    let id = GrammarProviderID.gemini.rawValue
    let displayName = GrammarProviderID.gemini.displayName

    func fixGrammar(_ text: String, language: String?) async throws -> String {
        guard let apiKey = apiKey else {
            throw GrammarProviderError.missingAPIKey("Gemini Flash or VITE_GEMINI_API_KEY")
        }

        var request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-goog-api-key")
        request.httpBody = try JSONEncoder().encode(GeminiRequest(
            contents: [
                .init(parts: [
                    .init(text: """
                    \(GrammarProviderFactory.prompt)

                    \(GrammarProviderFactory.inputPrompt(for: text))
                    """)
                ])
            ],
            generationConfig: .init(temperature: 0)
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 500
        guard status < 300 else {
            let body = String(data: data, encoding: .utf8) ?? "(no body)"
            throw GrammarProviderError.httpError(status: status, body: body)
        }

        let decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
        let corrected = decoded.candidates
            .flatMap { $0.content.parts }
            .map(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !corrected.isEmpty else { throw GrammarProviderError.emptyCorrection }
        return corrected
    }

    private var apiKey: String? {
        let environment = ProcessInfo.processInfo.environment
        let value = environment["VITE_GEMINI_API_KEY"] ?? environment["GEMINI_API_KEY"] ?? KeychainStore.read(key: id)
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

private struct GeminiRequest: Encodable {
    let contents: [Content]
    let generationConfig: GenerationConfig

    struct Content: Encodable {
        let parts: [Part]
    }

    struct Part: Encodable {
        let text: String
    }

    struct GenerationConfig: Encodable {
        let temperature: Double
    }
}

private struct GeminiResponse: Decodable {
    let candidates: [Candidate]

    struct Candidate: Decodable {
        let content: Content
    }

    struct Content: Decodable {
        let parts: [Part]
    }

    struct Part: Decodable {
        let text: String
    }
}
