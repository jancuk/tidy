import Foundation

enum CodexCLIError: LocalizedError {
    case executableNotFound(String)
    case timedOut
    case failed(status: Int32, output: String)
    case emptyOutput

    var errorDescription: String? {
        switch self {
        case .executableNotFound(let command):
            "Codex CLI was not found. Set the Codex CLI path in Settings -> Model. Current value: \(command)"
        case .timedOut:
            "Codex CLI timed out before returning an answer."
        case .failed(let status, let output):
            "Codex CLI exited with status \(status):\n\(String(output.prefix(240)))"
        case .emptyOutput:
            "Codex CLI returned an empty answer."
        }
    }
}

struct CodexCLIRunResult {
    let answer: String
    let threadID: String?
}

struct CodexCLIJSONEventParser {
    struct Snapshot: Equatable {
        let threadID: String?
        let progressMessage: String?
    }

    static func snapshot(from line: String) -> Snapshot? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"),
              let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else {
            return nil
        }

        let threadID = object["thread_id"] as? String
        var progressMessage: String?

        switch type {
        case "thread.started":
            progressMessage = "Codex session started"
        case "turn.started":
            progressMessage = "Codex is reading the question"
        case "item.started", "item.completed":
            progressMessage = itemProgressMessage(from: object, eventType: type)
        case "turn.completed":
            progressMessage = "Codex finished the answer"
        default:
            break
        }

        guard threadID != nil || progressMessage != nil else { return nil }
        return Snapshot(threadID: threadID, progressMessage: progressMessage)
    }

    private static func itemProgressMessage(from object: [String: Any], eventType: String) -> String? {
        guard let item = object["item"] as? [String: Any],
              let itemType = item["type"] as? String else {
            return nil
        }

        switch itemType {
        case "command_execution":
            let command = (item["command"] as? String).map(displayCommand) ?? "shell command"
            return eventType == "item.started"
                ? "Codex is running `\(command)`"
                : "Codex finished `\(command)`"
        case "agent_message":
            return eventType == "item.completed" ? "Codex is preparing the final response" : nil
        default:
            return nil
        }
    }

    private static func displayCommand(_ command: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let display: String
        if let range = trimmed.range(of: " -lc ") {
            display = String(trimmed[range.upperBound...])
        } else {
            display = trimmed
        }
        return String(display.prefix(90))
    }
}

struct CodexCLIService {
    static var codexHomeURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Tidy/Codex", isDirectory: true)
    }

    static func run(
        prompt: String,
        workingDirectory: URL? = nil,
        additionalDirectories: [URL] = [],
        timeout: TimeInterval = 180,
        progressHandler: @escaping (String) -> Void = { _ in }
    ) async throws -> String {
        try await runWithResult(
            prompt: prompt,
            workingDirectory: workingDirectory,
            additionalDirectories: additionalDirectories,
            timeout: timeout,
            progressHandler: progressHandler
        ).answer
    }

    static func runWithResult(
        prompt: String,
        workingDirectory: URL? = nil,
        additionalDirectories: [URL] = [],
        resumeThreadID: String? = nil,
        timeout: TimeInterval = 180,
        progressHandler: @escaping (String) -> Void = { _ in }
    ) async throws -> CodexCLIRunResult {
        try await Task.detached(priority: .userInitiated) {
            try runSynchronously(
                prompt: prompt,
                workingDirectory: workingDirectory,
                additionalDirectories: additionalDirectories,
                resumeThreadID: resumeThreadID,
                progressHandler: progressHandler,
                timeout: timeout
            )
        }.value
    }

    private static func runSynchronously(
        prompt: String,
        workingDirectory: URL?,
        additionalDirectories: [URL],
        resumeThreadID: String?,
        progressHandler: @escaping (String) -> Void,
        timeout: TimeInterval
    ) throws -> CodexCLIRunResult {
        let accessedFolders = startAccessingSecurityScopedResources(
            for: [workingDirectory].compactMap(\.self) + additionalDirectories
        )
        defer {
            stopAccessingSecurityScopedResources(accessedFolders)
        }

        let configuredCommand = (UserDefaults.standard.string(forKey: AppDefaults.codexCLIPath) ?? "codex")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? "codex"
        let executable = try executableURL(for: configuredCommand)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tidy-codex-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        var arguments = ["exec"]

        if let resumeThreadID {
            arguments += [
                "resume",
                "--json",
                "--config", "approval_policy=\"never\"",
                "--skip-git-repo-check",
                "--output-last-message", outputURL.path
            ]
        } else {
            arguments += [
                "--color", "never",
                "--json",
                "--config", "approval_policy=\"never\"",
                "--skip-git-repo-check",
                "--sandbox", "read-only",
                "--output-last-message", outputURL.path
            ]
        }

        let model = (UserDefaults.standard.string(forKey: AppDefaults.codexCLIModel) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !model.isEmpty {
            arguments += ["--model", model]
        }

        if resumeThreadID == nil, let workingDirectory {
            arguments += ["--cd", workingDirectory.path]
        }

        if resumeThreadID == nil {
            for directory in additionalDirectories {
                arguments += ["--add-dir", directory.path]
            }
        }

        if let resumeThreadID {
            arguments.append(resumeThreadID)
        }

        arguments.append("-")

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = codexEnvironment()

        let stdout = Pipe()
        let stderr = Pipe()
        let stdin = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = stdin

        let eventState = CodexCLIEventState(progressHandler: progressHandler)
        let stdoutCollector = CodexProcessStreamCollector { line in
            eventState.handle(line)
        }
        let stderrCollector = CodexProcessStreamCollector()

        stdout.fileHandleForReading.readabilityHandler = { handle in
            stdoutCollector.append(handle.availableData)
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            stderrCollector.append(handle.availableData)
        }

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }

        try process.run()

        if let data = prompt.data(using: .utf8) {
            stdin.fileHandleForWriting.write(data)
        }
        try? stdin.fileHandleForWriting.close()

        guard finished.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            throw CodexCLIError.timedOut
        }

        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        stdoutCollector.append(stdout.fileHandleForReading.readDataToEndOfFile())
        stderrCollector.append(stderr.fileHandleForReading.readDataToEndOfFile())

        let stdoutText = stdoutCollector.flush()
        let stderrText = stderrCollector.flush()
        let combinedOutput = [stdoutText, stderrText]
            .map(stripANSI)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")

        guard process.terminationStatus == 0 else {
            throw CodexCLIError.failed(status: process.terminationStatus, output: combinedOutput)
        }

        let finalAnswer = (try? String(contentsOf: outputURL, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        let fallbackAnswer = CodexCLIJSONAnswerParser.answer(from: stdoutText)

        guard let answer = finalAnswer ?? fallbackAnswer else {
            throw CodexCLIError.emptyOutput
        }

        return CodexCLIRunResult(answer: answer, threadID: eventState.threadID)
    }

    private static func executableURL(for command: String) throws -> URL {
        let expandedCommand = NSString(string: command).expandingTildeInPath
        if expandedCommand.hasPrefix("/") {
            let url = URL(fileURLWithPath: expandedCommand)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }

        for path in candidateExecutablePaths(for: expandedCommand) {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        throw CodexCLIError.executableNotFound(command)
    }

    private static func startAccessingSecurityScopedResources(for urls: [URL]) -> [URL] {
        urls.filter { $0.startAccessingSecurityScopedResource() }
    }

    private static func stopAccessingSecurityScopedResources(_ urls: [URL]) {
        urls.forEach { $0.stopAccessingSecurityScopedResource() }
    }

    static func resolvedExecutableURL(for command: String) throws -> URL {
        try executableURL(for: command)
    }

    static func codexEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_HOME"] = codexHomeURL.path
        return environment
    }

    private static func candidateExecutablePaths(for command: String) -> [String] {
        let executableName = URL(fileURLWithPath: command).lastPathComponent
        let pathEntries = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
            .map { URL(fileURLWithPath: $0).appendingPathComponent(executableName).path }

        let home = FileManager.default.homeDirectoryForCurrentUser
        var candidates = pathEntries + [
            "/opt/homebrew/bin/\(executableName)",
            "/usr/local/bin/\(executableName)",
            home.appendingPathComponent(".local/bin/\(executableName)").path
        ]

        let nvmRoot = home.appendingPathComponent(".nvm/versions/node")
        if let versions = try? FileManager.default.contentsOfDirectory(at: nvmRoot, includingPropertiesForKeys: nil) {
            candidates += versions
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }
                .map { $0.appendingPathComponent("bin/\(executableName)").path }
        }

        return candidates
    }
}

private final class CodexCLIEventState {
    private let lock = NSLock()
    private var storedThreadID: String?
    private var lastProgressMessage = ""
    private let progressHandler: (String) -> Void

    init(progressHandler: @escaping (String) -> Void) {
        self.progressHandler = progressHandler
    }

    var threadID: String? {
        lock.lock()
        defer { lock.unlock() }
        return storedThreadID
    }

    func handle(_ line: String) {
        guard let snapshot = CodexCLIJSONEventParser.snapshot(from: line) else { return }
        if let threadID = snapshot.threadID {
            setThreadID(threadID)
        }
        if let progressMessage = snapshot.progressMessage {
            emit(progressMessage)
        }
    }

    private func setThreadID(_ threadID: String) {
        lock.lock()
        storedThreadID = threadID
        lock.unlock()
    }

    private func emit(_ message: String) {
        lock.lock()
        guard message != lastProgressMessage else {
            lock.unlock()
            return
        }
        lastProgressMessage = message
        lock.unlock()
        progressHandler(message)
    }
}

private final class CodexProcessStreamCollector {
    private let lock = NSLock()
    private var text = ""
    private var pendingLine = ""
    private let onLine: (String) -> Void

    init(onLine: @escaping (String) -> Void = { _ in }) {
        self.onLine = onLine
    }

    func append(_ data: Data) {
        guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }

        var completedLines: [String] = []
        lock.lock()
        text += chunk
        pendingLine += chunk
        while let newlineRange = pendingLine.range(of: "\n") {
            completedLines.append(String(pendingLine[..<newlineRange.lowerBound]))
            pendingLine.removeSubrange(pendingLine.startIndex...newlineRange.lowerBound)
        }
        lock.unlock()

        completedLines.forEach(onLine)
    }

    func flush() -> String {
        var lineToFlush: String?
        let fullText: String

        lock.lock()
        if !pendingLine.isEmpty {
            lineToFlush = pendingLine
            pendingLine = ""
        }
        fullText = text
        lock.unlock()

        if let lineToFlush {
            onLine(lineToFlush)
        }
        return fullText
    }
}

private enum CodexCLIJSONAnswerParser {
    static func answer(from stdout: String) -> String? {
        stdout
            .components(separatedBy: .newlines)
            .compactMap(agentMessage)
            .last?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    private static func agentMessage(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"),
              let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["type"] as? String == "item.completed",
              let item = object["item"] as? [String: Any],
              item["type"] as? String == "agent_message" else {
            return nil
        }

        return item["text"] as? String
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

private func stripANSI(_ text: String) -> String {
    text.replacingOccurrences(
        of: "\u{001B}\\[[0-9;?]*[ -/]*[@-~]",
        with: "",
        options: .regularExpression
    )
}
