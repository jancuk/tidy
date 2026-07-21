import SwiftUI

// MARK: - Section model

enum DashboardSection: String, Identifiable, CaseIterable {
    case home
    case fileTidy
    case clipboard
    case developerTools
    case correctionLog
    case aiRequestLog
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home:           "Home"
        case .fileTidy:       "File Tidy"
        case .clipboard:      "Clipboard"
        case .developerTools: "Dev Tools"
        case .correctionLog:  "Corrections"
        case .aiRequestLog:   "AI Requests"
        case .settings:       "Settings"
        }
    }

    var fullTitle: String {
        switch self {
        case .home:           "Home"
        case .fileTidy:       "File Tidy"
        case .clipboard:      "Clipboard History"
        case .developerTools: "Developer Tools"
        case .correctionLog:  "Correction Log"
        case .aiRequestLog:   "AI Requests"
        case .settings:       "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .home:           "house"
        case .fileTidy:       "folder.badge.gearshape"
        case .clipboard:      "doc.on.clipboard"
        case .developerTools: "chevron.left.forwardslash.chevron.right"
        case .correctionLog:  "checkmark.rectangle"
        case .aiRequestLog:   "network"
        case .settings:       "gear"
        }
    }

    var activeSystemImage: String {
        switch self {
        case .home:           "house.fill"
        case .fileTidy:       "folder.badge.gearshape"
        case .clipboard:      "doc.on.clipboard.fill"
        case .developerTools: "chevron.left.forwardslash.chevron.right"
        case .correctionLog:  "checkmark.rectangle.fill"
        case .aiRequestLog:   "network"
        case .settings:       "gear"
        }
    }

    var isBottomGroup: Bool { self == .settings }
}

// MARK: - Sidebar

struct SidebarView: View {
    @Binding var selection: DashboardSection
    @Environment(\.colorScheme) private var colorScheme

    private var topSections: [DashboardSection] {
        DashboardSection.allCases.filter { !$0.isBottomGroup }
    }
    private var bottomSections: [DashboardSection] {
        DashboardSection.allCases.filter { $0.isBottomGroup }
    }

    var body: some View {
        VStack(spacing: 0) {
            appBrand
            Divider().opacity(0.4)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(topSections) { section in
                        navRow(section)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 10)
            }

            Spacer()
            Divider().opacity(0.4).padding(.horizontal, 10)

            VStack(spacing: 2) {
                ForEach(bottomSections) { section in
                    navRow(section)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
            .padding(.top, 6)
        }
        .frame(width: 200)
        .background(sidebarBackground)
        .overlay(alignment: .trailing) {
            Divider().opacity(0.4)
        }
    }

    private var appBrand: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.accentColor)
                    .frame(width: 28, height: 28)
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Text("Tidy")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color(NSColor.labelColor))
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }

    private var sidebarBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.10, green: 0.10, blue: 0.11)
            : Color(red: 0.93, green: 0.93, blue: 0.95)
    }

    @ViewBuilder
    private func navRow(_ section: DashboardSection) -> some View {
        let active = selection == section
        Button { selection = section } label: {
            HStack(spacing: 9) {
                Image(systemName: active ? section.activeSystemImage : section.systemImage)
                    .font(.system(size: 13, weight: active ? .semibold : .regular))
                    .frame(width: 18, alignment: .center)
                Text(section.title)
                    .font(.system(size: 13, weight: active ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(active ? Color.accentColor : Color(NSColor.secondaryLabelColor))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                active ? Color.accentColor.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(section.fullTitle)
    }
}

// MARK: - Dashboard root

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selection: DashboardSection = .home

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(selection: $selection)

            Group {
                switch selection {
                case .home:
                    HomeView()
                        .environmentObject(appState.correctionLogStore)
                case .fileTidy:
                    FileTidyView()
                case .clipboard:
                    ClipboardListView()
                        .environmentObject(appState.clipboardService)
                case .developerTools:
                    DeveloperToolsView()
                case .correctionLog:
                    CorrectionLogView()
                        .environmentObject(appState.correctionLogStore)
                case .aiRequestLog:
                    AIRequestLogView()
                        .environmentObject(appState.aiRequestLogStore)
                case .settings:
                    SettingsView()
                        .environmentObject(appState)
                        .environmentObject(appState.correctionLogStore)
                        .environmentObject(appState.clipboardService)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

// MARK: - Home

struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var correctionLogStore: CorrectionLogStore
    @AppStorage(AppDefaults.autoSuggestEnabled) private var autoSuggestEnabled = true
    @AppStorage(AppDefaults.grammarProvider) private var grammarProvider = GrammarProviderID.gemini.rawValue
    @State private var accessibilityTrusted = Permissions.isAccessibilityTrusted
    private let permissionTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                heroCard
                statusRow
                featureGrid
                hotkeysCard
                Spacer(minLength: 8)
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

    // MARK: Hero card

    private var heroCard: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.18))
                    .frame(width: 52, height: 52)
                Image(systemName: "sparkles")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Tidy Selected Text")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                Text("Select text anywhere, press the hotkey, and grammar is fixed instantly.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("⌃⌥G")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.white.opacity(0.28), lineWidth: 0.5)
                )
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color.accentColor, Color.accentColor.opacity(0.68)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .shadow(color: Color.accentColor.opacity(0.30), radius: 14, y: 5)
    }

    // MARK: Status row

    private var statusRow: some View {
        HStack(spacing: 8) {
            if accessibilityTrusted {
                statusPill(title: "Accessibility on", icon: "checkmark.circle.fill", tint: .green)
            } else {
                Button(action: openAccessibilityConfiguration) {
                    statusPill(title: "Accessibility needed", icon: "exclamationmark.circle.fill", tint: .orange)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Open Accessibility settings")

                Button("Open Settings", action: openAccessibilityConfiguration)
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                Button("Restart Tidy") { appState.restartApp() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            statusPill(title: providerDisplayName, icon: "cpu", tint: .blue)
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    autoSuggestEnabled.toggle()
                }
            } label: {
                statusPill(
                    title: autoSuggestEnabled ? "Auto-suggest on" : "Auto-suggest off",
                    icon: autoSuggestEnabled ? "checkmark.circle.fill" : "xmark.circle.fill",
                    tint: autoSuggestEnabled ? .green : .orange
                )
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(autoSuggestEnabled ? "Turn off auto-suggest" : "Turn on auto-suggest")
            .accessibilityLabel("Auto-suggest")
            .accessibilityValue(autoSuggestEnabled ? "On" : "Off")
            .accessibilityHint(autoSuggestEnabled ? "Turn off auto-suggest" : "Turn on auto-suggest")
        }
    }

    private func openAccessibilityConfiguration() {
        accessibilityTrusted = Permissions.requestAccessibilityIfNeeded()
        Permissions.openAccessibilitySettings()
    }

    private func statusPill(title: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(title)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(tint.opacity(0.10), in: Capsule())
        .overlay(Capsule().stroke(tint.opacity(0.2), lineWidth: 0.5))
    }

    // MARK: Feature grid

    private var featureGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Features")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                featureCard(
                    icon: "doc.on.clipboard",
                    accent: .blue,
                    count: appState.clipboardService.entries.count,
                    title: "Clipboard",
                    subtitle: "⌃⌥V to open palette"
                )
                featureCard(
                    icon: "chevron.left.forwardslash.chevron.right",
                    accent: .purple,
                    count: DeveloperTool.allCases.count,
                    title: "Dev Tools",
                    subtitle: "JSON, JWT, Diff, Cron…"
                )
                featureCard(
                    icon: "folder.badge.gearshape",
                    accent: .orange,
                    count: FileTidyCategory.allCases.count,
                    title: "File Tidy",
                    subtitle: "Local-only cleanup rules"
                )
                featureCard(
                    icon: "checkmark.rectangle",
                    accent: .green,
                    count: correctionLogStore.entries.count,
                    title: "Corrections",
                    subtitle: "Grammar fixes logged"
                )
            }
        }
    }

    private func featureCard(icon: String, accent: Color, count: Int, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(accent.opacity(0.12))
                        .frame(width: 34, height: 34)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(accent)
                }
                Spacer()
                Text("\(count)")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color(NSColor.labelColor))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(NSColor.labelColor))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5)
        )
    }

    // MARK: Hotkeys card

    private var hotkeysCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Keyboard Shortcuts")
            VStack(spacing: 0) {
                hotkeyRow(label: "Tidy selected text", combo: "⌃⌥G")
                Divider().opacity(0.4).padding(.leading, 14)
                hotkeyRow(label: "Open clipboard palette", combo: "⌃⌥V")
                Divider().opacity(0.4).padding(.leading, 14)
                hotkeyRow(label: "Ask AI anything", combo: "⌃⌥J")
            }
            .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5)
            )
        }
    }

    private func hotkeyRow(label: String, combo: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(Color(NSColor.labelColor))
            Spacer()
            Text(combo)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(Color(NSColor.labelColor))
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlColor), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color(NSColor.separatorColor).opacity(0.8), lineWidth: 0.5)
                )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Color(NSColor.secondaryLabelColor))
            .textCase(.uppercase)
            .kerning(0.5)
    }

    private var providerDisplayName: String {
        GrammarProviderID(rawValue: grammarProvider)?.displayName ?? grammarProvider
    }
}

// MARK: - Page header helper

fileprivate struct ContentHeader<Actions: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let actions: Actions

    init(title: String, subtitle: String? = nil, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.subtitle = subtitle
        self.actions = actions()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Color(NSColor.labelColor))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(NSColor.secondaryLabelColor))
                }
            }
            Spacer()
            HStack(spacing: 8) { actions }
                .controlSize(.small)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .background(Color(NSColor.controlBackgroundColor))
        .overlay(alignment: .bottom) { Divider().opacity(0.5) }
    }
}

// MARK: - Clipboard list

struct ClipboardListView: View {
    @EnvironmentObject private var clipboardService: ClipboardService

    var body: some View {
        VStack(spacing: 0) {
            ContentHeader(
                title: "Clipboard History",
                subtitle: "\(clipboardService.entries.count) items stored"
            ) { EmptyView() }

            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
                TextField("Search…", text: $clipboardService.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                if !clipboardService.query.isEmpty {
                    Button {
                        clipboardService.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(NSColor.secondaryLabelColor))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Color(NSColor.controlBackgroundColor))
            .overlay(alignment: .bottom) { Divider().opacity(0.5) }

            if clipboardService.entries.isEmpty {
                ContentUnavailableView(
                    "No clipboard history yet",
                    systemImage: "doc.on.clipboard",
                    description: Text("Copy some text and it will appear here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(clipboardService.entries.enumerated()), id: \.element.id) { index, entry in
                            ClipboardRowView(
                                entry: entry,
                                onDelete: { clipboardService.delete(entry) }
                            )
                            if index < clipboardService.entries.count - 1 {
                                Divider().opacity(0.35).padding(.leading, 56)
                            }
                        }
                    }
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

private struct ClipboardRowView: View {
    let entry: ClipboardEntry
    let onDelete: () -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(appColor(for: entry.sourceAppName))
                .frame(width: 9, height: 9)
                .padding(.leading, 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.preview)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(NSColor.labelColor))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    if let app = entry.sourceAppName {
                        Text(app)
                    }
                    Text("·")
                    Text(entry.createdAt, style: .relative)
                    Text("·")
                    Text("\(entry.charCount) chars")
                }
                .font(.system(size: 11))
                .foregroundStyle(Color(NSColor.secondaryLabelColor))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isHovered {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.content, forType: .string)
                } label: {
                    Text("Copy")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.10), in: Capsule())
                        .overlay(Capsule().stroke(Color.accentColor.opacity(0.25), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
                .padding(.trailing, 18)
            }
        }
        .padding(.vertical, 11)
        .background(isHovered ? Color(NSColor.controlBackgroundColor) : Color.clear)
        .animation(.easeInOut(duration: 0.1), value: isHovered)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.content, forType: .string)
            }
            Button("Delete", role: .destructive) { onDelete() }
        }
    }

    private func appColor(for appName: String?) -> Color {
        switch appName?.lowercased() {
        case "safari":                                       return Color(red: 0, green: 0.478, blue: 1)
        case "chrome", "google chrome":                      return Color(red: 1, green: 0.584, blue: 0)
        case "firefox":                                      return Color(red: 1, green: 0.4, blue: 0.1)
        case "xcode":                                        return Color(red: 0.345, green: 0.525, blue: 0.835)
        case "vs code", "visual studio code", "code":        return Color(red: 0.2, green: 0.784, blue: 0.349)
        case "terminal", "iterm2", "iterm":                  return Color(red: 0.15, green: 0.15, blue: 0.15)
        case "notes":                                        return Color(red: 1, green: 0.231, blue: 0.188)
        case "slack":                                        return Color(red: 0.44, green: 0.15, blue: 0.6)
        default:                                             return Color(NSColor.secondaryLabelColor)
        }
    }
}

// MARK: - Correction log

struct CorrectionLogView: View {
    @EnvironmentObject private var correctionLogStore: CorrectionLogStore

    var body: some View {
        VStack(spacing: 0) {
            ContentHeader(
                title: "Correction Log",
                subtitle: "\(correctionLogStore.entries.count) corrections recorded"
            ) {
                Button("Clear") { correctionLogStore.clear() }
                    .buttonStyle(.bordered)
                    .disabled(correctionLogStore.entries.isEmpty)
            }

            if correctionLogStore.entries.isEmpty {
                ContentUnavailableView(
                    "No corrections yet",
                    systemImage: "checkmark.rectangle",
                    description: Text("Grammar corrections you apply will be logged here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(correctionLogStore.entries.enumerated()), id: \.element.id) { index, entry in
                            VStack(alignment: .leading, spacing: 8) {
                                if !entry.original.isEmpty {
                                    Text(entry.original)
                                        .font(.system(size: 13))
                                        .foregroundStyle(Color(NSColor.secondaryLabelColor))
                                        .strikethrough(color: Color(NSColor.secondaryLabelColor))
                                        .lineLimit(2)
                                }
                                Text(entry.corrected)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color(NSColor.labelColor))
                                    .lineLimit(3)
                                HStack(spacing: 6) {
                                    Text(entry.providerID)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(Color(NSColor.secondaryLabelColor))
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 2)
                                        .background(Color(NSColor.controlBackgroundColor), in: Capsule())
                                        .overlay(Capsule().stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5))
                                    Text(entry.createdAt, style: .relative)
                                        .font(.system(size: 11))
                                        .foregroundStyle(Color(NSColor.secondaryLabelColor))
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 13)

                            if index < correctionLogStore.entries.count - 1 {
                                Divider().opacity(0.35).padding(.leading, 20)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}
