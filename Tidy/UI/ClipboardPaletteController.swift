import AppKit
import Carbon
import SwiftUI

@MainActor
final class PaletteSelectionState: ObservableObject {
    @Published var selectedIndex: Int = 0
}

@MainActor
final class ClipboardPaletteController {
    private let clipboardService: ClipboardService
    private let selectionState = PaletteSelectionState()
    private var panel: NSPanel?
    private var eventMonitor: Any?
    private weak var previouslyFocusedApp: NSRunningApplication?

    private var selectedIndex: Int {
        get { selectionState.selectedIndex }
        set { selectionState.selectedIndex = newValue }
    }

    init(clipboardService: ClipboardService) {
        self.clipboardService = clipboardService
    }

    func toggle() {
        if panel?.isVisible == true {
            hide()
        } else {
            show()
        }
    }

    func show() {
        previouslyFocusedApp = NSWorkspace.shared.frontmostApplication
        selectedIndex = 0
        clipboardService.query = ""
        clipboardService.reload()

        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
                styleMask: [.titled, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isMovableByWindowBackground = true
            panel.isReleasedWhenClosed = false
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.backgroundColor = .clear
            panel.isOpaque = false

            let rootView = ClipboardPaletteView(
                clipboardService: clipboardService,
                selectionState: selectionState,
                paste: { [weak self] in self?.pasteSelected() },
                copy: { [weak self] in self?.copySelected() },
                delete: { [weak self] in self?.deleteSelected() },
                hide: { [weak self] in self?.hide() }
            )
            panel.contentView = NSHostingView(rootView: rootView)
            self.panel = panel
        }

        centerPanel()
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate()
        installEventMonitor()
    }

    func hide() {
        panel?.orderOut(nil)
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    private func pasteSelected() {
        guard let entry = selectedEntry else { return }
        hide()
        previouslyFocusedApp?.activate(options: [])
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.content, forType: .string)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            KeyboardSimulator.paste()
        }
    }

    private func copySelected() {
        guard let entry = selectedEntry else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.content, forType: .string)
    }

    private func deleteSelected() {
        guard let entry = selectedEntry else { return }
        clipboardService.delete(entry)
        selectedIndex = min(selectedIndex, max(clipboardService.entries.count - 1, 0))
    }

    private var selectedEntry: ClipboardEntry? {
        guard clipboardService.entries.indices.contains(selectedIndex) else { return nil }
        return clipboardService.entries[selectedIndex]
    }

    private func centerPanel() {
        guard let panel, let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        let origin = NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2)
        panel.setFrameOrigin(origin)
    }

    private func installEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel?.isKeyWindow == true else { return event }
            let commandPressed = event.modifierFlags.contains(.command)

            switch Int(event.keyCode) {
            case kVK_Escape:
                self.hide()
                return nil
            case kVK_DownArrow:
                self.selectedIndex = min(self.selectedIndex + 1, max(self.clipboardService.entries.count - 1, 0))
                return nil
            case kVK_UpArrow:
                self.selectedIndex = max(self.selectedIndex - 1, 0)
                return nil
            case kVK_Return, kVK_ANSI_KeypadEnter:
                self.pasteSelected()
                return nil
            case kVK_ANSI_C where commandPressed:
                self.copySelected()
                return nil
            case kVK_Delete where commandPressed:
                self.deleteSelected()
                return nil
            default:
                return event
            }
        }
    }
}

struct ClipboardPaletteView: View {
    @ObservedObject var clipboardService: ClipboardService
    @ObservedObject var selectionState: PaletteSelectionState
    let paste: () -> Void
    let copy: () -> Void
    let delete: () -> Void
    let hide: () -> Void
    @FocusState private var searchFocused: Bool

    private var selectedIndex: Int { selectionState.selectedIndex }

    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search clipboard history", text: $clipboardService.query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 20, weight: .medium))
                        .focused($searchFocused)
                }
                .padding(.horizontal, 18)
                .frame(height: 64)

                Divider()

                if clipboardService.entries.isEmpty {
                    ContentUnavailableView(
                        clipboardService.query.isEmpty ? "No clipboard history yet" : "No matches",
                        systemImage: "doc.on.clipboard",
                        description: Text("Copied text will appear here.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(clipboardService.entries.enumerated()), id: \.element.id) { index, entry in
                                    ClipboardRow(entry: entry, isSelected: index == selectedIndex)
                                        .id(entry.id)
                                        .onTapGesture {
                                            selectionState.selectedIndex = index
                                            paste()
                                        }
                                }
                            }
                        }
                        .onChange(of: selectionState.selectedIndex) { _, newValue in
                            guard clipboardService.entries.indices.contains(newValue) else { return }
                            proxy.scrollTo(clipboardService.entries[newValue].id, anchor: .center)
                        }
                    }
                }

                Divider()

                HStack(spacing: 16) {
                    Label("Paste", systemImage: "return")
                    Label("Copy", systemImage: "command")
                    Label("Delete", systemImage: "delete.left")
                    Spacer()
                    Text("\(clipboardService.entries.count) items")
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 18)
                .frame(height: 40)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onAppear {
            searchFocused = true
        }
    }
}

private struct ClipboardRow: View {
    let entry: ClipboardEntry
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            appIcon
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.preview.replacingOccurrences(of: "\n", with: " "))
                    .lineLimit(2)
                    .font(.system(size: 14))
                HStack(spacing: 8) {
                    Text(entry.sourceAppName ?? "Unknown app")
                    Text("•")
                    Text(relativeTimestamp)
                    Text("•")
                    Text("\(entry.charCount) chars")
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 62)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        .contentShape(Rectangle())
    }

    private var appIcon: some View {
        Group {
            if let image = iconImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var iconImage: NSImage? {
        guard let bundleID = entry.sourceAppBundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private var relativeTimestamp: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: entry.createdAt, relativeTo: Date())
    }
}

private struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blendingMode
    }
}
