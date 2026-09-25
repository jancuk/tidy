import Foundation

enum CodexTextRunner {
    static func arguments(output: URL, directory: URL, model: String, fastResponse: Bool = false) -> [String] {
        var arguments = ["exec", "--ignore-user-config", "--ignore-rules", "--ephemeral", "--skip-git-repo-check",
                         "--sandbox", "read-only", "--color", "never", "--cd", directory.path,
                         "--output-last-message", output.path,
                         "-c", "approval_policy=\"never\"", "-c", "web_search=\"disabled\"", "-c", "project_doc_max_bytes=0"]
        for feature in ["shell_tool", "unified_exec", "apps", "plugins", "hooks", "multi_agent", "browser_use",
                        "computer_use", "in_app_browser", "code_mode", "code_mode_host", "image_generation", "view_image", "memories", "skill_search"] {
            arguments += ["--disable", feature]
        }
        if fastResponse { arguments += ["-c", "model_reasoning_effort=\"low\""] }
        if !model.isEmpty { arguments += ["--model", model] }
        return arguments + ["-"]
    }

    static func run(_ prompt: String, model: String? = nil, fastResponse: Bool = false) async throws -> String {
        let command = UserDefaults.standard.string(forKey: AppDefaults.codexCLIPath) ?? "codex"
        let executable = try CodexCLIService.resolvedExecutableURL(for: command)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TidyTextRequest-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: folder) }
        let input = folder.appendingPathComponent("input.txt")
        let output = folder.appendingPathComponent("result.txt")
        let log = folder.appendingPathComponent("process.log")
        try Data(prompt.utf8).write(to: input)
        SecureLocalStorage.protectFile(at: input)
        FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let inputHandle = try FileHandle(forReadingFrom: input)
        let logHandle = try FileHandle(forWritingTo: log)
        defer { try? inputHandle.close(); try? logHandle.close() }
        let process = Process()
        process.executableURL = executable
        process.currentDirectoryURL = folder
        process.environment = CodexCLIService.codexEnvironment(executableURL: executable)
        process.arguments = arguments(output: output, directory: folder,
                                      model: model ?? (UserDefaults.standard.string(forKey: AppDefaults.codexCLIModel) ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                                      fastResponse: fastResponse)
        process.standardInput = inputHandle
        process.standardOutput = logHandle
        process.standardError = logHandle
        try Task.checkCancellation()
        try process.run()
        do {
            let deadline = Date().addingTimeInterval(180)
            while process.isRunning {
                try Task.checkCancellation()
                guard Date() < deadline else { throw CodexCLIError.timedOut }
                try await Task.sleep(for: .milliseconds(100))
            }
        } catch {
            if process.isRunning {
                process.terminate()
                await Task.detached {
                    try? await Task.sleep(for: .milliseconds(250))
                    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                    // Keep private working files until the child has stopped using them.
                    process.waitUntilExit()
                }.value
            }
            throw error
        }
        guard process.terminationStatus == 0 else {
            throw MeetingError.message("Codex could not complete this text request. Check that the selected model is available to your Codex account and that you are signed in through Settings → Model. A current Codex CLI supporting ephemeral runs and --ignore-user-config is required. Your original content is unchanged.")
        }
        let text = try String(contentsOf: output, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw CodexCLIError.emptyOutput }
        return text
    }
}
