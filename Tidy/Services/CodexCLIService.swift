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
        timeout: TimeInterval = 180
    ) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try runSynchronously(
                prompt: prompt,
                workingDirectory: workingDirectory,
                additionalDirectories: additionalDirectories,
                timeout: timeout
            )
        }.value
    }

    private static func runSynchronously(
        prompt: String,
        workingDirectory: URL?,
        additionalDirectories: [URL],
        timeout: TimeInterval
    ) throws -> String {
        let configuredCommand = (UserDefaults.standard.string(forKey: AppDefaults.codexCLIPath) ?? "codex")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? "codex"
        let executable = try executableURL(for: configuredCommand)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tidy-codex-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        var arguments = [
            "exec",
            "--color", "never",
            "--skip-git-repo-check",
            "--sandbox", "read-only",
            "--output-last-message", outputURL.path
        ]

        let model = (UserDefaults.standard.string(forKey: AppDefaults.codexCLIModel) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !model.isEmpty {
            arguments += ["--model", model]
        }

        if let workingDirectory {
            arguments += ["--cd", workingDirectory.path]
        }

        for directory in additionalDirectories {
            arguments += ["--add-dir", directory.path]
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

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }

        try process.run()

        if let data = prompt.data(using: .utf8) {
            stdin.fileHandleForWriting.write(data)
        }
        try? stdin.fileHandleForWriting.close()

        guard finished.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            throw CodexCLIError.timedOut
        }

        let stdoutText = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
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
        let fallbackAnswer = stripANSI(stdoutText)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty

        guard let answer = finalAnswer ?? fallbackAnswer else {
            throw CodexCLIError.emptyOutput
        }

        return answer
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
