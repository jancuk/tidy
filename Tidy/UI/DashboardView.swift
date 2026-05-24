import SwiftUI

enum DashboardSection: String, Identifiable, CaseIterable {
    case home
    case clipboard
    case developerTools
    case correctionLog
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:           "Home"
        case .clipboard:      "Clipboard History"
        case .developerTools: "Developer Tools"
        case .correctionLog:  "Correction Log"
        case .settings:       "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .home:           "house"
        case .clipboard:      "doc.on.clipboard"
        case .developerTools: "chevron.left.forwardslash.chevron.right"
        case .correctionLog:  "checkmark.rectangle"
        case .settings:       "gear"
        }
    }

    /// Whether this section appears in the bottom rail group (below the divider).
    var isBottomGroup: Bool { self == .settings }
}

struct IconRailView: View {
    @Binding var selection: DashboardSection

    private var topSections: [DashboardSection] {
        DashboardSection.allCases.filter { !$0.isBottomGroup }
    }
    private var bottomSections: [DashboardSection] {
        DashboardSection.allCases.filter { $0.isBottomGroup }
    }

    var body: some View {
        VStack(spacing: 2) {
            ForEach(topSections) { section in
                railButton(section)
            }
            Spacer()
            Divider()
                .frame(width: 28)
                .padding(.vertical, 4)
            ForEach(bottomSections) { section in
                railButton(section)
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(width: 54)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(alignment: .trailing) {
            Divider()
        }
    }

    @ViewBuilder
    private func railButton(_ section: DashboardSection) -> some View {
        let active = selection == section
        Button {
            selection = section
        } label: {
            ZStack(alignment: .leading) {
                // Active left-edge indicator bar
                if active {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color(NSColor.labelColor).opacity(0.7))
                        .frame(width: 3, height: 18)
                        .offset(x: -1)
                }
                // Icon background + icon
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(active
                        ? Color(NSColor.labelColor).opacity(0.11)
                        : Color.clear)
                    .frame(width: 36, height: 36)
                    .overlay {
                        Image(systemName: section.systemImage)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(active
                                ? Color(NSColor.labelColor)
                                : Color(NSColor.secondaryLabelColor))
                    }
            }
            .frame(width: 54, height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(section.title)
    }
}

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selection: DashboardSection = .home

    var body: some View {
        HStack(spacing: 0) {
            IconRailView(selection: $selection)

            Group {
                switch selection {
                case .home:
                    HomeView()
                case .clipboard:
                    ClipboardListView()
                        .environmentObject(appState.clipboardService)
                case .developerTools:
                    DeveloperToolsView()
                case .correctionLog:
                    CorrectionLogView()
                case .settings:
                    SettingsView()
                        .environmentObject(appState)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage(AppDefaults.autoSuggestEnabled) private var autoSuggestEnabled = true
    @AppStorage(AppDefaults.grammarProvider) private var grammarProvider = GrammarProviderID.gemini.rawValue
    @State private var accessibilityTrusted = Permissions.isAccessibilityTrusted
    private let permissionTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                heroCard
                statusRow
                quickAccessSection
                hotkeysCard
                Spacer(minLength: 12)
            }
            .padding(22)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onReceive(permissionTimer) { _ in
            accessibilityTrusted = Permissions.isAccessibilityTrusted
        }
    }

    @Environment(\.colorScheme) private var colorScheme

    private var heroGradient: LinearGradient {
        colorScheme == .dark
            ? LinearGradient(
                colors: [Color(hex: "#48484a"), Color(hex: "#6e6e73")],
                startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(
                colors: [Color(hex: "#2c2c2e"), Color(hex: "#505050")],
                startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var heroCard: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.white.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Tidy Selected Text")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                Text("Select text in any app, then press the hotkey to fix grammar instantly.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("⌃⌥G")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.white.opacity(0.13), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(.white.opacity(0.2), lineWidth: 0.5)
                )
        }
        .padding(18)
        .background(heroGradient, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 7, y: 3)
    }

    private var statusRow: some View {
        HStack(spacing: 7) {
            statusBadge(
                title: accessibilityTrusted ? "Accessibility on" : "Accessibility needed",
                tint: accessibilityTrusted ? .green : .orange
            )
            statusBadge(title: providerDisplayName, tint: .green)
            statusBadge(
                title: autoSuggestEnabled ? "Auto-suggest on" : "Auto-suggest off",
                tint: autoSuggestEnabled ? .green : .orange
            )
        }
    }

    private func statusBadge(title: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(tint.opacity(0.1), in: Capsule())
    }

    private var quickAccessSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Access")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color(NSColor.secondaryLabelColor))
                .textCase(.uppercase)
                .kerning(0.5)

            HStack(spacing: 10) {
                quickChip(
                    icon: "doc.on.clipboard",
                    count: appState.clipboardService.entries.count,
                    label: "Clipboard",
                    subtitle: "⌃⌥V to open palette"
                )
                quickChip(
                    icon: "chevron.left.forwardslash.chevron.right",
                    count: DeveloperTool.allCases.count,
                    label: "Dev Tools",
                    subtitle: "JSON, JWT, Diff…"
                )
                quickChip(
                    icon: "checkmark.rectangle",
                    count: appState.correctionLogStore.entries.count,
                    label: "Corrections",
                    subtitle: "Today's log"
                )
            }
        }
    }

    private func quickChip(icon: String, count: Int, label: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
                Spacer()
                Text("\(count)")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color(NSColor.labelColor))
            }
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(NSColor.labelColor))
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(Color(NSColor.secondaryLabelColor))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color(NSColor.separatorColor).opacity(0.6), lineWidth: 0.5)
        )
    }

    private var hotkeysCard: some View {
        VStack(spacing: 0) {
            hotkeyRow(label: "Tidy selected text", combo: "⌃⌥G")
            Divider().opacity(0.5)
            hotkeyRow(label: "Open clipboard palette", combo: "⌃⌥V")
        }
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color(NSColor.separatorColor).opacity(0.6), lineWidth: 0.5)
        )
    }

    private func hotkeyRow(label: String, combo: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Color(NSColor.labelColor))
            Spacer()
            Text(combo)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(NSColor.labelColor))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color(NSColor.windowBackgroundColor), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var providerDisplayName: String {
        GrammarProviderID(rawValue: grammarProvider)?.displayName ?? grammarProvider
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

struct CorrectionLogView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Correction Log")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color(NSColor.labelColor))
                Spacer()
                Button("Clear") { appState.correctionLogStore.clear() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 10)
            .overlay(alignment: .bottom) { Divider() }

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
    }
}
