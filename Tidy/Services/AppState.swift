import AppKit
import Combine
import ServiceManagement

@MainActor
final class AppState: ObservableObject {
    let clipboardService: ClipboardService
    let correctionLogStore: CorrectionLogStore
    let aiRequestLogStore: AIRequestLogStore
    let suggestionMonitor: SuggestionMonitor

    private let hotkeyManager = HotkeyManager()
    private let hud = HUDController()
    private let grammarService: GrammarService
    private let paletteController: ClipboardPaletteController
    private let askAIController: AskAIController
    private let suggestionPopup = SuggestionPopupController()
    private var cancellables: Set<AnyCancellable> = []

    init() {
        UserDefaults.standard.registerTidyDefaults()
        clipboardService = ClipboardService()
        correctionLogStore = CorrectionLogStore()
        aiRequestLogStore = AIRequestLogStore()
        grammarService = GrammarService(hud: hud, logStore: correctionLogStore, requestLogStore: aiRequestLogStore)
        paletteController = ClipboardPaletteController(clipboardService: clipboardService)
        askAIController = AskAIController(requestLogStore: aiRequestLogStore)
        suggestionMonitor = SuggestionMonitor()

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
        registerHotkeys()
        if !UserDefaults.standard.bool(forKey: AppDefaults.didCompleteFirstRun) {
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

    func tidyClipboardText() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            hud.show(.warning("Clipboard is empty"), autoDismissAfter: 1.2)
            return
        }

        hud.show(.loading("Tidying clipboard..."))
        Task {
            let providerID = GrammarProviderID(rawValue: UserDefaults.standard.string(forKey: AppDefaults.grammarProvider) ?? "") ?? .gemini
            let provider = GrammarProviderFactory.provider(for: providerID)
            let start = Date()
            do {
                let corrected = try await provider.fixGrammar(text, language: nil)
                let ms = Int(Date().timeIntervalSince(start) * 1000)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(corrected, forType: .string)
                correctionLogStore.append(original: text, corrected: corrected, providerID: providerID.rawValue)
                aiRequestLogStore.append(AIRequestLogEntry(
                    providerName: provider.displayName,
                    requestPreview: String(text.prefix(100)),
                    durationMs: ms,
                    source: "grammar"
                ))
                hud.show(.success("Clipboard tidied"), autoDismissAfter: 1)
            } catch {
                let ms = Int(Date().timeIntervalSince(start) * 1000)
                aiRequestLogStore.append(AIRequestLogEntry(
                    providerName: provider.displayName,
                    requestPreview: String(text.prefix(100)),
                    statusCode: httpStatus(from: error),
                    errorMessage: error.localizedDescription,
                    durationMs: ms,
                    source: "grammar"
                ))
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
}
