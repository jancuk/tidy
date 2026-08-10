import AppKit
import Combine
import Foundation
import ServiceManagement

@MainActor
final class AppState: ObservableObject {
    let clipboardService: ClipboardService
    let correctionLogStore: CorrectionLogStore
    let aiRequestLogStore: AIRequestLogStore
    let suggestionMonitor: SuggestionMonitor
    let jiraService: JiraService
    let asanaService: AsanaService
    let terminalService: TerminalService
    let unifiedNotificationService: UnifiedNotificationService
    @Published var showOnboarding: Bool
    @Published private(set) var selectedGoals: Set<TidyGoal>
    @Published private(set) var credentialRevision = 0
    @Published var selectedDashboardSection: DashboardSection {
        didSet {
            UserDefaults.standard.set(selectedDashboardSection.rawValue, forKey: AppDefaults.dashboardSection)
        }
    }
    @Published var isSidebarCollapsed: Bool {
        didSet {
            UserDefaults.standard.set(isSidebarCollapsed, forKey: AppDefaults.sidebarCollapsed)
        }
    }

    private let hotkeyManager = HotkeyManager()
    private let hud = HUDController()
    private let grammarService: GrammarService
    private let paletteController: ClipboardPaletteController
    private let askAIController: AskAIController
    private let suggestionPopup = SuggestionPopupController()
    private var cancellables: Set<AnyCancellable> = []

    init() {
        let defaults = UserDefaults.standard
        let hadCompletedLegacyFirstRun = defaults.bool(forKey: AppDefaults.didCompleteFirstRun)
        let hadOnboardingPreference = defaults.object(forKey: AppDefaults.didCompleteOnboarding) != nil
        defaults.registerTidyDefaults()
        let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        if hadCompletedLegacyFirstRun && !hadOnboardingPreference {
            defaults.set(true, forKey: AppDefaults.didCompleteOnboarding)
        }
        let storedGoals = TidyGoal.decode(defaults.string(forKey: AppDefaults.selectedGoals) ?? "")
        selectedGoals = storedGoals.isEmpty && hadCompletedLegacyFirstRun
            ? Set(TidyGoal.allCases)
            : storedGoals
        showOnboarding = !isRunningTests
            && !defaults.bool(forKey: AppDefaults.didCompleteOnboarding)
        selectedDashboardSection = isRunningTests
            ? .home
            : DashboardSection(
                rawValue: UserDefaults.standard.string(forKey: AppDefaults.dashboardSection) ?? ""
            ) ?? .home
        isSidebarCollapsed = UserDefaults.standard.bool(forKey: AppDefaults.sidebarCollapsed)
        clipboardService = ClipboardService()
        correctionLogStore = CorrectionLogStore()
        aiRequestLogStore = AIRequestLogStore()
        grammarService = GrammarService(hud: hud, logStore: correctionLogStore, requestLogStore: aiRequestLogStore)
        paletteController = ClipboardPaletteController(clipboardService: clipboardService)
        askAIController = AskAIController(requestLogStore: aiRequestLogStore)
        suggestionMonitor = SuggestionMonitor()
        jiraService = JiraService()
        asanaService = AsanaService()
        terminalService = TerminalService()
        unifiedNotificationService = UnifiedNotificationService(requestLogStore: aiRequestLogStore)

        hotkeyManager.onGrammar = { [weak self] in
            Task { @MainActor in self?.grammarService.tidySelectedText() }
        }
        hotkeyManager.onClipboard = { [weak self] in
            Task { @MainActor in self?.paletteController.toggle() }
        }
        hotkeyManager.onAskAI = { [weak self] in
            Task { @MainActor in self?.askAIController.toggle() }
        }

        suggestionMonitor.onSuggestion = { [weak self] suggestion in
            guard let self else { return }
            self.suggestionPopup.show(original: suggestion.original, corrected: suggestion.corrected, anchorRect: suggestion.anchorRect)
        }
        suggestionMonitor.onDismiss = { [weak self] in
            self?.suggestionPopup.dismiss()
        }
        suggestionPopup.onAccept = { [weak self] corrected in
            guard let self else { return }
            self.suggestionMonitor.applyReplacement(corrected)
            self.suggestionMonitor.noteAccepted()
            self.correctionLogStore.append(original: "", corrected: corrected, providerID: UserDefaults.standard.string(forKey: AppDefaults.grammarProvider) ?? "")
        }
        suggestionPopup.onDismiss = { [weak self] original in
            self?.suggestionMonitor.noteDismissed(text: original)
        }

        start()
    }

    func start() {
        NSApp.setActivationPolicy(.regular)
        clipboardService.start()
        suggestionMonitor.start()
        unifiedNotificationService.start()
        registerHotkeys()
        if !showOnboarding,
           !UserDefaults.standard.bool(forKey: AppDefaults.didCompleteFirstRun) {
            Permissions.requestAccessibilityIfNeeded()
            UserDefaults.standard.set(true, forKey: AppDefaults.didCompleteFirstRun)
        }
    }

    func registerHotkeys() {
        let defaults = UserDefaults.standard
        let grammar = Hotkey.parse(defaults.string(forKey: AppDefaults.grammarHotkey) ?? "", fallback: .grammarDefault)
        let clipboard = Hotkey.parse(defaults.string(forKey: AppDefaults.clipboardHotkey) ?? "", fallback: .clipboardDefault)
        let askAI = Hotkey.parse(defaults.string(forKey: AppDefaults.askAIHotkey) ?? "", fallback: .askAIDefault)
        hotkeyManager.register(grammar: grammar, clipboard: clipboard, askAI: askAI)
    }

    func openPalette() {
        paletteController.show()
    }

    func openAskAI() {
        askAIController.show()
    }

    func openJira(issueID: String? = nil) {
        selectedDashboardSection = .jira
        if let issueID { jiraService.requestIssue(issueID) }
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.title == "Tidy" })?.makeKeyAndOrderFront(nil)
    }

    func openJiraNotifications() {
        selectedDashboardSection = .jira
        jiraService.requestNotificationCenter()
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.title == "Tidy" })?.makeKeyAndOrderFront(nil)
    }

    func openUnifiedNotifications() {
        selectedDashboardSection = .notifications
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.title == "Tidy" })?.makeKeyAndOrderFront(nil)
    }

    func openMCPSettings() {
        UserDefaults.standard.set("MCP", forKey: AppDefaults.settingsTab)
        selectedDashboardSection = .settings
    }

    func refreshJira() async {
        let defaults = UserDefaults.standard
        let projectKey = defaults.string(forKey: AppDefaults.jiraProjectKey) ?? ""
        guard await jiraService.refreshConfigurationStatus(),
              !projectKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        await jiraService.loadActiveSprintIssues(
            projectKey: projectKey,
            assigneeAccountID: defaults.string(forKey: AppDefaults.jiraAssigneeAccountID)
        )
    }

    func tidyClipboardText() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            hud.show(.warning("Clipboard is empty"), autoDismissAfter: 1.2)
            return
        }

        hud.show(.loading("Tidying clipboard..."))
        Task {
            let providerIDs = GrammarCorrectionPipeline.configuredProviderIDs()
            let start = Date()
            do {
                let result = try await GrammarCorrectionPipeline.correct(text, providerIDs: providerIDs)
                let ms = Int(Date().timeIntervalSince(start) * 1000)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(result.correctedText, forType: .string)
                correctionLogStore.append(original: text, corrected: result.correctedText, providerID: result.providerID)
                for failure in result.failures {
                    aiRequestLogStore.append(AIRequestLogEntry(
                        providerName: failure.providerName,
                        requestPreview: String(text.prefix(100)),
                        statusCode: failure.statusCode,
                        errorMessage: failure.message,
                        durationMs: failure.durationMs,
                        source: "grammar-fallback"
                    ))
                }
                aiRequestLogStore.append(AIRequestLogEntry(
                    providerName: result.providerName,
                    requestPreview: String(text.prefix(100)),
                    durationMs: ms,
                    source: "grammar"
                ))
                let message = result.usedFallback ? "Clipboard tidied · \(result.providerName) fallback" : "Clipboard tidied"
                hud.show(.success(message), autoDismissAfter: 1.5)
            } catch {
                let ms = Int(Date().timeIntervalSince(start) * 1000)
                if case GrammarCorrectionPipelineError.allProvidersFailed(let failures) = error {
                    for failure in failures {
                        aiRequestLogStore.append(AIRequestLogEntry(
                            providerName: failure.providerName,
                            requestPreview: String(text.prefix(100)),
                            statusCode: failure.statusCode,
                            errorMessage: failure.message,
                            durationMs: failure.durationMs,
                            source: "grammar-fallback"
                        ))
                    }
                } else {
                    let providerName = providerIDs.first?.displayName ?? "Grammar provider"
                    aiRequestLogStore.append(AIRequestLogEntry(
                        providerName: providerName,
                        requestPreview: String(text.prefix(100)),
                        statusCode: httpStatus(from: error),
                        errorMessage: error.localizedDescription,
                        durationMs: ms,
                        source: "grammar"
                    ))
                }
                hud.show(.error(error.localizedDescription), autoDismissAfter: 2.5)
            }
        }
    }

    private func httpStatus(from error: Error) -> Int? {
        if case GrammarProviderError.httpError(let status, _) = error { return status }
        return nil
    }

    func setLaunchAtLogin(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    func restartApp() {
        let appPath = Bundle.main.bundleURL.path.replacingOccurrences(of: "'", with: "'\\''")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 0.5; open '\(appPath)'"]
        try? process.run()
        NSApplication.shared.terminate(nil)
    }

    var launchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    var visibleDashboardSections: [DashboardSection] {
        let alwaysVisible: Set<DashboardSection> = [.home, .settings]
        guard !selectedGoals.isEmpty else { return DashboardSection.allCases }
        let goalSections = selectedGoals.reduce(into: alwaysVisible) { result, goal in
            result.formUnion(goal.dashboardSections)
        }
        return DashboardSection.allCases.filter(goalSections.contains)
    }

    func presentOnboarding() {
        showOnboarding = true
    }

    func completeOnboarding(goals: Set<TidyGoal>, localOnlyAI: Bool) {
        let resolvedGoals = goals.isEmpty ? Set(TidyGoal.allCases) : goals
        selectedGoals = resolvedGoals
        let defaults = UserDefaults.standard
        defaults.set(TidyGoal.encode(resolvedGoals), forKey: AppDefaults.selectedGoals)
        defaults.set(localOnlyAI, forKey: AppDefaults.localOnlyAI)
        defaults.set(true, forKey: AppDefaults.didCompleteOnboarding)
        defaults.set(true, forKey: AppDefaults.didCompleteFirstRun)
        showOnboarding = false
        if !visibleDashboardSections.contains(selectedDashboardSection) {
            selectedDashboardSection = .home
        }
        if resolvedGoals.contains(.writing) {
            Permissions.requestAccessibilityIfNeeded()
        }
    }

    func runWorkflow(_ workflow: DeveloperWorkflowID) {
        switch workflow {
        case .startDay, .meetingPrep:
            openUnifiedNotifications()
            Task { await unifiedNotificationService.refresh() }
        case .cleanProject:
            selectedDashboardSection = .fileTidy
        case .shareContext:
            openAskAI()
        case .wrapUp:
            UserDefaults.standard.set("standup", forKey: AppDefaults.jiraWorkspaceMode)
            openJira()
            Task { await refreshJira() }
        }
    }

    func clearAllLocalHistory() {
        clipboardService.clear()
        correctionLogStore.clear()
        aiRequestLogStore.clear()
        unifiedNotificationService.clearCache()
        FileTidyUndoLogStore().clear()
    }

    func disconnectAllIntegrations() {
        KeychainStore.deleteAll()
        let defaults = UserDefaults.standard
        [
            AppDefaults.jiraSiteURL,
            AppDefaults.jiraEmail,
            AppDefaults.jiraProjectKey,
            AppDefaults.jiraAssigneeAccountID,
            AppDefaults.asanaWorkspaceGID,
            AppDefaults.mcpServerURL,
            AppDefaults.slackNotificationChannels
        ].forEach(defaults.removeObject(forKey:))
        defaults.set(0.0, forKey: AppDefaults.asanaTokenExpiresAt)
        defaults.set(false, forKey: AppDefaults.mcpAutoRefreshEnabled)
        jiraService.configurationDidChange()
        asanaService.configurationDidChange()
        unifiedNotificationService.clearCache()
        unifiedNotificationService.configurationDidChange()
        credentialRevision += 1
    }
}
