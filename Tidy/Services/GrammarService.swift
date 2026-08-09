import ApplicationServices
import AppKit
import Carbon

@MainActor
final class GrammarService: ObservableObject {
    private let hud: HUDController
    private let logStore: CorrectionLogStore
    private let requestLogStore: AIRequestLogStore

    init(hud: HUDController, logStore: CorrectionLogStore, requestLogStore: AIRequestLogStore) {
        self.hud = hud
        self.logStore = logStore
        self.requestLogStore = requestLogStore
    }

    func tidySelectedText() {
        guard Permissions.requestAccessibilityIfNeeded() else {
            hud.show(.warning("Allow Accessibility"), autoDismissAfter: 2)
            Permissions.openAccessibilitySettings()
            return
        }

        hud.show(.loading("Tidying..."))

        Task {
            do {
                let selectedText = try await readSelectedText()
                guard !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    hud.show(.warning("Select text first"), autoDismissAfter: 1.2)
                    return
                }

                if selectedText.count > 2_000 {
                    hud.show(.warning("Selection is too long"), autoDismissAfter: 1.5)
                    return
                }

                let providerID = currentProviderID()
                try AppPrivacyPolicy.validateAIProvider(providerID)
                let provider = GrammarProviderFactory.provider(for: providerID)
                let start = Date()
                do {
                    let corrected = try await provider.fixGrammar(selectedText, language: nil)
                    let ms = Int(Date().timeIntervalSince(start) * 1000)
                    let hudHandled = try await replaceSelection(with: corrected)
                    logStore.append(original: selectedText, corrected: corrected, providerID: providerID.rawValue)
                    requestLogStore.append(AIRequestLogEntry(
                        providerName: provider.displayName,
                        requestPreview: String(selectedText.prefix(100)),
                        durationMs: ms,
                        source: "grammar"
                    ))
                    if !hudHandled {
                        hud.show(.success("Tidied"), autoDismissAfter: 0.8)
                    }
                } catch {
                    let ms = Int(Date().timeIntervalSince(start) * 1000)
                    requestLogStore.append(AIRequestLogEntry(
                        providerName: provider.displayName,
                        requestPreview: String(selectedText.prefix(100)),
                        statusCode: httpStatus(from: error),
                        errorMessage: error.localizedDescription,
                        durationMs: ms,
                        source: "grammar"
                    ))
                    throw error
                }
            } catch {
                hud.show(.error(error.localizedDescription), autoDismissAfter: 2.5)
            }
        }
    }

    private func httpStatus(from error: Error) -> Int? {
        if case GrammarProviderError.httpError(let status, _) = error { return status }
        return nil
    }

    private func currentProviderID() -> GrammarProviderID {
        let rawValue = UserDefaults.standard.string(forKey: AppDefaults.grammarProvider) ?? GrammarProviderID.gemini.rawValue
        return GrammarProviderID(rawValue: rawValue) ?? .gemini
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
