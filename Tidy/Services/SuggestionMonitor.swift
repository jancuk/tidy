import ApplicationServices
import AppKit
import Combine

@MainActor
final class SuggestionMonitor: ObservableObject {
    struct Suggestion {
        let original: String
        let corrected: String
        let anchorRect: CGRect?
    }

    @Published var enabled: Bool = UserDefaults.standard.bool(forKey: AppDefaults.autoSuggestEnabled)

    var onSuggestion: ((Suggestion) -> Void)?
    var onDismiss: (() -> Void)?

    private var pollTimer: Timer?
    private var lastSeenText: String = ""
    private var lastChangeAt: Date = .distantPast
    private var lastCheckedText: String = ""
    private var lastDismissedText: String = ""
    private var inflight: Bool = false
    private let idleThreshold: TimeInterval = 2.5
    private let minLength: Int = 12
    private let maxLength: Int = 800

    private let deniedBundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "com.1password.1password",
        "com.1password.1password7",
        "com.bitwarden.desktop",
        "com.microsoft.VSCode",
        "com.apple.dt.Xcode",
        "company.thebrowser.Browser"
    ]

    func start() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        pollTimer?.tolerance = 0.2

        NotificationCenter.default.addObserver(self, selector: #selector(reloadEnabled), name: UserDefaults.didChangeNotification, object: nil)
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    @objc private func reloadEnabled() {
        let newValue = UserDefaults.standard.bool(forKey: AppDefaults.autoSuggestEnabled)
        if newValue != enabled {
            enabled = newValue
            if !enabled {
                onDismiss?()
            }
        }
    }

    func noteDismissed(text: String) {
        lastDismissedText = text
        onDismiss?()
    }

    func noteAccepted() {
        onDismiss?()
    }

    private func tick() {
        guard enabled, !inflight else { return }
        guard Permissions.isAccessibilityTrusted else { return }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier,
              !(app.bundleIdentifier.map { deniedBundleIDs.contains($0) } ?? false) else {
            return
        }

        guard let (text, rect) = readFocusedText() else {
            // Lost focus -> dismiss any open suggestion
            if !lastSeenText.isEmpty {
                lastSeenText = ""
                onDismiss?()
            }
            return
        }

        // Text changed -> reset idle timer
        if text != lastSeenText {
            lastSeenText = text
            lastChangeAt = Date()
            return
        }

        // Skip if too short, too long, or already checked/dismissed
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minLength, trimmed.count <= maxLength else { return }
        guard text != lastCheckedText, text != lastDismissedText else { return }
        guard Date().timeIntervalSince(lastChangeAt) >= idleThreshold else { return }

        lastCheckedText = text
        runCheck(text: text, anchorRect: rect)
    }

    private func runCheck(text: String, anchorRect: CGRect?) {
        inflight = true
        Task {
            defer { inflight = false }
            do {
                let providerID = currentProviderID()
                try AppPrivacyPolicy.validateAIProvider(providerID)
                let provider = GrammarProviderFactory.provider(for: providerID)
                let corrected = try await provider.fixGrammar(text, language: nil)
                let cleanedCorrected = corrected.trimmingCharacters(in: .whitespacesAndNewlines)
                let cleanedOriginal = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleanedCorrected.isEmpty, cleanedCorrected != cleanedOriginal else { return }

                // Sanity check: reject if the model returned something wildly different
                // (e.g. answered the text instead of correcting it)
                guard isPlausibleCorrection(original: cleanedOriginal, corrected: cleanedCorrected) else {
                    return
                }

                // Only emit if the focused field still has this text
                if let (current, currentRect) = readFocusedText(), current == text {
                    onSuggestion?(Suggestion(original: text, corrected: corrected, anchorRect: currentRect ?? anchorRect))
                }
            } catch {
                // Silent fail for auto-mode
            }
        }
    }

    /// Reject corrections that look like the model answered the text instead of correcting it.
    /// Heuristic: corrected length must be within 0.4x..2.5x of original, OR length difference < 30 chars.
    private func isPlausibleCorrection(original: String, corrected: String) -> Bool {
        let origLen = original.count
        let newLen = corrected.count
        if abs(newLen - origLen) < 30 { return true }
        let ratio = Double(newLen) / Double(max(origLen, 1))
        return ratio >= 0.4 && ratio <= 2.5
    }

    private func currentProviderID() -> GrammarProviderID {
        let raw = UserDefaults.standard.string(forKey: AppDefaults.grammarProvider) ?? GrammarProviderID.gemini.rawValue
        return GrammarProviderID(rawValue: raw) ?? .gemini
    }

    private func readFocusedText() -> (String, CGRect?)? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        var focusedObject: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedObject) == .success,
              let focusedObject else { return nil }
        let focused = focusedObject as! AXUIElement

        // Read value
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused, kAXValueAttribute as CFString, &valueRef) == .success,
              let text = valueRef as? String else { return nil }

        // Position
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        var rect: CGRect?
        if AXUIElementCopyAttributeValue(focused, kAXPositionAttribute as CFString, &posRef) == .success,
           AXUIElementCopyAttributeValue(focused, kAXSizeAttribute as CFString, &sizeRef) == .success,
           let posValue = posRef, let sizeValue = sizeRef {
            var origin = CGPoint.zero
            var size = CGSize.zero
            AXValueGetValue(posValue as! AXValue, .cgPoint, &origin)
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
            rect = CGRect(origin: origin, size: size)
        }

        return (text, rect)
    }

    /// Set the entire value of the focused element. Falls back to select-all + paste.
    func applyReplacement(_ newText: String) {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var focusedObject: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedObject) == .success,
              let focusedObject else {
            fallbackReplace(newText)
            return
        }
        let focused = focusedObject as! AXUIElement
        let status = AXUIElementSetAttributeValue(focused, kAXValueAttribute as CFString, newText as CFString)
        if status != .success {
            fallbackReplace(newText)
        }
        lastSeenText = newText
        lastCheckedText = newText
    }

    private func fallbackReplace(_ newText: String) {
        let snapshot = PasteboardSnapshot()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(newText, forType: .string)
        KeyboardSimulator.selectAll()
        KeyboardSimulator.paste()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(200))
            snapshot.restore()
        }
    }
}
