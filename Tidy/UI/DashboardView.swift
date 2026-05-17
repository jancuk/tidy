import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openSettings) private var openSettings
    @State private var accessibilityTrusted: Bool = Permissions.isAccessibilityTrusted
    private let permissionTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            ClipboardListView()
                .environmentObject(appState.clipboardService)
        }
        .navigationTitle("Tidy")
        .onReceive(permissionTimer) { _ in
            accessibilityTrusted = Permissions.isAccessibilityTrusted
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    openSettings()
                } label: {
                    Label("Settings", systemImage: "gear")
                }
            }
        }
    }

    private var sidebar: some View {
        List {
            Section("Actions") {
                Button {
                    appState.tidyClipboardText()
                } label: {
                    Label("Tidy Clipboard Text", systemImage: "sparkles")
                }
                .buttonStyle(.plain)

                Button {
                    appState.openPalette()
                } label: {
                    Label("Open Clipboard Palette", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.plain)
            }

            Section("Hotkeys") {
                Label("⌃⌥G — Tidy selected text", systemImage: "textformat")
                Label("⌃⌥V — Open palette", systemImage: "keyboard")
            }

            Section("Status") {
                Label(
                    accessibilityTrusted ? "Accessibility allowed" : "Accessibility needed",
                    systemImage: accessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                .foregroundStyle(accessibilityTrusted ? .green : .orange)

                if !accessibilityTrusted {
                    Button("Open Accessibility Settings") {
                        Permissions.openAccessibilitySettings()
                    }
                    .buttonStyle(.link)
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 220)
    }
}

struct ClipboardListView: View {
    @EnvironmentObject private var clipboardService: ClipboardService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search clipboard history", text: $clipboardService.query)
                    .textFieldStyle(.plain)
            }
            .padding(10)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

            if clipboardService.entries.isEmpty {
                ContentUnavailableView(
                    "No clipboard history yet",
                    systemImage: "doc.on.clipboard",
                    description: Text("Copy some text and it will appear here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(clipboardService.entries) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.preview)
                            .lineLimit(3)
                        HStack(spacing: 8) {
                            if let appName = entry.sourceAppName {
                                Text(appName)
                            }
                            Text(entry.createdAt, style: .relative)
                            Text("\(entry.charCount) chars")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .contextMenu {
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(entry.content, forType: .string)
                        }
                        Button("Delete", role: .destructive) {
                            clipboardService.delete(entry)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding(16)
    }
}
