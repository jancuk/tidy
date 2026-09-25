import AppKit
import ApplicationServices
import SwiftUI

@MainActor
final class GoogleMeetMonitor {
    var canSuggest: () -> Bool = { true }
    var onOpenNotetaker: (() -> Void)?
    private var timer: Timer?
    private var panel: NSPanel?
    private var lastSuggested: [String: Date] = [:]
    private let browserIDs: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary", "org.chromium.Chromium",
        "com.apple.Safari", "com.apple.SafariTechnologyPreview", "com.microsoft.edgemac",
        "company.thebrowser.Browser", "company.thebrowser.dia", "com.brave.Browser", "org.mozilla.firefox"
    ]

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func refresh() {
        guard UserDefaults.standard.bool(forKey: AppDefaults.meetingDetectGoogleMeet),
              Permissions.isAccessibilityTrusted, canSuggest(),
              let app = NSWorkspace.shared.frontmostApplication,
              browserIDs.contains(app.bundleIdentifier ?? "") else { panel?.orderOut(nil); return }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.15)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { panel?.orderOut(nil); return }
        let window = unsafeBitCast(value, to: AXUIElement.self)
        func attribute(_ name: String) -> String? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, name as CFString, &value) == .success else { return nil }
            return (value as? String) ?? (value as? URL)?.absoluteString
        }
        guard let code = Self.meetingCode(document: attribute(kAXDocumentAttribute), title: attribute(kAXTitleAttribute)) else {
            panel?.orderOut(nil)
            return
        }
        lastSuggested = lastSuggested.filter { Date().timeIntervalSince($0.value) < 3600 }
        guard lastSuggested[code] == nil else { return }
        lastSuggested[code] = Date()
        showSuggestion(browser: app.localizedName ?? "your browser")
    }

    static func meetingCode(document: String?, title: String?) -> String? {
        let pattern = "^[a-z]{3}-[a-z]{4}-[a-z]{3}$"
        if let document, !document.isEmpty {
            guard let url = URL(string: document), url.scheme == "https", url.host?.lowercased() == "meet.google.com",
                  url.user == nil, url.password == nil, url.port == nil,
                  url.pathComponents.count == 2 else { return nil }
            let code = url.lastPathComponent
            return code.range(of: pattern, options: .regularExpression) != nil ? code : nil
        }
        // A title-only match is a suggestion, never proof that the user has joined a call.
        guard let title, let range = title.range(of: "(?i)^Meet\\s*[-–—]\\s*([a-z]{3}-[a-z]{4}-[a-z]{3})(?=\\s*[-–—]|$)", options: .regularExpression) else { return nil }
        return String(title[range]).suffix(12).lowercased()
    }

    private func showSuggestion(browser: String) {
        panel?.orderOut(nil)
        let view = GoogleMeetSuggestionView(browser: browser, open: { [weak self] in
            self?.panel?.orderOut(nil)
            self?.onOpenNotetaker?()
        }, dismiss: { [weak self] in self?.panel?.orderOut(nil) })
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 150),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: view)
        let screen = NSScreen.main?.visibleFrame ?? .zero
        panel.setFrameOrigin(NSPoint(x: screen.maxX - 380, y: screen.minY + 20))
        self.panel = panel
        panel.orderFrontRegardless()
    }
}

private struct GoogleMeetSuggestionView: View {
    let browser: String
    let open: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Google Meet is open", systemImage: "video").font(.headline)
            Text("Let Tidy take notes for your conversation in \(browser).").font(.callout)
            HStack {
                Button("Not now", action: dismiss)
                Spacer()
                Button("Set up notetaker", action: open).buttonStyle(.borderedProminent)
            }
        }.padding(18).frame(width: 360, height: 150)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
