import AppKit
import SwiftUI

@MainActor
final class SuggestionPopupController {
    private var window: NSPanel?
    private var hostingView: NSHostingView<SuggestionPopupView>?

    var onAccept: ((String) -> Void)?
    var onDismiss: ((String) -> Void)?

    func show(original: String, corrected: String, anchorRect: CGRect?) {
        let view = SuggestionPopupView(
            original: original,
            corrected: corrected,
            onAccept: { [weak self] in
                self?.onAccept?(corrected)
                self?.dismiss()
            },
            onDismiss: { [weak self] in
                self?.onDismiss?(original)
                self?.dismiss()
            }
        )

        if window == nil {
            let host = NSHostingView(rootView: view)
            host.frame = NSRect(x: 0, y: 0, width: 360, height: 160)
            let panel = NSPanel(
                contentRect: host.frame,
                styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentView = host
            window = panel
            hostingView = host
        } else {
            hostingView?.rootView = view
        }

        positionNear(anchorRect: anchorRect)
        window?.orderFrontRegardless()
    }

    func dismiss() {
        window?.orderOut(nil)
    }

    private func positionNear(anchorRect: CGRect?) {
        guard let window else { return }
        let popupSize = CGSize(width: 360, height: 160)
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero

        if let anchorRect, anchorRect.width > 0, anchorRect.height > 0 {
            // AX coordinates: y is from top of screen. Convert to AppKit (y from bottom).
            let screenHeight = NSScreen.screens.first?.frame.height ?? 0
            let appkitY = screenHeight - anchorRect.origin.y - anchorRect.size.height
            var x = anchorRect.origin.x
            var y = appkitY - popupSize.height - 8

            // Keep on-screen
            if x + popupSize.width > screenFrame.maxX { x = screenFrame.maxX - popupSize.width - 8 }
            if x < screenFrame.minX { x = screenFrame.minX + 8 }
            if y < screenFrame.minY {
                // Flip below the field
                y = screenHeight - anchorRect.origin.y + 8
            }

            window.setFrame(NSRect(origin: CGPoint(x: x, y: y), size: popupSize), display: true)
        } else {
            // Fallback: near mouse
            let mouse = NSEvent.mouseLocation
            let frame = NSRect(x: mouse.x + 12, y: mouse.y - popupSize.height - 12, width: popupSize.width, height: popupSize.height)
            window.setFrame(frame, display: true)
        }
    }
}

struct SuggestionPopupView: View {
    let original: String
    let corrected: String
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.tint)
                Text("Tidy suggestion")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(corrected)
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxHeight: 80)

            HStack {
                Spacer()
                Button("Dismiss") {
                    onDismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button {
                    onAccept()
                } label: {
                    Label("Apply", systemImage: "checkmark")
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .frame(width: 360, height: 160)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.separator, lineWidth: 0.5)
        )
    }
}
