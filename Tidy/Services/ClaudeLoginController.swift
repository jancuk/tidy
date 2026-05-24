import AppKit
import Foundation

@MainActor
final class ClaudeLoginController: ObservableObject {
    @Published var output = ""
    @Published var status = "Not checked"
    @Published var isSigningIn = false
    @Published var awaitingCode = false
    @Published var isLoggedIn = false

    private var process: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var stdinPipe: Pipe?

    func refreshStatus(command: String) {
        Task {
            let text = await statusText(command: command)
            status = text
            isLoggedIn = text.contains("\"loggedIn\": true")
        }
    }

    func start(command: String) {
        guard !isSigningIn else { return }
        output = "Opening browser for Claude sign-in...\n"
        status = "Waiting for sign-in"
        isSigningIn = true

        do {
            let executable = try ClaudeCodeCLIService.resolvedExecutableURL(for: command)
            let process = Process()
            process.executableURL = executable
            process.arguments = ["auth", "login"]
            process.environment = ProcessInfo.processInfo.environment

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            let stdinPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            process.standardInput = stdinPipe
            self.process = process
            self.outputPipe = outputPipe
            self.errorPipe = errorPipe
            self.stdinPipe = stdinPipe

            installReader(for: outputPipe)
            installReader(for: errorPipe)

            process.terminationHandler = { [weak self] _ in
                Task { @MainActor in
                    self?.finish(command: command)
                }
            }

            try process.run()
        } catch {
            isSigningIn = false
            status = error.localizedDescription
            output += "\n\(error.localizedDescription)"
        }
    }

    func cancel() {
        process?.terminate()
        cleanupProcess()
        isSigningIn = false
        status = "Sign-in cancelled"
        output += "\nSign-in cancelled."
    }

    private func installReader(for pipe: Pipe) {
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                self?.append(chunk)
            }
        }
    }

    func submitAuthCode(_ code: String) {
        guard let stdinPipe, !code.isEmpty else { return }
        let line = code + "\n"
        if let data = line.data(using: .utf8) {
            stdinPipe.fileHandleForWriting.write(data)
        }
        awaitingCode = false
    }

    private func append(_ chunk: String) {
        output += stripANSI(chunk)
        if output.contains("Paste code here") || output.contains("paste") && output.contains("code") {
            awaitingCode = true
        }
    }

    private func finish(command: String) {
        cleanupProcess()
        isSigningIn = false
        Task {
            let text = await statusText(command: command)
            status = text
            isLoggedIn = text.contains("\"loggedIn\": true")
        }
    }

    private func cleanupProcess() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        try? stdinPipe?.fileHandleForWriting.close()
        process = nil
        outputPipe = nil
        errorPipe = nil
        stdinPipe = nil
        awaitingCode = false
    }

    private func statusText(command: String) async -> String {
        await Task.detached {
            do {
                let executable = try ClaudeCodeCLIService.resolvedExecutableURL(for: command)
                let process = Process()
                process.executableURL = executable
                process.arguments = ["auth", "status"]
                process.environment = ProcessInfo.processInfo.environment

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                let finished = DispatchSemaphore(value: 0)
                process.terminationHandler = { _ in finished.signal() }

                try process.run()

                guard finished.wait(timeout: .now() + 15) == .success else {
                    process.terminate()
                    return "Status check timed out"
                }

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let text = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return text?.isEmpty == false ? stripANSI(text ?? "") : "Not signed in"
            } catch {
                return error.localizedDescription
            }
        }.value
    }
}

private func stripANSI(_ text: String) -> String {
    text.replacingOccurrences(
        of: "\u{001B}\\[[0-9;?]*[ -/]*[@-~]",
        with: "",
        options: .regularExpression
    )
}
