import AppKit
import Foundation

@MainActor
final class CodexLoginController: ObservableObject {
    @Published var output = ""
    @Published var status = "Not checked"
    @Published var isSigningIn = false
    @Published var isSignedIn = false
    @Published var authURL: URL?
    @Published var deviceCode = ""

    private var process: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var rawLoginOutput = ""

    func refreshStatus(command: String) {
        Task {
            updateStatus(await statusText(command: command))
        }
    }

    func start(command: String) {
        guard !isSigningIn else { return }

        output = """
        Signing in to OpenAI Codex...
        (Tidy creates its own session — won't affect Codex CLI or VS Code)

        """
        rawLoginOutput = ""
        updateStatus("Waiting for sign-in")
        authURL = nil
        deviceCode = ""
        isSigningIn = true

        do {
            try FileManager.default.createDirectory(
                at: CodexCLIService.codexHomeURL,
                withIntermediateDirectories: true,
                attributes: [
                    .posixPermissions: NSNumber(
                        value: SecureLocalStorage.ownerDirectoryPermissions
                    )
                ]
            )
            SecureLocalStorage.ensureOwnerOnlyDirectory(at: CodexCLIService.codexHomeURL)

            let executable = try CodexCLIService.resolvedExecutableURL(for: command)
            let process = Process()
            process.executableURL = executable
            process.arguments = ["login", "--device-auth"]
            process.environment = CodexCLIService.codexEnvironment(executableURL: executable)

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            self.process = process
            self.outputPipe = outputPipe
            self.errorPipe = errorPipe

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
            updateStatus(error.localizedDescription)
            output += "\n\(error.localizedDescription)"
        }
    }

    func reauthenticate(command: String) {
        guard !isSigningIn else { return }
        isSigningIn = true
        updateStatus("Resetting expired session")
        output = "Signing out of the saved Codex session..."

        Task {
            if let errorMessage = await signOut(command: command) {
                isSigningIn = false
                updateStatus(errorMessage)
                output = errorMessage
                return
            }

            isSigningIn = false
            start(command: command)
        }
    }

    func cancel() {
        process?.terminate()
        cleanupProcess()
        isSigningIn = false
        updateStatus("Sign-in cancelled")
        output += "\nSign-in cancelled."
    }

    func openAuthURL() {
        if let authURL, SecureHTTP.isSafeWebURL(authURL) {
            NSWorkspace.shared.open(authURL)
        }
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

    private func append(_ chunk: String) {
        let cleaned = stripANSI(chunk)
        rawLoginOutput += cleaned
        parseLoginDetails(from: rawLoginOutput)
        output = formattedLoginOutput()
    }

    private func finish(command: String) {
        cleanupProcess()
        isSigningIn = false
        Task {
            updateStatus(await statusText(command: command))
            if isSignedIn {
                output = """
                Signed in to OpenAI Codex for Tidy.
                (Tidy uses its own session — Codex CLI and VS Code are unchanged.)
                """
            }
        }
    }

    private func updateStatus(_ text: String) {
        status = text
        isSignedIn = Self.statusMeansSignedIn(text)
    }

    private func cleanupProcess() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        process = nil
        outputPipe = nil
        errorPipe = nil
    }

    private func parseLoginDetails(from text: String) {
        if authURL == nil,
           let range = text.range(of: #"https?://[^\s\[]+"#, options: .regularExpression) {
            let rawURL = String(text[range]).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            authURL = URL(string: rawURL).flatMap {
                SecureHTTP.isSafeWebURL($0) ? $0 : nil
            }
            if let authURL {
                NSWorkspace.shared.open(authURL)
            }
        }

        if deviceCode.isEmpty,
           let range = text.range(of: #"[A-Z0-9]{4}-[A-Z0-9]{5}"#, options: .regularExpression) {
            deviceCode = String(text[range])
        }
    }

    private func formattedLoginOutput() -> String {
        var text = """
        Signing in to OpenAI Codex...
        (Tidy creates its own session — won't affect Codex CLI or VS Code)

        To continue, follow these steps:

          1. Open this URL in your browser:
        """

        if let authURL {
            text += "\n     \(authURL.absoluteString)"
        } else {
            text += "\n     Waiting for auth URL..."
        }

        text += "\n\n  2. Enter this code -> "
        text += deviceCode.isEmpty ? "Waiting for code..." : deviceCode
        text += "\n\nWaiting for sign-in..."
        return text
    }

    private func statusText(command: String) async -> String {
        await Task.detached {
            do {
                let executable = try CodexCLIService.resolvedExecutableURL(for: command)
                try FileManager.default.createDirectory(
                    at: CodexCLIService.codexHomeURL,
                    withIntermediateDirectories: true,
                    attributes: [
                        .posixPermissions: NSNumber(
                            value: SecureLocalStorage.ownerDirectoryPermissions
                        )
                    ]
                )
                SecureLocalStorage.ensureOwnerOnlyDirectory(at: CodexCLIService.codexHomeURL)

                let process = Process()
                process.executableURL = executable
                process.arguments = ["login", "status"]
                process.environment = CodexCLIService.codexEnvironment(executableURL: executable)

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                try process.run()
                process.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let text = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return text?.isEmpty == false ? stripANSI(text ?? "") : "Not signed in"
            } catch {
                return error.localizedDescription
            }
        }.value
    }

    private func signOut(command: String) async -> String? {
        await Task.detached {
            do {
                let executable = try CodexCLIService.resolvedExecutableURL(for: command)
                let process = Process()
                process.executableURL = executable
                process.arguments = ["logout"]
                process.environment = CodexCLIService.codexEnvironment(executableURL: executable)

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                try process.run()
                process.waitUntilExit()

                guard process.terminationStatus != 0 else { return nil }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let message = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return message?.isEmpty == false ? stripANSI(message ?? "") : "Could not reset the Codex session."
            } catch {
                return error.localizedDescription
            }
        }.value
    }

    nonisolated static func statusMeansSignedIn(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("logged in") || lower.contains("authenticated")
    }
}

private func stripANSI(_ text: String) -> String {
    let withoutEscapedANSI = text.replacingOccurrences(
        of: "\u{001B}\\[[0-9;?]*[ -/]*[@-~]",
        with: "",
        options: .regularExpression
    )
    return withoutEscapedANSI.replacingOccurrences(
        of: #"(?<!\S)\[[0-9;]*[A-Za-z]"#,
        with: "",
        options: .regularExpression
    )
}
