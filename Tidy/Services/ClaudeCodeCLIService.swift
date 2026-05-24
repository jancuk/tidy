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

struct ClaudeCodeCLIService {
    static func run(
        prompt: String,
        timeout: TimeInterval = 120
    ) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try runSynchronously(prompt: prompt, timeout: timeout)
        }.value
    }

    private static func runSynchronously(prompt: String, timeout: TimeInterval) throws -> String {
        let configuredCommand = (UserDefaults.standard.string(forKey: AppDefaults.claudeCLIPath) ?? "claude")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty ?? "claude"
        let executable = try executableURL(for: configuredCommand)

        let process = Process()
        process.executableURL = executable
        process.arguments = ["-p", prompt]
        process.environment = ProcessInfo.processInfo.environment

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }

        try process.run()

        guard finished.wait(timeout: .now() + timeout) == .success else {
            process.terminate()
            throw ClaudeCodeCLIError.timedOut
        }

        let stdoutText = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            let combined = [stdoutText, stderrText]
                .map(stripANSI)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            throw ClaudeCodeCLIError.failed(status: process.terminationStatus, output: combined)
        }

        let answer = stripANSI(stdoutText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty else { throw ClaudeCodeCLIError.emptyOutput }
        return answer
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
