import SwiftUI

// MARK: - Section model

enum DashboardSection: String, Identifiable, CaseIterable {
    case home
    case today
    case workflows
    case fileTidy
    case clipboard
    case data
    case terminal
    case developerTools
    case correctionLog
    case aiRequestLog
    case notifications
    case jira
    case asana
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .home:           "Home"
        case .workflows:      "Workflows"
        case .fileTidy:       "File Tidy"
        case .clipboard:      "Clipboard"
        case .data:           "Tidy Data"
        case .terminal:       "Terminal"
        case .developerTools: "Dev Tools"
        case .correctionLog:  "Corrections"
        case .aiRequestLog:   "AI Requests"
        case .notifications:  "Notifications"
        case .jira:           "Jira"
        case .asana:          "Asana"
        case .settings:       "Settings"
        }
    }

    var fullTitle: String {
        switch self {
        case .today: "Today · Notes & Reminders"
        case .home:           "Home"
        case .workflows:      "Developer Workflows"
        case .fileTidy:       "File Tidy"
        case .clipboard:      "Clipboard History"
        case .data:           "Tidy Data Workspace"
        case .terminal:       "Terminal"
        case .developerTools: "Developer Tools"
        case .correctionLog:  "Correction Log"
        case .aiRequestLog:   "AI Requests"
        case .notifications:  "Unified Notifications"
        case .jira:           "Jira Active Sprint"
        case .asana:          "Asana My Tasks"
        case .settings:       "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .today: "sun.max"
        case .home:           "house"
        case .workflows:      "arrow.triangle.branch"
        case .fileTidy:       "folder.badge.gearshape"
        case .clipboard:      "doc.on.clipboard"
        case .data:           "tablecells"
        case .terminal:       "terminal"
        case .developerTools: "chevron.left.forwardslash.chevron.right"
        case .correctionLog:  "checkmark.rectangle"
        case .aiRequestLog:   "network"
        case .notifications:  "bell"
        case .jira:           "shippingbox"
        case .asana:          "checklist"
        case .settings:       "gear"
        }
    }

    var activeSystemImage: String {
        switch self {
        case .today: "sun.max.fill"
        case .home:           "house.fill"
        case .workflows:      "arrow.triangle.branch"
        case .fileTidy:       "folder.badge.gearshape"
        case .clipboard:      "doc.on.clipboard.fill"
        case .data:           "tablecells.fill"
        case .terminal:       "terminal.fill"
        case .developerTools: "chevron.left.forwardslash.chevron.right"
        case .correctionLog:  "checkmark.rectangle.fill"
        case .aiRequestLog:   "network"
        case .notifications:  "bell.fill"
        case .jira:           "shippingbox.fill"
        case .asana:          "checklist.checked"
        case .settings:       "gear"
        }
    }

    var shortcutDigit: Character {
        switch self {
        case .today: "t"
        case .home:           "1"
        case .workflows:      "w"
        case .fileTidy:       "2"
        case .clipboard:      "3"
        case .data:           "d"
        case .terminal:       "4"
        case .developerTools: "5"
        case .correctionLog:  "6"
        case .aiRequestLog:   "7"
        case .notifications:  "n"
        case .jira:           "8"
        case .asana:          "9"
        case .settings:       "0"
        }
    }

    var shortcutLabel: String {
        if self == .today { return "⌘⇧T" }
        if self == .notifications { return "⌘⇧N" }
        if self == .workflows { return "⌘⇧W" }
        if self == .data { return "⌘⇧D" }
        return "⌘\(shortcutDigit)"
    }

    var shortcutModifiers: EventModifiers {
        switch self {
        case .notifications, .workflows, .data, .today: [.command, .shift]
        default: [.command]
        }
    }

    var isBottomGroup: Bool { self == .settings }
}

// MARK: - Sidebar

struct SidebarView: View {
    @Binding var selection: DashboardSection
    @Binding var isCollapsed: Bool
    let visibleSections: [DashboardSection]
    @Environment(\.colorScheme) private var colorScheme

    private var navigationGroups: [(title: String, sections: [DashboardSection])] {
        let groups: [(String, [DashboardSection])] = [
            ("Workspace", [.home, .today, .clipboard, .workflows]),
            ("Tools", [.fileTidy, .data, .terminal, .developerTools]),
            ("Connected", [.notifications, .jira, .asana]),
            ("History", [.correctionLog, .aiRequestLog])
        ]
        return groups.compactMap { title, sections in
            let visible = sections.filter { visibleSections.contains($0) }
            return visible.isEmpty ? nil : (title, visible)
        }
    }
    private var bottomSections: [DashboardSection] {
        visibleSections.filter { $0.isBottomGroup }
    }

    var body: some View {
        VStack(spacing: 0) {
            appBrand
            Divider().opacity(0.4)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(navigationGroups, id: \.title) { group in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(group.title.uppercased()).font(.system(size: 10, weight: .semibold))
                                .tracking(1.1).foregroundStyle(.tertiary).padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 5)
                            ForEach(group.sections) { section in navRow(section) }
                        }
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
            Image("TidyLogo")
                .resizable()
                .interpolation(.high)
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityLabel("Tidy app icon")
            Text("Tidy")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color(NSColor.labelColor))
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isCollapsed = true
                }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
            }
            .buttonStyle(.plain)
            .help("Hide sidebar (⌘/)")
            .accessibilityLabel("Hide sidebar")
        }
        .padding(.horizontal, 14)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }

    private var sidebarBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.10, green: 0.10, blue: 0.11)
            : Color(red: 0.945, green: 0.941, blue: 0.929)
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
                Text(section.shortcutLabel)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(
                        active
                            ? Color.secondary
                            : Color(NSColor.tertiaryLabelColor)
                    )
            }
            .foregroundStyle(active ? Color.primary : Color(NSColor.secondaryLabelColor))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                active ? WorkspaceDesign.border.opacity(0.65) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("\(section.fullTitle) (\(section.shortcutLabel))")
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}

// MARK: - Dashboard root

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 0) {
            if !appState.isSidebarCollapsed {
                SidebarView(
                    selection: $appState.selectedDashboardSection,
                    isCollapsed: $appState.isSidebarCollapsed,
                    visibleSections: appState.visibleDashboardSections
                )
                .transition(.move(edge: .leading).combined(with: .opacity))
            }

            Group {
                switch appState.selectedDashboardSection {
                case .home:
                    HomeView()
                        .environmentObject(appState.correctionLogStore)
                case .today:
                    TodayView().environmentObject(appState.productivityService)
                        .environmentObject(appState.productivitySyncService)
                case .workflows:
                    DeveloperWorkflowsView()
                case .fileTidy:
                    FileTidyView().environmentObject(appState.fileTidyViewModel)
                case .clipboard:
                    ClipboardListView()
                        .environmentObject(appState.clipboardService)
                case .data:
                    DataWorkspaceView()
                        .environmentObject(appState.dataWorkspaceService)
                case .terminal:
                    TerminalView(isSidebarCollapsed: $appState.isSidebarCollapsed)
                        .environmentObject(appState.terminalService)
                case .developerTools:
                    DeveloperToolsView()
                case .correctionLog:
                    CorrectionLogView()
                        .environmentObject(appState.correctionLogStore)
                case .aiRequestLog:
                    AIRequestLogView()
                        .environmentObject(appState.aiRequestLogStore)
                case .notifications:
                    NotificationCenterView()
                        .environmentObject(appState.unifiedNotificationService)
                case .jira:
                    JiraView()
                        .environmentObject(appState.jiraService)
                case .asana:
                    AsanaView()
                        .environmentObject(appState.asanaService)
                case .settings:
                    SettingsView()
                        .environmentObject(appState)
                        .environmentObject(appState.correctionLogStore)
                        .environmentObject(appState.clipboardService)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topLeading) {
                if appState.isSidebarCollapsed,
                   appState.selectedDashboardSection != .terminal {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            appState.isSidebarCollapsed = false
                        }
                    } label: {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 30, height: 30)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .help("Show sidebar (⌘/)")
                    .accessibilityLabel("Show sidebar")
                    .padding(12)
                }
            }
        }
        .background(WorkspaceDesign.canvas)
        .onAppear { appState.onShowMainWindow = { openWindow(id: "main") } }
        .animation(.easeInOut(duration: 0.18), value: appState.isSidebarCollapsed)
        .sheet(isPresented: $appState.showOnboarding) {
            OnboardingView(
                selectedGoals: appState.selectedGoals,
                localOnlyAI: UserDefaults.standard.bool(forKey: AppDefaults.localOnlyAI)
            )
            .environmentObject(appState)
        }
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
                VStack(alignment: .leading, spacing: 8) {
                    Text("A little more space for your work.").font(.system(size: 32, design: .serif))
                    Text("Capture a thought, pick up a task, or put a useful tool to work.")
                        .font(.system(size: 14)).foregroundStyle(.secondary)
                }.padding(.vertical, 12)
                todayCard
                heroCard
                statusRow
                featureGrid
                hotkeysCard
                Spacer(minLength: 8)
            }
            .padding(32)
            .frame(maxWidth: 940)
            .frame(maxWidth: .infinity)
        }
        .background(WorkspaceDesign.canvas)
        .onReceive(permissionTimer) { _ in
            accessibilityTrusted = Permissions.isAccessibilityTrusted
        }
    }

    private var todayCard: some View {
        Button { appState.openToday() } label: {
            HStack(spacing: 14) {
                Image(systemName: "sun.max.fill").font(.system(size: 28)).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Make room for today").font(.system(size: 18, weight: .bold))
                    Text("Plan your focus, capture notes, and keep track of pending work and routines.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Label("Open Today", systemImage: "arrow.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.accentColor)
            }.padding(20).background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain)
    }

    // MARK: Hero card

    private var heroCard: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(WorkspaceDesign.inset)
                    .frame(width: 52, height: 52)
                Image(systemName: "sparkles")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.primary)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("Tidy Selected Text")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)
                Text("Select text anywhere, press the hotkey, and grammar is fixed instantly.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("⌃⌥G")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(.primary)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(WorkspaceDesign.inset, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(WorkspaceDesign.border, lineWidth: 0.5)
                )
        }
        .padding(20)
        .background(WorkspaceDesign.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(WorkspaceDesign.border))
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
                    .buttonStyle(WorkspaceButtonStyle())
                    .controlSize(.small)

                Button("Restart Tidy") { appState.restartApp() }
                    .buttonStyle(WorkspaceButtonStyle())
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
        .background(WorkspaceDesign.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
            .background(WorkspaceDesign.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
