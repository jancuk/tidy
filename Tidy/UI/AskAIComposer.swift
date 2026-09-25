import AppKit
import SwiftUI

struct AskAIComposer: NSViewRepresentable {
    @Binding var text: String
    let focusRequest: UUID
    let submit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let editor = ComposerTextView()
        editor.isRichText = false
        editor.drawsBackground = false
        editor.font = .systemFont(ofSize: 15)
        editor.textColor = .labelColor
        editor.textContainerInset = NSSize(width: 4, height: 8)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.heightTracksTextView = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isAutomaticLinkDetectionEnabled = false
        editor.setAccessibilityLabel("Message Ask AI")
        editor.setAccessibilityIdentifier("ask-ai-composer")
        editor.delegate = context.coordinator
        editor.submit = submit
        scroll.documentView = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? ComposerTextView else { return }
        if editor.string != text { editor.string = text }
        editor.submit = submit
        if context.coordinator.focusRequest != focusRequest {
            context.coordinator.focusRequest = focusRequest
            DispatchQueue.main.async { [weak editor] in
                guard let editor, editor.window?.isKeyWindow == true else { return }
                editor.window?.makeFirstResponder(editor)
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> NSSize? {
        guard let width = proposal.width, let editor = nsView.documentView as? NSTextView,
              let container = editor.textContainer, let layout = editor.layoutManager else { return nil }
        container.containerSize = NSSize(width: max(40, width - 20), height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        return NSSize(width: width, height: min(160, max(56, layout.usedRect(for: container).height + 20)))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AskAIComposer
        var focusRequest: UUID?
        init(_ parent: AskAIComposer) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            if let editor = notification.object as? NSTextView { parent.text = editor.string }
        }
    }
}

private final class ComposerTextView: NSTextView {
    var submit: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if [UInt16(36), 76].contains(event.keyCode), !hasMarkedText(),
           !event.modifierFlags.contains(.shift), !event.modifierFlags.contains(.option) {
            submit?()
        } else { super.keyDown(with: event) }
    }
}
