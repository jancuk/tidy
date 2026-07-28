import Foundation

struct LanguageToolProvider: GrammarProvider {
    let id = GrammarProviderID.languageTool.rawValue
    let displayName = GrammarProviderID.languageTool.displayName

    func fixGrammar(_ text: String, language: String?) async throws -> String {
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "text", value: text),
            URLQueryItem(name: "language", value: language ?? "auto")
        ]

        var request = URLRequest(url: URL(string: "https://api.languagetool.org/v2/check")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await SecureHTTP.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode ?? 500 < 300 else {
            throw GrammarProviderError.invalidResponse
        }
        let decoded = try JSONDecoder().decode(LanguageToolResponse.self, from: data)
        return apply(matches: decoded.matches, to: text)
    }

    private func apply(matches: [LanguageToolResponse.Match], to text: String) -> String {
        var corrected = text
        for match in matches.sorted(by: { $0.offset > $1.offset }) {
            guard let replacement = match.replacements.first?.value,
                  let start = corrected.index(corrected.startIndex, offsetBy: match.offset, limitedBy: corrected.endIndex),
                  let end = corrected.index(start, offsetBy: match.length, limitedBy: corrected.endIndex) else {
                continue
            }
            corrected.replaceSubrange(start..<end, with: replacement)
        }
        return corrected
    }
}

private struct LanguageToolResponse: Decodable {
    let matches: [Match]

    struct Match: Decodable {
        let offset: Int
        let length: Int
        let replacements: [Replacement]
    }

    struct Replacement: Decodable {
        let value: String
    }
}
