import Foundation

struct DeepSeekProvider: GrammarProvider {
    let id = GrammarProviderID.deepSeek.rawValue
    let displayName = GrammarProviderID.deepSeek.displayName

    func fixGrammar(_ text: String, language: String?) async throws -> String {
        guard let apiKey = Self.apiKey else {
            throw GrammarProviderError.missingAPIKey(displayName)
        }

        let model = UserDefaults.standard.string(forKey: AppDefaults.deepSeekModel)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? "deepseek-v4-flash"
        var tokenBudget = Self.maxTokens(for: text)

        for attempt in 0...1 {
            let request = try Self.makeRequest(
                text: text,
                apiKey: apiKey,
                model: model,
                maxTokens: tokenBudget
            )

            let (data, response) = try await SecureHTTP.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 500
            guard status < 300 else {
                let body = String(data: data, encoding: .utf8) ?? "(no body)"
                throw GrammarProviderError.httpError(status: status, body: body)
            }

            do {
                return try Self.correctedText(from: data)
            } catch GrammarProviderError.responseTruncated where attempt == 0 {
                tokenBudget = Self.retryMaxTokens(after: tokenBudget)
            }
        }

        throw GrammarProviderError.responseTruncated(displayName)
    }

    static func makeRequest(
        text: String,
        apiKey: String,
        model: String,
        maxTokens: Int? = nil
    ) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.deepseek.com/anthropic/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(DeepSeekRequest(
            model: model,
            maxTokens: maxTokens ?? Self.maxTokens(for: text),
            temperature: 0,
            thinking: .init(type: "disabled"),
            system: GrammarProviderFactory.prompt,
            messages: [.init(role: "user", content: GrammarProviderFactory.inputPrompt(for: text))]
        ))
        return request
    }

    static func maxTokens(for text: String) -> Int {
        max(1_024, min(8_192, text.count * 2 + 512))
    }

    static func retryMaxTokens(after initialBudget: Int) -> Int {
        min(16_384, max(initialBudget + 1_024, initialBudget * 2))
    }

    static func correctedText(from data: Data) throws -> String {
        let decoded = try JSONDecoder().decode(DeepSeekResponse.self, from: data)
        guard decoded.stopReason != "max_tokens" else {
            throw GrammarProviderError.responseTruncated(GrammarProviderID.deepSeek.displayName)
        }

        let corrected = decoded.content
            .compactMap(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !corrected.isEmpty else {
            throw GrammarProviderError.emptyCorrection
        }
        return corrected
    }

    private static var apiKey: String? {
        let value = KeychainStore.read(key: GrammarProviderID.deepSeek.rawValue)
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

private struct DeepSeekRequest: Encodable {
    let model: String
    let maxTokens: Int
    let temperature: Double
    let thinking: Thinking
    let system: String
    let messages: [Message]

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case temperature
        case thinking
        case system
        case messages
    }

    struct Thinking: Encodable {
        let type: String
    }

    struct Message: Encodable {
        let role: String
        let content: String
    }
}

private struct DeepSeekResponse: Decodable {
    let content: [Content]
    let stopReason: String?

    enum CodingKeys: String, CodingKey {
        case content
        case stopReason = "stop_reason"
    }

    struct Content: Decodable {
        let text: String?
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
