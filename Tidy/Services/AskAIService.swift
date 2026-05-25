import Foundation

struct AskAIMessage: Identifiable, Equatable {
    enum Role: String, Equatable {
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    let content: String
    let createdAt: Date

    init(id: UUID = UUID(), role: Role, content: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

enum AskAISource: String, CaseIterable, Identifiable, Hashable {
    case llmWiki
    case folder

    var id: String { rawValue }

    var title: String {
        switch self {
        case .llmWiki: "llm-wiki"
        case .folder: "Folder"
        }
    }

    var subtitle: String {
        switch self {
        case .llmWiki: "coming soon"
        case .folder: "local context"
        }
    }

    var systemImage: String {
        switch self {
        case .llmWiki: "books.vertical"
        case .folder: "folder"
        }
    }
}

enum AskAIMCPSource: String, CaseIterable, Identifiable, Hashable {
    case slack = "mcp-slack"
    case jira = "mcp-jira"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .slack: "Slack"
        case .jira: "Jira"
        }
    }

    var mention: String { "@\(rawValue)" }

    var systemImage: String {
        switch self {
        case .slack: "bubble.left.and.bubble.right"
        case .jira: "list.bullet.rectangle"
        }
    }
}

struct AskAIFolderSource: Identifiable, Hashable {
    let alias: String
    let url: URL

    var id: String { url.path }
    var mention: String { "@!\(alias)" }
    var displayName: String { "\(mention) (\(url.path))" }
}

struct AskAIContext {
    var enabledSources: Set<AskAISource>
    var mcpSources: Set<AskAIMCPSource>
    var folderURLs: [URL]
}

struct AskAICLISession {
    var codexThreadID: String?
    var claudeSessionID: String?
}

enum AskAIMentionParser {
    static func mcpSources(in text: String) -> Set<AskAIMCPSource> {
        let tokens = mentionTokens(in: text, prefix: "@")
        return Set(tokens.compactMap { AskAIMCPSource(rawValue: $0) })
    }

    static func folderSources(in text: String, availableFolders: [AskAIFolderSource]) -> [AskAIFolderSource] {
        let tokens = Set((folderMentionTokens(in: text) + mentionTokens(in: text, prefix: "/")).map { $0.lowercased() })
        var seen = Set<String>()
        return availableFolders.filter { source in
            guard tokens.contains(source.alias.lowercased()), !seen.contains(source.id) else { return false }
            seen.insert(source.id)
            return true
        }
    }

    static func currentMention(in text: String) -> AskAIMentionMode? {
        guard text.last?.isWhitespace != true else { return nil }
        guard let token = text.split(whereSeparator: \.isWhitespace).last.map(String.init) else { return nil }
        if token.hasPrefix("@!") {
            return .folder(String(token.dropFirst(2)))
        }
        if token.hasPrefix("@") {
            return .mcp(String(token.dropFirst()))
        }
        return nil
    }

    static func replacingCurrentMention(in text: String, with mention: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let lastRange = trimmed.rangeOfCharacter(from: .whitespacesAndNewlines, options: .backwards) else {
            return "\(mention) "
        }

        let tokenStart = trimmed.index(after: lastRange.lowerBound)
        let currentToken = String(trimmed[tokenStart...])
        guard currentToken.hasPrefix("@") else {
            return trimmed.isEmpty ? "\(mention) " : "\(trimmed) \(mention) "
        }

        trimmed.replaceSubrange(tokenStart..<trimmed.endIndex, with: mention)
        return "\(trimmed) "
    }

    static func removingCurrentMention(in text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let lastRange = trimmed.rangeOfCharacter(from: .whitespacesAndNewlines, options: .backwards) else {
            return trimmed.hasPrefix("@") ? "" : trimmed
        }

        let tokenStart = trimmed.index(after: lastRange.lowerBound)
        let currentToken = String(trimmed[tokenStart...])
        guard currentToken.hasPrefix("@") else { return trimmed }
        trimmed.removeSubrange(tokenStart..<trimmed.endIndex)
        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func mentionTokens(in text: String, prefix: Character) -> [String] {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_./"))
        var tokens: [String] = []
        var index = text.startIndex

        while index < text.endIndex {
            guard text[index] == prefix else {
                index = text.index(after: index)
                continue
            }

            let tokenStart = text.index(after: index)
            var tokenEnd = tokenStart
            while tokenEnd < text.endIndex {
                let scalar = text[tokenEnd].unicodeScalars.first
                guard let scalar, allowed.contains(scalar) else { break }
                tokenEnd = text.index(after: tokenEnd)
            }

            if tokenStart < tokenEnd {
                if prefix == "/", let slashIndex = text[tokenStart..<tokenEnd].firstIndex(of: "/") {
                    tokenEnd = slashIndex
                }
                tokens.append(String(text[tokenStart..<tokenEnd]))
            }
            index = tokenEnd
        }

        return tokens
    }

    private static func folderMentionTokens(in text: String) -> [String] {
        text
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { $0.hasPrefix("@!") }
            .map { String($0.dropFirst(2)) }
            .filter { !$0.isEmpty }
    }
}

enum AskAIMentionMode: Equatable {
    case mcp(String)
    case folder(String)
}

enum AskAIError: LocalizedError {
    case providerUnavailable
    case invalidResponse
    case httpError(status: Int, body: String)
    case emptyAnswer

    var errorDescription: String? {
        switch self {
        case .providerUnavailable:
            "Ask AI needs Gemini, OpenAI, Anthropic, OpenCode, Ollama, Codex CLI, or Claude (Subscription). Choose one in Settings."
        case .invalidResponse:
            "The AI provider returned an unexpected response."
        case .httpError(let status, let body):
            "API error \(status): \(String(body.prefix(180)))"
        case .emptyAnswer:
            "The AI provider returned an empty answer."
        }
    }
}

struct AskAIService {
    func ask(
        _ question: String,
        history: [AskAIMessage],
        context: AskAIContext,
        logStore: AIRequestLogStore,
        cliSession: AskAICLISession = AskAICLISession(),
        progressHandler: @escaping (String) -> Void = { _ in },
        sessionUpdateHandler: @escaping (GrammarProviderID, String) -> Void = { _, _ in }
    ) async throws -> String {
        let providerID = GrammarProviderID(rawValue: UserDefaults.standard.string(forKey: AppDefaults.grammarProvider) ?? "") ?? .gemini
        let providerName = providerID.displayName
        let start = Date()

        do {
            let answer = try await performAsk(
                question: question,
                history: history,
                context: context,
                providerID: providerID,
                cliSession: cliSession,
                progressHandler: progressHandler,
                sessionUpdateHandler: sessionUpdateHandler
            )
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            Task { @MainActor in
                logStore.append(AIRequestLogEntry(
                    providerName: providerName,
                    requestPreview: String(question.prefix(100)),
                    durationMs: ms,
                    source: "ask-ai"
                ))
            }
            return answer
        } catch {
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            Task { @MainActor in
                logStore.append(AIRequestLogEntry(
                    providerName: providerName,
                    requestPreview: String(question.prefix(100)),
                    statusCode: httpStatus(from: error),
                    errorMessage: error.localizedDescription,
                    durationMs: ms,
                    source: "ask-ai"
                ))
            }
            throw error
        }
    }

    private func httpStatus(from error: Error) -> Int? {
        if case AskAIError.httpError(let status, _) = error { return status }
        return nil
    }

    private func performAsk(
        question: String,
        history: [AskAIMessage],
        context: AskAIContext,
        providerID: GrammarProviderID,
        cliSession: AskAICLISession,
        progressHandler: @escaping (String) -> Void,
        sessionUpdateHandler: @escaping (GrammarProviderID, String) -> Void
    ) async throws -> String {
        // CLI-based providers are handled before the switch (special prompt-based invocation)
        if providerID == .codexCLI {
            return try await askCodexCLI(
                question: question,
                history: history,
                context: context,
                resumeThreadID: cliSession.codexThreadID,
                progressHandler: progressHandler,
                sessionUpdateHandler: sessionUpdateHandler
            )
        }
        if providerID == .claudeCLI {
            return try await askClaudeCLI(
                question: question,
                history: history,
                context: context,
                resumeSessionID: cliSession.claudeSessionID,
                progressHandler: progressHandler,
                sessionUpdateHandler: sessionUpdateHandler
            )
        }

        let messages = buildMessages(question: question, history: history, context: context)

        switch providerID {
        case .gemini:
            return try await askGemini(messages: messages)
        case .openAI:
            return try await askOpenAI(messages: messages)
        case .anthropic:
            return try await askAnthropic(messages: messages)
        case .openCode:
            return try await askOpenCode(messages: messages)
        case .ollama:
            return try await askOllama(messages: messages)
        case .languageTool, .codexCLI, .claudeCLI:
            throw AskAIError.providerUnavailable
        }
    }

    private func buildMessages(question: String, history: [AskAIMessage], context: AskAIContext) -> [ChatMessage] {
        var messages = [ChatMessage(role: "system", content: systemPrompt(question: question, context: context))]

        let recentHistory = history.suffix(8)
        for message in recentHistory {
            messages.append(ChatMessage(role: message.role.rawValue, content: message.content))
        }

        messages.append(ChatMessage(role: "user", content: question))
        return messages
    }

    private func systemPrompt(question: String, context: AskAIContext) -> String {
        var prompt = """
        You are Tidy Ask AI, a concise Mac assistant with Codex-like local folder awareness.
        Answer the user's question directly. When selected folders are supplied, treat them as the current workspace and use them as the authoritative context for project questions.
        Use the workspace map, git context, symbol index, and supplied files before answering, the same way a repo-aware coding assistant would first inspect the repository.
        Cite relative file paths when that helps. Do not say you lack project information if the selected folder context includes project files, a README, symbol index, or a project map.
        If the selected folders do not contain enough information, say exactly what is missing or which file would be needed.
        """

        if !context.mcpSources.isEmpty {
            let requestedSources = context.mcpSources
                .map(\.mention)
                .sorted()
                .joined(separator: ", ")
            prompt += "\n\nRequested MCP sources: \(requestedSources). MCP transport is not connected yet in this build, so do not claim you read Slack or Jira data. If the user's request needs those sources, say that the matching MCP server must be configured before live data can be used."
        }

        if context.enabledSources.contains(.llmWiki) {
            prompt += "\n\nllm-wiki source note: llm-wiki integration is not connected yet in this build. Do not claim you used wiki data."
        }

        if !context.folderURLs.isEmpty {
            let folderContext = FolderContextBuilder.context(for: context.folderURLs, question: question)
            if !folderContext.isEmpty {
                prompt += "\n\nSelected folder contexts:\n\(folderContext)"
            }
        }

        return prompt
    }

    private func askGemini(messages: [ChatMessage]) async throws -> String {
        guard let apiKey = apiKey(for: .gemini) ?? ProcessInfo.processInfo.environment["VITE_GEMINI_API_KEY"] ?? ProcessInfo.processInfo.environment["GEMINI_API_KEY"] else {
            throw GrammarProviderError.missingAPIKey("Gemini Flash or VITE_GEMINI_API_KEY")
        }

        var request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-goog-api-key")
        request.httpBody = try JSONEncoder().encode(GeminiChatRequest(
            contents: [
                .init(parts: [.init(text: messages.map { "\($0.role):\n\($0.content)" }.joined(separator: "\n\n"))])
            ],
            generationConfig: .init(temperature: 0.2)
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        let decoded = try JSONDecoder().decode(GeminiChatResponse.self, from: data)
        let answer = decoded.candidates.flatMap { $0.content.parts }.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { throw AskAIError.emptyAnswer }
        return answer
    }

    private func askOpenAI(messages: [ChatMessage]) async throws -> String {
        guard let apiKey = apiKey(for: .openAI) else {
            throw GrammarProviderError.missingAPIKey(GrammarProviderID.openAI.displayName)
        }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(OpenAIChatRequest(
            model: "gpt-4.1-mini",
            messages: messages,
            temperature: 0.2
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        let decoded = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
        let answer = (decoded.choices.first?.message.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { throw AskAIError.emptyAnswer }
        return answer
    }

    private func askAnthropic(messages: [ChatMessage]) async throws -> String {
        guard let apiKey = apiKey(for: .anthropic) else {
            throw GrammarProviderError.missingAPIKey(GrammarProviderID.anthropic.displayName)
        }
        let system = messages.first?.content ?? ""
        let chatMessages = messages.dropFirst().map { AnthropicChatRequest.Message(role: $0.role == "assistant" ? "assistant" : "user", content: $0.content) }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(AnthropicChatRequest(
            model: "claude-3-5-haiku-latest",
            max_tokens: 2048,
            temperature: 0.2,
            system: system,
            messages: chatMessages
        ))

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        let decoded = try JSONDecoder().decode(AnthropicChatResponse.self, from: data)
        let answer = decoded.content.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { throw AskAIError.emptyAnswer }
        return answer
    }

    private func askOpenCode(messages: [ChatMessage]) async throws -> String {
        guard let apiKey = apiKey(for: .openCode) else {
            throw GrammarProviderError.missingAPIKey(GrammarProviderID.openCode.displayName)
        }

        let model = UserDefaults.standard.string(forKey: AppDefaults.openCodeModel)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? "deepseek-v4-flash-free"

        var request = URLRequest(url: URL(string: "https://opencode.ai/zen/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(OpenCodeChatRequest(model: model, messages: messages))

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        let decoded = try JSONDecoder().decode(OpenCodeChatResponse.self, from: data)
        let answer = (decoded.choices.first?.message.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { throw AskAIError.emptyAnswer }
        return answer
    }

    private func askOllama(messages: [ChatMessage]) async throws -> String {
        let defaults = UserDefaults.standard
        let baseURL = (defaults.string(forKey: AppDefaults.ollamaBaseURL) ?? "http://localhost:11434")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let model = (defaults.string(forKey: AppDefaults.ollamaModel) ?? "gnokit/improve-grammar")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let url = URL(string: "\(baseURL)/api/chat") else {
            throw AskAIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(OllamaChatRequest(model: model, stream: false, messages: messages))

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        let decoded = try JSONDecoder().decode(OllamaChatResponse.self, from: data)
        let answer = decoded.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { throw AskAIError.emptyAnswer }
        return answer
    }

    private func askCodexCLI(
        question: String,
        history: [AskAIMessage],
        context: AskAIContext,
        resumeThreadID: String?,
        progressHandler: @escaping (String) -> Void,
        sessionUpdateHandler: @escaping (GrammarProviderID, String) -> Void
    ) async throws -> String {
        let recentHistory = history.suffix(8)
            .map { "\($0.role.rawValue.uppercased()):\n\($0.content)" }
            .joined(separator: "\n\n")
        let folderList = context.folderURLs
            .map(\.path)
            .joined(separator: "\n")

        let prompt: String
        if resumeThreadID == nil {
            prompt = """
        You are running inside Tidy as the Codex CLI model.
        Answer the user's question using Codex's normal repository-reading behavior.
        Do not modify files. Do not run write commands. Inspect/read only.
        Keep the repo inspection bounded: start with fast file/search commands, inspect only the files needed for the question, and answer without doing a broad full-repo review.
        If a selected folder is broad, such as the user's home folder, do not inspect macOS privacy-sensitive folders like Desktop, Documents, Downloads, Pictures, Photos libraries, Movies, or Music unless that exact folder was explicitly selected.
        Use structured Markdown with short sections, blank lines between blocks, and bullets or tables for lists. Cite relative file paths when helpful.

        Selected folders:
        \(folderList.isEmpty ? "(none)" : folderList)

        Conversation so far:
        \(recentHistory.isEmpty ? "(none)" : recentHistory)

        User question:
        \(question)
        """
        } else {
            prompt = """
        Continue the existing Tidy Ask AI session.
        Keep the same read-only behavior: do not modify files and do not run write commands.
        Answer the follow-up directly using the existing repo context and inspect only if needed.
        Use structured Markdown with short sections, blank lines between blocks, and bullets or tables for lists. Cite relative file paths when helpful.

        User question:
        \(question)
        """
        }

        let workingDirectory = context.folderURLs.first
        let additionalDirectories = Array(context.folderURLs.dropFirst())
        let result = try await CodexCLIService.runWithResult(
            prompt: prompt,
            workingDirectory: workingDirectory,
            additionalDirectories: additionalDirectories,
            resumeThreadID: resumeThreadID,
            timeout: 600,
            progressHandler: progressHandler
        )
        if let threadID = result.threadID {
            sessionUpdateHandler(.codexCLI, threadID)
        }
        let answer = result.answer.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !answer.isEmpty else { throw AskAIError.emptyAnswer }
        return answer
    }

    private func askClaudeCLI(
        question: String,
        history: [AskAIMessage],
        context: AskAIContext,
        resumeSessionID: String?,
        progressHandler: @escaping (String) -> Void,
        sessionUpdateHandler: @escaping (GrammarProviderID, String) -> Void
    ) async throws -> String {
        let recentHistory = history.suffix(8)
            .map { "\($0.role.rawValue.uppercased()):\n\($0.content)" }
            .joined(separator: "\n\n")
        let folderList = context.folderURLs
            .map(\.path)
            .joined(separator: "\n")

        let prompt: String
        if resumeSessionID == nil {
            prompt = """
        You are an AI assistant running inside Tidy.
        Answer the user's question concisely using structured Markdown with short sections, blank lines between blocks, and bullets or tables for lists. Cite relative file paths when helpful.
        If a selected folder is broad, such as the user's home folder, do not inspect macOS privacy-sensitive folders like Desktop, Documents, Downloads, Pictures, Photos libraries, Movies, or Music unless that exact folder was explicitly selected.

        Selected folders:
        \(folderList.isEmpty ? "(none)" : folderList)

        Conversation so far:
        \(recentHistory.isEmpty ? "(none)" : recentHistory)

        User question:
        \(question)
        """
        } else {
            prompt = """
        Continue the existing Tidy Ask AI session.
        Answer the follow-up directly using the existing repo context and inspect only if needed.
        Use structured Markdown with short sections, blank lines between blocks, and bullets or tables for lists. Cite relative file paths when helpful.

        User question:
        \(question)
        """
        }

        let workingDirectory = context.folderURLs.first
        let additionalDirectories = Array(context.folderURLs.dropFirst())
        let result = try await ClaudeCodeCLIService.runWithResult(
            prompt: prompt,
            workingDirectory: workingDirectory,
            additionalDirectories: additionalDirectories,
            resumeSessionID: resumeSessionID,
            timeout: 600,
            progressHandler: progressHandler
        )
        if let sessionID = result.sessionID {
            sessionUpdateHandler(.claudeCLI, sessionID)
        }
        let answer = result.answer.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !answer.isEmpty else { throw AskAIError.emptyAnswer }
        return answer
    }

    private func apiKey(for provider: GrammarProviderID) -> String? {
        let value = KeychainStore.read(key: provider.rawValue)
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }

    private func validate(response: URLResponse, data: Data) throws {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 500
        guard status < 300 else {
            throw AskAIError.httpError(status: status, body: String(data: data, encoding: .utf8) ?? "(no body)")
        }
    }
}

struct FolderContextBuilder {
    static func context(for folderURLs: [URL], question: String = "") -> String {
        folderURLs
            .map { context(for: $0, question: question) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    static func context(for folderURL: URL, question: String = "") -> String {
        let didAccess = folderURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                folderURL.stopAccessingSecurityScopedResource()
            }
        }

        let fileManager = FileManager.default
        let rootSummary = rootSummary(for: folderURL, fileManager: fileManager)
        let projectSignals = projectSignals(for: folderURL, fileManager: fileManager)
        let gitContext = gitContext(for: folderURL)
        let projectMap = projectMap(for: folderURL, fileManager: fileManager)
        let symbolIndex = symbolIndex(for: folderURL, fileManager: fileManager)
        guard let enumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return ""
        }

        var candidates: [FolderContextFile] = []
        var totalCharacters = 0
        let maxFiles = 36
        let maxCharacters = 140_000
        let maxPerFile = 10_000
        let skippedDirectories = skippedDirectoryNames
        let priorityRelativePaths = [
            "README.md",
            "README",
            "readme.md",
            "AGENT.md",
            "CLAUDE.md",
            "CONTRIBUTING.md",
            "package.json",
            "Package.swift",
            "pyproject.toml",
            "Cargo.toml",
            "go.mod",
            "Gemfile",
            "Podfile",
            "Local.xcconfig",
            "Tidy.xcodeproj/project.pbxproj"
        ]
        var seenPaths = Set<String>()
        let queryTokens = queryTokens(from: question)

        for (index, relativePath) in priorityRelativePaths.enumerated() {
            let url = folderURL.appendingPathComponent(relativePath)
            guard fileManager.fileExists(atPath: url.path),
                  let file = contextFile(
                    for: url,
                    rootURL: folderURL,
                    queryTokens: queryTokens,
                    priorityScore: 2_000 - index
                  ) else {
                continue
            }
            candidates.append(file)
            seenPaths.insert(url.standardizedFileURL.path)
        }

        for case let fileURL as URL in enumerator {
            let name = fileURL.lastPathComponent
            guard !seenPaths.contains(fileURL.standardizedFileURL.path) else { continue }
            let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey])

            if values?.isDirectory == true {
                if skippedDirectories.contains(name) || isPrivacySensitiveDescendant(fileURL, rootURL: folderURL) {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard values?.isRegularFile == true,
                  isReadableTextFile(fileURL),
                  (values?.fileSize ?? 0) <= 200_000 else {
                continue
            }

            guard let file = contextFile(
                for: fileURL,
                rootURL: folderURL,
                queryTokens: queryTokens,
                priorityScore: 0
            ) else {
                continue
            }

            candidates.append(file)
            seenPaths.insert(fileURL.standardizedFileURL.path)

            if candidates.count >= 700 {
                break
            }
        }

        let selectedFiles = candidates
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.relativePath.localizedCaseInsensitiveCompare(rhs.relativePath) == .orderedAscending
                }
                return lhs.score > rhs.score
            }
            .prefix(maxFiles)

        var chunks: [String] = []
        for file in selectedFiles {
            let chunk = chunk(for: file, maxCharacters: maxPerFile)
            guard totalCharacters + chunk.count <= maxCharacters else { continue }
            chunks.append(chunk)
            totalCharacters += chunk.count
        }

        guard !chunks.isEmpty else {
            return """
            Selected folder: \(folderURL.path)
            \(rootSummary)
            \(projectSignals)
            Git context:
            \(gitContext)
            Project map:
            \(projectMap)
            Code symbol index:
            \(symbolIndex)
            No readable text files were found in the selected folder.
            """
        }

        return """
        Selected folder: \(folderURL.path)
        \(rootSummary)
        \(projectSignals)
        Git context:
        \(gitContext)
        Project map:
        \(projectMap)
        Code symbol index:
        \(symbolIndex)
        Relevant files supplied to the model:

        \(chunks.joined(separator: "\n\n"))
        """
    }

    private static func rootSummary(for folderURL: URL, fileManager: FileManager) -> String {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return "Root entries: unavailable"
        }

        let names = entries
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            .prefix(40)
            .map { url -> String in
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                return isDirectory ? "\(url.lastPathComponent)/" : url.lastPathComponent
            }
            .joined(separator: ", ")

        return names.isEmpty ? "Root entries: none" : "Root entries: \(names)"
    }

    private static func projectSignals(for folderURL: URL, fileManager: FileManager) -> String {
        let entries = (try? fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var signals: [String] = []
        if fileManager.fileExists(atPath: folderURL.appendingPathComponent("README.md").path) {
            signals.append("README.md")
        }
        if fileManager.fileExists(atPath: folderURL.appendingPathComponent("Package.swift").path) {
            signals.append("Swift Package")
        }
        if fileManager.fileExists(atPath: folderURL.appendingPathComponent("package.json").path) {
            signals.append("Node package")
        }
        if fileManager.fileExists(atPath: folderURL.appendingPathComponent("pyproject.toml").path) {
            signals.append("Python project")
        }

        let xcodeProjects = entries
            .filter { $0.pathExtension == "xcodeproj" }
            .map { "\($0.deletingPathExtension().lastPathComponent) Xcode project" }
        signals.append(contentsOf: xcodeProjects)

        return signals.isEmpty
            ? "Detected project signals: none"
            : "Detected project signals: \(signals.joined(separator: ", "))"
    }

    private static func gitContext(for folderURL: URL) -> String {
        let gitDirectory = folderURL.appendingPathComponent(".git")
        guard FileManager.default.fileExists(atPath: gitDirectory.path) else {
            return "- no git repository detected at this folder root"
        }

        let status = gitOutput(["-C", folderURL.path, "status", "--short", "--branch"])
        let recentCommits = gitOutput(["-C", folderURL.path, "log", "-5", "--oneline", "--decorate"])

        var sections: [String] = []
        if let status, !status.isEmpty {
            sections.append("Status:\n\(status)")
        }
        if let recentCommits, !recentCommits.isEmpty {
            sections.append("Recent commits:\n\(recentCommits)")
        }

        return sections.isEmpty ? "- git repository detected, but git output was unavailable" : sections.joined(separator: "\n")
    }

    private static func projectMap(for folderURL: URL, fileManager: FileManager) -> String {
        guard let enumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return "- unavailable"
        }

        var lines: [String] = []
        for case let url as URL in enumerator {
            let relativePath = relativePath(for: url, rootURL: folderURL)
            let name = url.lastPathComponent
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])

            if values?.isDirectory == true {
                if skippedDirectoryNames.contains(name) || isPrivacySensitiveDescendant(url, rootURL: folderURL) {
                    enumerator.skipDescendants()
                    continue
                }
                if pathDepth(relativePath) <= 3 {
                    lines.append("- \(relativePath)/")
                }
                continue
            }

            guard values?.isRegularFile == true, isReadableTextFile(url) || isProjectMetadata(url) else { continue }
            if pathDepth(relativePath) <= 3 {
                lines.append("- \(relativePath)")
            }

            if lines.count >= 180 {
                lines.append("- ...")
                break
            }
        }

        return lines.isEmpty ? "- no visible project files" : lines.joined(separator: "\n")
    }

    private static func symbolIndex(for folderURL: URL, fileManager: FileManager) -> String {
        guard let enumerator = fileManager.enumerator(
            at: folderURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return "- unavailable"
        }

        var lines: [String] = []
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey])

            if values?.isDirectory == true {
                if skippedDirectoryNames.contains(name) || isPrivacySensitiveDescendant(url, rootURL: folderURL) {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard values?.isRegularFile == true,
                  isSourceFile(url),
                  (values?.fileSize ?? 0) <= 200_000,
                  let declarations = declarations(in: url),
                  !declarations.isEmpty else {
                continue
            }

            let relativePath = relativePath(for: url, rootURL: folderURL)
            lines.append("- \(relativePath): \(declarations.prefix(8).joined(separator: "; "))")

            if lines.count >= 220 {
                lines.append("- ...")
                break
            }
        }

        return lines.isEmpty ? "- no source declarations detected" : lines.joined(separator: "\n")
    }

    private static func contextFile(
        for fileURL: URL,
        rootURL: URL,
        queryTokens: Set<String>,
        priorityScore: Int
    ) -> FolderContextFile? {
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return nil
        }

        let relativePath = relativePath(for: fileURL, rootURL: rootURL)
        let score = priorityScore
            + baseScore(for: fileURL, relativePath: relativePath)
            + queryScore(relativePath: relativePath, text: text, queryTokens: queryTokens)
        return FolderContextFile(relativePath: relativePath, text: text, score: score)
    }

    private static func chunk(for file: FolderContextFile, maxCharacters: Int) -> String {
        let clipped = String(file.text.prefix(maxCharacters))
        return "--- \(file.relativePath) ---\n\(clipped)"
    }

    private static func relativePath(for url: URL, rootURL: URL) -> String {
        let filePath = url.resolvingSymlinksInPath().standardizedFileURL.path
        let rootPath = rootURL.resolvingSymlinksInPath().standardizedFileURL.path
        if filePath.hasPrefix(rootPath + "/") {
            return String(filePath.dropFirst(rootPath.count + 1))
        }
        return url.lastPathComponent
    }

    private static func pathDepth(_ relativePath: String) -> Int {
        relativePath.split(separator: "/").count
    }

    private static func queryTokens(from question: String) -> Set<String> {
        let stopWords: Set<String> = [
            "the", "and", "for", "with", "this", "that", "what", "whats", "which", "where",
            "when", "how", "why", "are", "you", "can", "please", "into", "from", "about",
            "project", "folder", "repo", "code"
        ]
        let tokens = question
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && !stopWords.contains($0) }
        return Set(tokens)
    }

    private static func baseScore(for fileURL: URL, relativePath: String) -> Int {
        let name = fileURL.lastPathComponent.lowercased()
        let path = relativePath.lowercased()
        let ext = fileURL.pathExtension.lowercased()

        if name.hasPrefix("readme") { return 1_000 }
        if ["agent.md", "claude.md", "contributing.md"].contains(name) { return 920 }
        if isProjectMetadata(fileURL) { return 860 }
        if path.contains("/tests/") || path.contains("test") { return 180 }
        if ["swift", "ts", "tsx", "js", "jsx", "py", "go", "rs", "rb", "java", "kt"].contains(ext) { return 260 }
        if ["md", "txt"].contains(ext) { return 220 }
        if ["json", "yaml", "yml", "plist", "xcconfig"].contains(ext) { return 200 }
        return 80
    }

    private static func queryScore(relativePath: String, text: String, queryTokens: Set<String>) -> Int {
        guard !queryTokens.isEmpty else { return 0 }

        let lowerPath = relativePath.lowercased()
        let lowerText = text.lowercased()
        return queryTokens.reduce(0) { score, token in
            var nextScore = score
            if lowerPath.contains(token) {
                nextScore += 180
            }
            if lowerText.contains(token) {
                nextScore += 70
            }
            return nextScore
        }
    }

    private static func isReadableTextFile(_ url: URL) -> Bool {
        let allowedExtensions: Set<String> = [
            "swift", "md", "txt", "json", "yaml", "yml", "xml", "html", "css", "js", "ts", "tsx", "jsx",
            "py", "rb", "go", "rs", "java", "kt", "c", "h", "m", "mm", "cpp", "hpp", "sh", "zsh",
            "toml", "ini", "env", "plist", "csv", "sql"
        ]
        return allowedExtensions.contains(url.pathExtension.lowercased())
    }

    private static func isSourceFile(_ url: URL) -> Bool {
        [
            "swift", "js", "ts", "tsx", "jsx", "py", "rb", "go", "rs", "java", "kt",
            "c", "h", "m", "mm", "cpp", "hpp"
        ].contains(url.pathExtension.lowercased())
    }

    private static func isProjectMetadata(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        let path = url.path.lowercased()
        return [
            "package.json",
            "package-lock.json",
            "pnpm-lock.yaml",
            "yarn.lock",
            "package.swift",
            "pyproject.toml",
            "cargo.toml",
            "go.mod",
            "gemfile",
            "podfile",
            "local.xcconfig"
        ].contains(name) || path.hasSuffix(".xcodeproj/project.pbxproj")
    }

    private static var skippedDirectoryNames: Set<String> {
        ["node_modules", ".git", "build", "dist", ".next", ".swiftpm", "DerivedData", "Pods", ".venv", "coverage", ".turbo"]
    }

    static func isPrivacySensitiveDescendant(_ url: URL, rootURL: URL) -> Bool {
        let fileURL = url.resolvingSymlinksInPath().standardizedFileURL
        let root = rootURL.resolvingSymlinksInPath().standardizedFileURL
        guard fileURL.path != root.path else { return false }

        let home = FileManager.default.homeDirectoryForCurrentUser
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let protectedHomeChildren = [
            "Desktop",
            "Documents",
            "Downloads",
            "Movies",
            "Music",
            "Pictures"
        ]
        let protectedPaths = Set(protectedHomeChildren.map { home.appendingPathComponent($0, isDirectory: true).path })

        if protectedPaths.contains(fileURL.path), !protectedPaths.contains(root.path) {
            return true
        }

        if fileURL.pathExtension.lowercased() == "photoslibrary", fileURL.path != root.path {
            return true
        }

        return false
    }

    private static func declarations(in fileURL: URL) -> [String]? {
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }

        let declarationPrefixes = [
            "class ", "struct ", "enum ", "protocol ", "actor ", "extension ",
            "func ", "var ", "let ", "final class ", "public class ", "public struct ",
            "private func ", "static func ", "export function ", "export class ",
            "function ", "const ", "interface ", "type "
        ]

        return text
            .split(separator: "\n")
            .map { line in
                line.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { line in
                guard !line.hasPrefix("//"), !line.hasPrefix("*"), !line.hasPrefix("#") else { return false }
                return declarationPrefixes.contains { prefix in line.hasPrefix(prefix) }
            }
            .map { line in
                String(line.prefix(120))
                    .replacingOccurrences(of: "{", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
    }

    private static func gitOutput(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
}

private struct FolderContextFile {
    let relativePath: String
    let text: String
    let score: Int
}

private struct ChatMessage: Encodable {
    let role: String
    let content: String
}

private struct GeminiChatRequest: Encodable {
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

private struct GeminiChatResponse: Decodable {
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

private struct OpenAIChatRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
}

private struct OpenAIChatResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String
    }
}

private struct AnthropicChatRequest: Encodable {
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

private struct AnthropicChatResponse: Decodable {
    let content: [Content]

    struct Content: Decodable {
        let text: String
    }
}

private struct OpenCodeChatRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
}

private struct OpenCodeChatResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String
    }
}

private struct OllamaChatRequest: Encodable {
    let model: String
    let stream: Bool
    let messages: [ChatMessage]
}

private struct OllamaChatResponse: Decodable {
    let message: Message

    struct Message: Decodable {
        let content: String
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
