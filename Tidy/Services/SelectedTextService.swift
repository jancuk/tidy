import AppKit
import ApplicationServices

@MainActor
final class SelectedTextService {
    struct Selection {
        let text: String
        let source: CaptureSource
        let app: NSRunningApplication
        let element: AXUIElement?
        let range: CFRange?
        let document: String?
    }

    struct Replacement {
        let selection: Selection
        let text: String
        let expectedDocument: String
    }

    private var isCapturing = false
    private let clipboard: ClipboardService
    private(set) var replacement: Replacement?

    init(clipboard: ClipboardService) { self.clipboard = clipboard }

    func capture() async throws -> Selection {
        guard !isCapturing else { throw TextActionError.invalid("A selection is already being read. Please try again.") }
        isCapturing = true
        defer { isCapturing = false }
        guard Permissions.requestAccessibilityIfNeeded() else {
            throw TextActionError.invalid("Allow Accessibility in System Settings to read selected text.")
        }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            throw TextActionError.invalid("Select text in another app, then press the text actions shortcut.")
        }
        let element = focusedElement(in: app)
        if let element, stringAttribute(element, kAXSubroleAttribute) == "AXSecureTextField" {
            throw TextActionError.invalid("Password fields cannot be captured.")
        }
        let document = element.flatMap { stringAttribute($0, kAXValueAttribute) }
        let range = element.flatMap(selectedRange)
        let selected = element.flatMap { stringAttribute($0, kAXSelectedTextAttribute) }
        let text: String
        if let selected, !selected.isEmpty { text = selected }
        else {
            clipboard.suspendCapture()
            let snapshot = PasteboardSnapshot()
            NSPasteboard.general.clearContents()
            let changeCount = NSPasteboard.general.changeCount
            defer {
                snapshot.restore()
                clipboard.resumeCapture()
            }
            KeyboardSimulator.copy()
            for _ in 0..<10 {
                try await Task.sleep(for: .milliseconds(40))
                if NSPasteboard.general.changeCount != changeCount { break }
            }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else {
                throw TextActionError.invalid("The active app changed. Select your text and try again.")
            }
            guard !(NSPasteboard.general.types ?? []).contains(NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")) else {
                throw TextActionError.invalid("Concealed clipboard content cannot be captured.")
            }
            text = NSPasteboard.general.string(forType: .string) ?? ""
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TextActionError.invalid("Select some text first.")
        }
        guard text.count <= 100_000 else { throw TextActionError.invalid("Select up to 100,000 characters.") }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        let window = attribute(appElement, kAXFocusedWindowAttribute).flatMap(asElement)
        let sourceURL = element.flatMap { stringAttribute($0, kAXDocumentAttribute) }
            ?? window.flatMap { stringAttribute($0, kAXDocumentAttribute) }
        return Selection(text: text, source: CaptureSource(appName: app.localizedName, bundleID: app.bundleIdentifier,
                                                         url: CaptureSource.safeURL(sourceURL)),
                         app: app, element: element, range: range, document: document)
    }

    func canReplace(_ selection: Selection) -> Bool {
        guard !Self.terminalIDs.contains(selection.app.bundleIdentifier ?? ""),
              let element = selection.element, let range = selection.range,
              let document = selection.document,
              Self.substring(document, range: range) == selection.text else { return false }
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success && settable.boolValue
    }

    func replace(_ selection: Selection, with text: String) async throws {
        guard canReplace(selection), let element = selection.element,
              let range = selection.range, let document = selection.document else {
            throw TextActionError.invalid("This app cannot safely replace selected text. Use Copy and paste it manually.")
        }
        selection.app.activate(options: [])
        try await Task.sleep(for: .milliseconds(160))
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == selection.app.processIdentifier,
              let focused = focusedElement(in: selection.app), CFEqual(focused, element),
              stringAttribute(element, kAXValueAttribute) == document,
              sameRange(selectedRange(element), range),
              stringAttribute(element, kAXSelectedTextAttribute) == selection.text else {
            throw TextActionError.invalid("The original selection changed. Your text was not replaced; copy the result instead.")
        }
        guard AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString) == .success else {
            throw TextActionError.invalid("The app refused replacement. Copy the result instead.")
        }
        let expected = (document as NSString).replacingCharacters(in: NSRange(location: range.location, length: range.length), with: text)
        replacement = Replacement(selection: selection, text: text, expectedDocument: expected)
    }

    func restoreOriginal() async throws {
        guard let replacement, let element = replacement.selection.element,
              let range = replacement.selection.range else { return }
        let app = replacement.selection.app
        app.activate(options: [])
        try await Task.sleep(for: .milliseconds(160))
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
              let focused = focusedElement(in: app), CFEqual(focused, element),
              stringAttribute(element, kAXValueAttribute) == replacement.expectedDocument else {
            throw TextActionError.invalid("The document changed since replacement. Use Copy original to recover it without overwriting newer edits.")
        }
        let priorRange = selectedRange(element)
        var replacedRange = CFRange(location: range.location, length: (replacement.text as NSString).length)
        guard let value = AXValueCreate(.cfRange, &replacedRange),
              AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value) == .success else {
            throw TextActionError.invalid("Could not select the replacement. Use Copy original.")
        }
        guard AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, replacement.selection.text as CFString) == .success else {
            if var priorRange, let value = AXValueCreate(.cfRange, &priorRange) {
                AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value)
            }
            throw TextActionError.invalid("The app refused to restore the text. Use Copy original.")
        }
        self.replacement = nil
    }

    nonisolated static func substring(_ text: String, range: CFRange) -> String? {
        let value = text as NSString
        guard range.location >= 0, range.length >= 0, range.location <= value.length,
              range.length <= value.length - range.location else { return nil }
        return value.substring(with: NSRange(location: range.location, length: range.length))
    }

    private func focusedElement(in app: NSRunningApplication) -> AXUIElement? {
        attribute(AXUIElementCreateApplication(app.processIdentifier), kAXFocusedUIElementAttribute).flatMap(asElement)
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private func asElement(_ value: CFTypeRef) -> AXUIElement? {
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func stringAttribute(_ element: AXUIElement, _ name: String) -> String? { attribute(element, name) as? String }

    private func selectedRange(_ element: AXUIElement) -> CFRange? {
        guard let value = attribute(element, kAXSelectedTextRangeAttribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cfRange else { return nil }
        var range = CFRange()
        return AXValueGetValue(axValue, .cfRange, &range) ? range : nil
    }

    private func sameRange(_ lhs: CFRange?, _ rhs: CFRange) -> Bool { lhs?.location == rhs.location && lhs?.length == rhs.length }

    private static let terminalIDs: Set<String> = ["com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "io.alacritty", "com.github.wez.wezterm", "net.kovidgoyal.kitty", "co.zeit.hyper"]
}
