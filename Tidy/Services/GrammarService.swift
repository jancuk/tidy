import ApplicationServices
import AppKit
import Carbon

@MainActor
final class GrammarService: ObservableObject {
    private let hud: HUDController
    private let logStore: CorrectionLogStore
    private let requestLogStore: AIRequestLogStore
    private var activeCorrectionTask: Task<Void, Never>?

    init(hud: HUDController, logStore: CorrectionLogStore, requestLogStore: AIRequestLogStore) {
        self.hud = hud
        self.logStore = logStore
        self.requestLogStore = requestLogStore
    }

    func tidySelectedText() {
        guard activeCorrectionTask == nil else {
            hud.show(.loading("Already tidying—your text is safe"))
            return
        }

        guard Permissions.requestAccessibilityIfNeeded() else {
            hud.show(.warning("Allow Accessibility"), autoDismissAfter: 2)
            Permissions.openAccessibilitySettings()
            return
        }

        hud.show(.loading("Reading your selection…"))

        activeCorrectionTask = Task {
            defer { activeCorrectionTask = nil }

            do {
                let selectedText = try await readSelectedText()
                guard !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    hud.show(.warning("Select text first"), autoDismissAfter: 1.2)
                    return
                }

                if selectedText.count > GrammarCorrectionPipeline.maximumInputCharacters {
                    hud.show(.warning("Select up to 100,000 characters"), autoDismissAfter: 2)
                    return
                }

                let providerIDs = GrammarCorrectionPipeline.configuredProviderIDs()
                guard let primaryID = providerIDs.first else {
                    throw AppPrivacyError.localOnlyProviderRequired
                }
                let primaryProvider = GrammarProviderFactory.provider(for: primaryID)
                let chunkCount = GrammarCorrectionPipeline.estimatedChunkCount(for: selectedText)
                let loadingMessage = chunkCount > 1
                    ? "Tidying \(chunkCount) sections with \(primaryProvider.displayName)…"
                    : "Tidying with \(primaryProvider.displayName)…"
                hud.show(.loading(loadingMessage))

                let progressTask = Task { @MainActor [hud] in
                    try? await Task.sleep(for: .seconds(4))
                    guard !Task.isCancelled else { return }
                    hud.show(.loading("Still working—your text is safe"))
                }
                let start = Date()
                do {
                    let result = try await GrammarCorrectionPipeline.correct(selectedText, providerIDs: providerIDs)
                    progressTask.cancel()
                    let ms = Int(Date().timeIntervalSince(start) * 1000)
                    logFailures(result.failures, requestPreview: selectedText)
                    logStore.append(original: selectedText, corrected: result.correctedText, providerID: result.providerID)
                    requestLogStore.append(AIRequestLogEntry(
                        providerName: result.providerName,
                        requestPreview: String(selectedText.prefix(100)),
                        durationMs: ms,
                        source: "grammar"
                    ))

                    if result.correctedText == selectedText {
                        let message = result.usedFallback ? "Already tidy · \(result.providerName) fallback" : "Already tidy"
                        hud.show(.success(message), autoDismissAfter: 1.4)
                        return
                    }

                    let hudHandled = try await replaceSelection(with: result.correctedText)
                    if !hudHandled {
                        let suffix = result.usedFallback ? " · \(result.providerName) fallback" : ""
                        hud.show(.success("Tidied in \(Self.durationDescription(milliseconds: ms))\(suffix)"), autoDismissAfter: 1.8)
                    }
                } catch {
                    progressTask.cancel()
                    let ms = Int(Date().timeIntervalSince(start) * 1000)
                    if case GrammarCorrectionPipelineError.allProvidersFailed(let failures) = error {
                        logFailures(failures, requestPreview: selectedText)
                    } else {
                        requestLogStore.append(AIRequestLogEntry(
                            providerName: primaryProvider.displayName,
                            requestPreview: String(selectedText.prefix(100)),
                            statusCode: httpStatus(from: error),
                            errorMessage: error.localizedDescription,
                            durationMs: ms,
                            source: "grammar"
                        ))
                    }
                    throw error
                }
            } catch {
                hud.show(.error(Self.userFacingMessage(for: error)), autoDismissAfter: 4)
            }
        }
    }

    nonisolated static func durationDescription(milliseconds: Int) -> String {
        if milliseconds < 1_000 { return "<1s" }
        let seconds = Double(milliseconds) / 1_000
        return seconds < 10 ? String(format: "%.1fs", seconds) : "\(Int(seconds.rounded()))s"
    }

    nonisolated static func userFacingMessage(for error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return "This is taking longer than usual. Your text is unchanged—please try again."
            case .notConnectedToInternet, .networkConnectionLost:
                return "You're offline. Your text is unchanged—check your connection and try again."
            case .cancelled:
                return "Tidying was cancelled. Your text is unchanged."
            default:
                break
            }
        }
        return error.localizedDescription
    }

    private func httpStatus(from error: Error) -> Int? {
        if case GrammarProviderError.httpError(let status, _) = error { return status }
        return nil
    }

    private func logFailures(_ failures: [GrammarProviderAttemptFailure], requestPreview: String) {
        for failure in failures {
            requestLogStore.append(AIRequestLogEntry(
                providerName: failure.providerName,
                requestPreview: String(requestPreview.prefix(100)),
                statusCode: failure.statusCode,
                errorMessage: failure.message,
                durationMs: failure.durationMs,
                source: "grammar-fallback"
            ))
        }
    }

    // Bundle IDs of terminal emulators that don't support "replace selected text" via Cmd+V.
    private static let terminalBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "io.alacritty",
        "com.github.wez.wezterm",
        "net.kovidgoyal.kitty",
        "co.zeit.hyper",
    ]

    private func frontmostAppIsTerminal() -> Bool {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        return Self.terminalBundleIDs.contains(bundleID)
    }

    private func readSelectedText() async throws -> String {
        if let selectedText = readSelectedTextWithAccessibility() {
            return selectedText
        }
        return try await readSelectedTextViaCopyFallback()
    }

    private func readSelectedTextWithAccessibility() -> String? {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)
        var focusedObject: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedObject) == .success,
              let focusedObject else {
            return nil
        }

        var selectedText: CFTypeRef?
        let focusedElement = focusedObject as! AXUIElement
        guard AXUIElementCopyAttributeValue(focusedElement, kAXSelectedTextAttribute as CFString, &selectedText) == .success else {
            return nil
        }
        return selectedText as? String
    }

    private func readSelectedTextViaCopyFallback() async throws -> String {
        let snapshot = PasteboardSnapshot()
        NSPasteboard.general.clearContents()
        KeyboardSimulator.copy()
        try await Task.sleep(for: .milliseconds(120))
        let copiedText = NSPasteboard.general.string(forType: .string) ?? ""
        snapshot.restore()
        return copiedText
    }

    /// Returns `true` if it already showed the success HUD (terminal mode), `false` if the caller should.
    @discardableResult
    private func replaceSelection(with correctedText: String) async throws -> Bool {
        if frontmostAppIsTerminal() {
            // Terminals don't support replace-selection via Cmd+V — leave the
            // corrected text in the clipboard so the user can paste manually.
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(correctedText, forType: .string)
            hud.show(.success("Corrected · ⌘V to paste"), autoDismissAfter: 3)
            return true
        }
        let snapshot = PasteboardSnapshot()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(correctedText, forType: .string)
        KeyboardSimulator.paste()
        try await Task.sleep(for: .milliseconds(200))
        snapshot.restore()
        return false
    }
}
