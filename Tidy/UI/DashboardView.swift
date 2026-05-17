import SwiftUI

enum DashboardSection: String, Identifiable, CaseIterable {
    case home
    case developerTools
    case clipboard
    case correctionLog

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .developerTools: "Developer Tools"
        case .clipboard: "Clipboard History"
        case .correctionLog: "Correction Log"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .developerTools: "hammer"
        case .clipboard: "doc.on.clipboard"
        case .correctionLog: "list.bullet.rectangle"
        }
    }
}

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openSettings) private var openSettings
    @State private var selection: DashboardSection = .home
    @State private var accessibilityTrusted: Bool = Permissions.isAccessibilityTrusted
    private let permissionTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationSplitView {
            List(DashboardSection.allCases, selection: $selection) { section in
                NavigationLink(value: section) {
                    Label(section.title, systemImage: section.systemImage)
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 200)
            .navigationTitle("Tidy")
        } detail: {
            switch selection {
            case .home:
                HomeView(accessibilityTrusted: $accessibilityTrusted)
            case .developerTools:
                DeveloperToolsView()
            case .clipboard:
                ClipboardListView()
                    .environmentObject(appState.clipboardService)
            case .correctionLog:
                CorrectionLogView()
            }
        }
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
}

struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var accessibilityTrusted: Bool
    @AppStorage(AppDefaults.autoSuggestEnabled) private var autoSuggestEnabled: Bool = true
    @AppStorage(AppDefaults.grammarProvider) private var grammarProvider = GrammarProviderID.gemini.rawValue

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                statusCard

                actionsGrid

                hotkeysCard

                Spacer(minLength: 12)
            }
            .padding(24)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .navigationTitle("Home")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.tint)
                Text("Tidy")
                    .font(.system(size: 32, weight: .bold))
            }
            Text("Your menu bar companion for grammar correction and clipboard history.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Status")
                .font(.headline)

            HStack(spacing: 10) {
                statusBadge(
                    title: accessibilityTrusted ? "Accessibility" : "Accessibility needed",
                    systemImage: accessibilityTrusted ? "checkmark.shield.fill" : "exclamationmark.shield.fill",
                    tint: accessibilityTrusted ? .green : .orange
                )

                statusBadge(
                    title: autoSuggestEnabled ? "Auto-suggest on" : "Auto-suggest off",
                    systemImage: autoSuggestEnabled ? "wand.and.sparkles" : "wand.and.sparkles.inverse",
                    tint: autoSuggestEnabled ? .blue : .secondary
                )

                statusBadge(
                    title: "Provider: \(providerDisplayName)",
                    systemImage: "brain.head.profile",
                    tint: .purple
                )
            }

            if !accessibilityTrusted {
                Button("Open Accessibility Settings") {
                    Permissions.openAccessibilitySettings()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func statusBadge(title: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.12), in: Capsule())
    }

    private var actionsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick actions")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ActionCard(
                    title: "Tidy Clipboard Text",
                    subtitle: "Fix grammar of whatever is on your clipboard now.",
                    systemImage: "sparkles"
                ) {
                    appState.tidyClipboardText()
                }

                ActionCard(
                    title: "Open Clipboard Palette",
                    subtitle: "Search and paste from your clipboard history.",
                    systemImage: "doc.on.clipboard"
                ) {
                    appState.openPalette()
                }

                ActionCard(
                    title: autoSuggestEnabled ? "Disable Auto-suggest" : "Enable Auto-suggest",
                    subtitle: "Watch focused fields and offer corrections after a pause.",
                    systemImage: "wand.and.sparkles"
                ) {
                    autoSuggestEnabled.toggle()
                }

                ActionCard(
                    title: "Tidy Selected Text",
                    subtitle: "Press ⌃⌥G after selecting text in any app.",
                    systemImage: "textformat"
                ) {
                    // No-op: this is a reminder card
                }
            }
        }
    }

    private var hotkeysCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hotkeys")
                .font(.headline)
            VStack(spacing: 0) {
                hotkeyRow(label: "Tidy selected text", combo: "⌃⌥G")
                Divider()
                hotkeyRow(label: "Open clipboard palette", combo: "⌃⌥V")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func hotkeyRow(label: String, combo: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(combo)
                .font(.system(.body, design: .monospaced).weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.background, in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6).stroke(.separator, lineWidth: 0.5)
                )
        }
        .padding(.vertical, 10)
    }

    private var providerDisplayName: String {
        GrammarProviderID(rawValue: grammarProvider)?.displayName ?? grammarProvider
    }
}

private struct ActionCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.tint)
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isHovered ? Color.accentColor.opacity(0.10) : Color.gray.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.separator, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
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
        .navigationTitle("Clipboard History")
    }
}

struct CorrectionLogView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if appState.correctionLogStore.entries.isEmpty {
                ContentUnavailableView(
                    "No corrections yet",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Grammar corrections you apply will be logged here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(appState.correctionLogStore.entries) { entry in
                    VStack(alignment: .leading, spacing: 6) {
                        if !entry.original.isEmpty {
                            Text(entry.original)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .strikethrough()
                        }
                        Text(entry.corrected)
                            .font(.system(size: 13))
                        HStack(spacing: 8) {
                            Text(entry.providerID)
                            Text("•")
                            Text(entry.createdAt, style: .relative)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.inset)
            }
        }
        .padding(16)
        .navigationTitle("Correction Log")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("Clear") {
                    appState.correctionLogStore.clear()
                }
            }
        }
    }
}
