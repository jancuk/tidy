import AppKit
import Carbon
import SwiftUI

@MainActor
final class AskAIModel: ObservableObject {
    @Published var query = ""
    @Published var messages: [AskAIMessage] = []
    @Published var enabledSources: Set<AskAISource> = []
    @Published var selectedMCPSources: Set<AskAIMCPSource> = []
    @Published var folderSources: [AskAIFolderSource] = []
    @Published var selectedFolderSources: [AskAIFolderSource] = []
    @Published var isLoading = false
    @Published var progressDescription = ""
    @Published var errorMessage: String?
    @Published var storageError: String?
    @Published var notice: String?
    @Published var focusRequestID = UUID()
    @Published var conversationID = UUID()
    @Published var title = "New chat"
    @Published var isTemporary = false
    @Published var editingMessageID: UUID?
    @Published var providerID = (GrammarProviderID(rawValue: UserDefaults.standard.string(forKey: AppDefaults.grammarProvider) ?? "") ?? .gemini).chatProvider
    var codexThreadID: String?
    var codexSessionFolderKey: String?
    var claudeSessionID: String?
    var claudeSessionFolderKey: String?
}

struct AskAIRequest {
    let question: String
    let history: [AskAIMessage]
    let context: AskAIContext
    let providerID: GrammarProviderID
    let cliSession: AskAICLISession
    let isTemporary: Bool
    let progress: (String) -> Void
    let sessionUpdate: (GrammarProviderID, String) -> Void
}

@MainActor
final class AskAIController {
    typealias Responder = (AskAIRequest) async throws -> String
    let model = AskAIModel()
    let conversations: AskAIConversationStore
    private let respond: Responder
    private var panel: NSPanel?
    private var eventMonitor: Any?
    private var requestTask: Task<Void, Never>?
    private var requestID = UUID()
    private var drafts: [UUID: String] = [:]
    private var activeProvider: GrammarProviderID?
    private var excludedMCPSources: Set<AskAIMCPSource> = []
    private var excludedFolderIDs: Set<String> = []

    init(requestLogStore: AIRequestLogStore, conversations: AskAIConversationStore? = nil, responder: Responder? = nil) {
        self.conversations = conversations ?? AskAIConversationStore()
        self.respond = responder ?? { request in
            try await AskAIService().ask(request.question, history: request.history, context: request.context,
                                        logStore: requestLogStore, cliSession: request.cliSession, providerID: request.providerID,
                                        isTemporary: request.isTemporary,
                                        progressHandler: request.progress, sessionUpdateHandler: request.sessionUpdate)
        }
    }

    func toggle() { if panel?.isVisible == true { hide() } else { show() } }

    func show(contextText: String) {
        guard newConversation() else { show(); return }
        model.query = "Help me with this text:\n\n" + contextText
        show()
    }

    func show() {
        if panel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 1060, height: 760),
                                styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            panel.title = "Ask AI — Tidy"
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isReleasedWhenClosed = false
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentMinSize = NSSize(width: 760, height: 560)
            panel.setFrameAutosaveName("TidyAskAIWorkspace")
            panel.contentView = NSHostingView(rootView: AskAIView(model: model, store: conversations, controller: self))
            if let screen = NSScreen.main {
                let size = NSSize(width: min(panel.frame.width, screen.visibleFrame.width), height: min(panel.frame.height, screen.visibleFrame.height))
                panel.setContentSize(size)
            }
            panel.center()
            self.panel = panel
        }
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate()
        model.focusRequestID = UUID()
        installEventMonitor()
    }

    func hide() {
        panel?.orderOut(nil)
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor); self.eventMonitor = nil }
    }

    @discardableResult
    func submit() -> Task<Void, Never>? {
        let question = model.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !model.isLoading else { return nil }
        guard question.count <= 100_000 else { model.errorMessage = "Use up to 100,000 characters per message."; return nil }
        if let editingID = model.editingMessageID, let index = model.messages.firstIndex(where: { $0.id == editingID }) {
            model.messages = Array(model.messages.prefix(index))
            resetCLISessions()
        }
        model.editingMessageID = nil
        syncMentionsFromQuery(question)
        let history = model.messages
        model.query = ""
        let contextLabels = model.selectedFolderSources.map(\.alias) + model.selectedMCPSources.map(\.title).sorted()
        model.messages.append(AskAIMessage(role: .user, content: question, contextLabels: contextLabels))
        if history.isEmpty { model.title = String(question.components(separatedBy: .newlines).first?.prefix(70) ?? question.prefix(70)) }
        saveCurrent()
        return request(question: question, history: history)
    }

    @discardableResult
    func retry() -> Task<Void, Never>? {
        guard !model.isLoading, let index = model.messages.lastIndex(where: { $0.role == .user }) else { return nil }
        resetCLISessions()
        let question = model.messages[index].content
        // Keep the previous answer visible until its replacement succeeds.
        return request(question: question, history: Array(model.messages.prefix(index)), replaceAfter: index)
    }

    private func request(question: String, history: [AskAIMessage], replaceAfter: Int? = nil) -> Task<Void, Never> {
        let id = UUID()
        requestID = id
        model.errorMessage = nil
        model.notice = nil
        model.isLoading = true
        let context = AskAIContext(enabledSources: model.enabledSources, mcpSources: model.selectedMCPSources,
                                   folderURLs: model.selectedFolderSources.map(\.url))
        let provider = currentProviderID
        activeProvider = provider
        let folderKey = context.folderURLs.map { $0.standardizedFileURL.path }.sorted().joined(separator: "\n")
        let session = AskAICLISession(codexThreadID: model.codexSessionFolderKey == folderKey ? model.codexThreadID : nil,
                                      claudeSessionID: model.claudeSessionFolderKey == folderKey ? model.claudeSessionID : nil)
        model.progressDescription = "Waiting for \(provider.displayName)…"
        let request = AskAIRequest(question: question, history: history, context: context, providerID: provider, cliSession: session,
            isTemporary: model.isTemporary,
            progress: { [weak self] message in
                Task { @MainActor in
                    guard let self, self.requestID == id, self.model.isLoading else { return }
                    self.model.progressDescription = message
                }
            }, sessionUpdate: { [weak self] provider, sessionID in
                Task { @MainActor in
                    guard let self, self.requestID == id, self.model.isLoading else { return }
                    if provider == .codexCLI { self.model.codexThreadID = sessionID; self.model.codexSessionFolderKey = folderKey }
                    if provider == .claudeCLI { self.model.claudeSessionID = sessionID; self.model.claudeSessionFolderKey = folderKey }
                }
            })
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let answer = try await respond(request)
                guard requestID == id, !Task.isCancelled else { return }
                guard !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AskAIError.emptyAnswer }
                if let replaceAfter { model.messages = Array(model.messages.prefix(replaceAfter + 1)) }
                model.messages.append(AskAIMessage(role: .assistant, content: answer, providerName: provider.displayName))
                saveCurrent()
            } catch {
                guard requestID == id, !Task.isCancelled else { return }
                model.errorMessage = error.localizedDescription
            }
            guard requestID == id else { return }
            model.isLoading = false
            model.progressDescription = ""
            model.focusRequestID = UUID()
        }
        requestTask = task
        return task
    }

    func stop() {
        let wasLoading = model.isLoading
        requestID = UUID()
        requestTask?.cancel()
        requestTask = nil
        model.isLoading = false
        model.progressDescription = ""
        resetCLISessions()
        if wasLoading {
            model.notice = activeProvider == .codexCLI || activeProvider == .claudeCLI
                ? "Stopped waiting. The CLI process may continue until its timeout; further output will be ignored."
                : "Response stopped. Retry whenever you’re ready."
        }
    }

    func edit(_ message: AskAIMessage) {
        guard !model.isLoading, message.role == .user else { return }
        model.editingMessageID = message.id
        model.query = message.content
        model.focusRequestID = UUID()
    }

    func cancelEdit() { model.editingMessageID = nil; model.query = "" }

    func providerChanged() { resetCLISessions() }

    func removeContext(_ source: AskAIMCPSource) {
        model.selectedMCPSources.remove(source)
        excludedMCPSources.insert(source)
    }

    func removeContext(_ source: AskAIFolderSource) {
        model.selectedFolderSources.removeAll { $0 == source }
        excludedFolderIDs.insert(source.id)
        if model.selectedFolderSources.isEmpty { model.enabledSources.remove(.folder) }
    }

    func addContext(_ source: AskAIMCPSource) {
        excludedMCPSources.remove(source)
        model.selectedMCPSources.insert(source)
    }

    func addContext(_ source: AskAIFolderSource) {
        excludedFolderIDs.remove(source.id)
        if !model.selectedFolderSources.contains(source) { model.selectedFolderSources.append(source) }
        model.enabledSources.insert(.folder)
    }

    @discardableResult
    func newConversation(temporary: Bool = false) -> Bool {
        guard saveCurrent() else { return false }
        stop()
        reset()
        model.conversationID = UUID()
        model.title = "New chat"
        model.isTemporary = temporary
        return true
    }

    func select(_ conversation: AskAIConversation) {
        guard conversation.id != model.conversationID, saveCurrent() else { return }
        drafts[model.conversationID] = model.query
        stop()
        reset()
        model.conversationID = conversation.id
        model.title = conversation.title
        model.messages = conversation.messages
        model.query = drafts[conversation.id] ?? ""
        model.isTemporary = false
    }

    func delete(_ conversation: AskAIConversation) {
        do {
            try conversations.delete(conversation.id)
            drafts[conversation.id] = nil
            if conversation.id == model.conversationID { stop(); reset(); model.conversationID = UUID(); model.title = "New chat" }
        } catch { model.storageError = error.localizedDescription }
    }

    func rename(_ conversation: AskAIConversation, title: String) {
        do {
            try conversations.rename(conversation.id, title: title)
            if let updated = conversations.conversations.first(where: { $0.id == model.conversationID }) { model.title = updated.title }
        } catch { model.storageError = error.localizedDescription }
    }

    @discardableResult
    func clearHistory() -> Bool {
        do {
            try conversations.clear()
            stop(); reset(); drafts.removeAll()
            model.conversationID = UUID(); model.title = "New chat"; model.isTemporary = false
            return true
        }
        catch { model.storageError = error.localizedDescription; return false }
    }

    func exportConversation() {
        guard !model.messages.isEmpty else { return }
        let picker = NSSavePanel()
        picker.nameFieldStringValue = "Tidy conversation.md"
        guard picker.runModal() == .OK, let url = picker.url else { return }
        do { try transcript.markdown.write(to: url, atomically: true, encoding: .utf8) }
        catch { model.errorMessage = "Export failed: \(error.localizedDescription)" }
    }

    var transcript: AskAIConversation { AskAIConversation(id: model.conversationID, title: model.title, messages: model.messages) }

    @discardableResult
    private func saveCurrent() -> Bool {
        guard !model.isTemporary, !model.messages.isEmpty else { return true }
        do { try conversations.save(transcript); model.storageError = nil; return true }
        catch { model.storageError = "This chat could not be saved. Export it before leaving. \(error.localizedDescription)"; return false }
    }

    private func reset() {
        model.messages = []; model.query = ""; model.errorMessage = nil; model.notice = nil; model.storageError = nil
        model.enabledSources = []; model.selectedMCPSources = []; model.selectedFolderSources = []
        model.folderSources = []; model.editingMessageID = nil
        excludedMCPSources = []; excludedFolderIDs = []
        model.focusRequestID = UUID()
        resetCLISessions()
    }

    private func resetCLISessions() {
        model.codexThreadID = nil; model.codexSessionFolderKey = nil
        model.claudeSessionID = nil; model.claudeSessionFolderKey = nil
    }

    func chooseFolder() {
        guard !model.isLoading else { return }
        let picker = NSOpenPanel()
        picker.title = "Add folders to this chat"
        picker.canChooseFiles = false; picker.canChooseDirectories = true; picker.allowsMultipleSelection = true
        picker.canCreateDirectories = false
        guard picker.runModal() == .OK else { return }
        for url in picker.urls {
            guard FolderAccessPolicy.allowsExplicitInspection(of: url) else {
                model.errorMessage = "Choose a project or working folder instead of your entire home or Library folder."
                continue
            }
            let source = AskAIFolderSource(alias: url.lastPathComponent, url: url)
            if !model.folderSources.contains(source) { model.folderSources.append(source) }
            addContext(source)
        }
        if !model.selectedFolderSources.isEmpty { model.enabledSources.insert(.folder) }
        if case .folder = AskAIMentionParser.currentMention(in: model.query) {
            model.query = AskAIMentionParser.removingCurrentMention(in: model.query)
        }
        model.focusRequestID = UUID()
    }

    private func syncMentionsFromQuery(_ query: String) {
        model.selectedMCPSources.formUnion(AskAIMentionParser.mcpSources(in: query).subtracting(excludedMCPSources))
        for folder in AskAIMentionParser.folderSources(in: query, availableFolders: model.folderSources)
            where !excludedFolderIDs.contains(folder.id) && !model.selectedFolderSources.contains(folder) { model.selectedFolderSources.append(folder) }
        if !model.selectedFolderSources.isEmpty { model.enabledSources.insert(.folder) }
    }

    private func installEventMonitor() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, panel?.isKeyWindow == true else { return event }
            if event.keyCode == kVK_Escape { hide(); return nil }
            if event.modifierFlags.contains(.command), event.keyCode == kVK_ANSI_N { newConversation(); return nil }
            return event
        }
    }

    private var currentProviderID: GrammarProviderID {
        model.providerID
    }
}
