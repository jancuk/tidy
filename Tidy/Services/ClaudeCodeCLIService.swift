import Foundation

enum ClaudeCodeCLIError: LocalizedError {
    case executableNotFound(String)
    case timedOut
    case failed(status: Int32, output: String)
    case emptyOutput

    var errorDescription: String? {
        switch self {
        case .executableNotFound(let command):
            "Claude Code CLI was not found. Set the path in Settings → Model. Current value: \(command)"
        case .timedOut:
            "Claude Code CLI timed out before returning an answer."
        case .failed(let status, let output):
            "Claude Code CLI exited with status \(status):\n\(String(output.prefix(240)))"
        case .emptyOutput:
            "Claude Code CLI returned an empty answer."
        }
    }
}

struct ClaudeCodeCLIRunResult {
    let answer: String
    let sessionID: String?
}

struct ClaudeCodeStreamEventParser {
    struct Snapshot: Equatable {
        let sessionID: String?
        let progressMessage: String?
        let answer: String?
    }

    static func snapshot(from line: String) -> Snapshot? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"),
              let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else {
            return nil
        }

        let sessionID = object["session_id"] as? String
        var progressMessage: String?
        var answer: String?

        switch type {
        case "system":
            if object["subtype"] as? String == "init" {
                progressMessage = "Claude Code session started"
            }
        case "stream_event":
            progressMessage = streamProgressMessage(from: object)
        case "assistant":
            progressMessage = "Claude Code is preparing the final response"
            answer = assistantAnswer(from: object)
        case "result":
            progressMessage = "Claude Code finished the answer"
            answer = object["result"] as? String
        default:
            break
        }

        guard sessionID != nil || progressMessage != nil || answer != nil else { return nil }
        return Snapshot(sessionID: sessionID, progressMessage: progressMessage, answer: answer)
    }

    private static func streamProgressMessage(from object: [String: Any]) -> String? {
        guard let event = object["event"] as? [String: Any],
              let eventType = event["type"] as? String else {
            return nil
        }

        switch eventType {
        case "message_start":
            return "Claude Code is drafting the answer"
        case "content_block_start":
            return "Claude Code started writing"
        case "tool_use":
            return "Claude Code is using a tool"
        default:
            return nil
        }
    }

    private static func assistantAnswer(from object: [String: Any]) -> String? {
        guard let message = object["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]] else {
            return nil
        }

        return content
            .compactMap { block -> String? in
                guard block["type"] as? String == "text" else { return nil }
                return block["text"] as? String
            }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }
}

struct ClaudeCodeCLIService {
    static func run(
        prompt: String,
        workingDirectory: URL? = nil,
        additionalDirectories: [URL] = [],
        timeout: TimeInterval = 120,
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
        resumeSessionID: String? = nil,
        timeout: TimeInterval = 120,
        progressHandler: @escaping (String) -> Void = { _ in }
    ) async throws -> ClaudeCodeCLIRunResult {
        try await Task.detached(priority: .userInitiated) {
            try runSynchronously(
                prompt: prompt,
                workingDirectory: workingDirectory,
                additionalDirectories: additionalDirectories,
                resumeSessionID: resumeSessionID,
                progressHandler: progressHandler,
                timeout: timeout
            )
        }.value
    }

    private static func runSynchronously(
        prompt: String,
        workingDirectory: URL?,
        additionalDirectories: [URL],
        resumeSessionID: String?,
        progressHandler: @escaping (String) -> Void,
        timeout: TimeInterval
    ) throws -> ClaudeCodeCLIRunResult {
        let accessedFolders = startAccessingSecurityScopedResources(
            for: [workingDirectory].compactMap(\.self) + additionalDirectories
        )
        defer {
            stopAccessingSecurityScopedResources(accessedFolders)
        }

        let configuredCommand = (UserDefaults.standard.string(forKey: AppDefaults.claudeCLIPath) ?? "claude")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? "claude"
        let executable = try executableURL(for: configuredCommand)

        let process = Process()
        process.executableURL = executable
        var arguments = [
            "--permission-mode", "dontAsk",
            "--allowedTools", "Read,Glob,Grep,LS",
            "--verbose",
            "--output-format", "stream-json"
        ]
        if let resumeSessionID {
            arguments += ["--resume", resumeSessionID]
        }
        for directory in additionalDirectories {
            arguments += ["--add-dir", directory.path]
        }
        arguments += ["-p", prompt]
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        process.environment = ProcessInfo.processInfo.environment

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let eventState = ClaudeCodeCLIEventState(progressHandler: progressHandler)
        let stdoutCollector = ClaudeProcessStreamCollector { line in
            eventState.handle(line)
        }
        let stderrCollector = ClaudeProcessStreamCollector()

        stdout.fileHandleForReading.readabilityHandler = { handle in
            stdoutCollector.append(handle.availableData)
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            stderrCollector.append(handle.availableData)
        }

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }

        try process.run()

        guard finished.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            throw ClaudeCodeCLIError.timedOut
        }

        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil
        stdoutCollector.append(stdout.fileHandleForReading.readDataToEndOfFile())
        stderrCollector.append(stderr.fileHandleForReading.readDataToEndOfFile())

        let stdoutText = stdoutCollector.flush()
        let stderrText = stderrCollector.flush()

        guard process.terminationStatus == 0 else {
            let combined = [stdoutText, stderrText]
                .map(stripANSI)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            throw ClaudeCodeCLIError.failed(status: process.terminationStatus, output: combined)
        }

        guard let answer = eventState.answer ?? ClaudeCodeStreamAnswerParser.answer(from: stdoutText) else {
            throw ClaudeCodeCLIError.emptyOutput
        }
        return ClaudeCodeCLIRunResult(answer: answer, sessionID: eventState.sessionID)
    }

    static func resolvedExecutableURL(for command: String) throws -> URL {
        try executableURL(for: command)
    }

    private static func executableURL(for command: String) throws -> URL {
        let expanded = NSString(string: command).expandingTildeInPath
        if expanded.hasPrefix("/") {
            let url = URL(fileURLWithPath: expanded)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }

        for path in candidateExecutablePaths(for: expanded) {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        throw ClaudeCodeCLIError.executableNotFound(command)
    }

    private static func startAccessingSecurityScopedResources(for urls: [URL]) -> [URL] {
        urls.filter { $0.startAccessingSecurityScopedResource() }
    }

    private static func stopAccessingSecurityScopedResources(_ urls: [URL]) {
        urls.forEach { $0.stopAccessingSecurityScopedResource() }
    }

    private static func candidateExecutablePaths(for command: String) -> [String] {
        let name = URL(fileURLWithPath: command).lastPathComponent
        let pathEntries = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
            .map { URL(fileURLWithPath: $0).appendingPathComponent(name).path }

        let home = FileManager.default.homeDirectoryForCurrentUser
        var candidates = pathEntries + [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            home.appendingPathComponent(".local/bin/\(name)").path
        ]

        let nvmRoot = home.appendingPathComponent(".nvm/versions/node")
        if let versions = try? FileManager.default.contentsOfDirectory(at: nvmRoot, includingPropertiesForKeys: nil) {
            candidates += versions
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedDescending }
                .map { $0.appendingPathComponent("bin/\(name)").path }
        }

        return candidates
    }
}

private final class ClaudeCodeCLIEventState {
    private let lock = NSLock()
    private var storedSessionID: String?
    private var storedAnswer: String?
    private var lastProgressMessage = ""
    private let progressHandler: (String) -> Void

    init(progressHandler: @escaping (String) -> Void) {
        self.progressHandler = progressHandler
    }

    var sessionID: String? {
        lock.lock()
        defer { lock.unlock() }
        return storedSessionID
    }

    var answer: String? {
        lock.lock()
        defer { lock.unlock() }
        return storedAnswer
    }

    func handle(_ line: String) {
        guard let snapshot = ClaudeCodeStreamEventParser.snapshot(from: line) else { return }
        if let sessionID = snapshot.sessionID {
            setSessionID(sessionID)
        }
        if let answer = snapshot.answer {
            setAnswer(answer)
        }
        if let progressMessage = snapshot.progressMessage {
            emit(progressMessage)
        }
    }

    private func setSessionID(_ sessionID: String) {
        lock.lock()
        storedSessionID = sessionID
        lock.unlock()
    }

    private func setAnswer(_ answer: String) {
        lock.lock()
        storedAnswer = answer
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

private final class ClaudeProcessStreamCollector {
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

private enum ClaudeCodeStreamAnswerParser {
    static func answer(from stdout: String) -> String? {
        stdout
            .components(separatedBy: .newlines)
            .compactMap { ClaudeCodeStreamEventParser.snapshot(from: $0)?.answer }
            .last?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
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
