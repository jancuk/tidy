import AppKit
import SwiftUI

@MainActor
final class HUDController {
    enum State: Equatable {
        case loading(String)
        case success(String)
        case warning(String)
        case error(String)
    }

    private var window: NSWindow?

    func show(_ state: State, autoDismissAfter delay: TimeInterval? = nil) {
        if window == nil {
            let hostingView = NSHostingView(rootView: HUDView(state: state))
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 210, height: 56),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentView = hostingView
            window = panel
        } else if let hostingView = window?.contentView as? NSHostingView<HUDView> {
            hostingView.rootView = HUDView(state: state)
        }

        positionNearMouse()
        window?.orderFrontRegardless()

        if let delay {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                self.dismiss()
            }
        }
    }

    func dismiss() {
        window?.orderOut(nil)
    }

    private func positionNearMouse() {
        guard let window else { return }
        let mouse = NSEvent.mouseLocation
        let frame = NSRect(x: mouse.x + 16, y: mouse.y - 72, width: 210, height: 56)
        window.setFrame(frame, display: true)
    }
}

struct HUDView: View {
    let state: HUDController.State

    var body: some View {
        HStack(spacing: 10) {
            switch state {
            case .loading:
                ProgressView()
                    .controlSize(.small)
            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .warning:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
            case .error:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }

            Text(message)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .frame(width: 210, height: 56, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var message: String {
        switch state {
        case .loading(let message), .success(let message), .warning(let message), .error(let message):
            message
        }
    }
}
