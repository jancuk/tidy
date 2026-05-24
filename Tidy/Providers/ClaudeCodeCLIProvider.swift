import Foundation

struct ClaudeCodeCLIProvider: GrammarProvider {
    let id = GrammarProviderID.claudeCLI.rawValue
    let displayName = GrammarProviderID.claudeCLI.displayName

    func fixGrammar(_ text: String, language: String?) async throws -> String {
        let prompt = """
        \(GrammarProviderFactory.prompt)

        \(GrammarProviderFactory.inputPrompt(for: text))
        """

        let corrected = try await ClaudeCodeCLIService.run(prompt: prompt, timeout: 120)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !corrected.isEmpty else { throw GrammarProviderError.emptyCorrection }
        return corrected
    }
}
