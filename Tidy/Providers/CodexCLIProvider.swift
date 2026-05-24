import Foundation

struct CodexCLIProvider: GrammarProvider {
    let id = GrammarProviderID.codexCLI.rawValue
    let displayName = GrammarProviderID.codexCLI.displayName

    func fixGrammar(_ text: String, language: String?) async throws -> String {
        let prompt = """
        \(GrammarProviderFactory.prompt)

        \(GrammarProviderFactory.inputPrompt(for: text))
        """

        let corrected = try await CodexCLIService.run(
            prompt: prompt,
            timeout: 120
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !corrected.isEmpty else { throw GrammarProviderError.emptyCorrection }
        return corrected
    }
}
