import ApplicationServices
import AppKit
import Carbon

@MainActor
final class GrammarService: ObservableObject {
    private let hud: HUDController
    private let logStore: CorrectionLogStore

    init(hud: HUDController, logStore: CorrectionLogStore) {
        self.hud = hud
        self.logStore = logStore
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
                let provider = GrammarProviderFactory.provider(for: providerID)
                let corrected = try await provider.fixGrammar(selectedText, language: nil)
                try await replaceSelection(with: corrected)
                logStore.append(original: selectedText, corrected: corrected, providerID: providerID.rawValue)
                hud.show(.success("Tidied"), autoDismissAfter: 0.8)
            } catch {
                hud.show(.error(error.localizedDescription), autoDismissAfter: 2.5)
            }
        }
    }

    private func currentProviderID() -> GrammarProviderID {
        let rawValue = UserDefaults.standard.string(forKey: AppDefaults.grammarProvider) ?? GrammarProviderID.gemini.rawValue
        return GrammarProviderID(rawValue: rawValue) ?? .gemini
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

    private func replaceSelection(with correctedText: String) async throws {
        let snapshot = PasteboardSnapshot()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(correctedText, forType: .string)
        KeyboardSimulator.paste()
        try await Task.sleep(for: .milliseconds(200))
        snapshot.restore()
    }
}
