import Foundation

struct OpenCodeProvider: GrammarProvider {
    let id = GrammarProviderID.openCode.rawValue
    let displayName = GrammarProviderID.openCode.displayName

    func fixGrammar(_ text: String, language: String?) async throws -> String {
        guard let apiKey = apiKey else {
            throw GrammarProviderError.missingAPIKey(displayName)
        }

        let model = UserDefaults.standard.string(forKey: AppDefaults.openCodeModel)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? "deepseek-v4-flash-free"

        var request = URLRequest(url: URL(string: "https://opencode.ai/zen/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(OpenCodeRequest(
            model: model,
            messages: [
                .init(role: "system", content: GrammarProviderFactory.prompt),
                .init(role: "user", content: GrammarProviderFactory.inputPrompt(for: text))
            ]
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 500
        guard status < 300 else {
            let body = String(data: data, encoding: .utf8) ?? "(no body)"
            throw GrammarProviderError.httpError(status: status, body: body)
        }

        let decoded = try JSONDecoder().decode(OpenCodeResponse.self, from: data)
        let corrected = (decoded.choices.first?.message.content ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !corrected.isEmpty else { throw GrammarProviderError.emptyCorrection }
        return corrected
    }

    private var apiKey: String? {
        let value = KeychainStore.read(key: id)
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

private struct OpenCodeRequest: Encodable {
    let model: String
    let messages: [Message]

    struct Message: Encodable {
        let role: String
        let content: String
    }
}

private struct OpenCodeResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
