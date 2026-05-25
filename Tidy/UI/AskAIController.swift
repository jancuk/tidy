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
    @Published var focusRequestID = UUID()
    var codexThreadID: String?
    var codexSessionFolderKey: String?
    var claudeSessionID: String?
    var claudeSessionFolderKey: String?
}

@MainActor
final class AskAIController {
    private let model = AskAIModel()
    private let service = AskAIService()
    private let requestLogStore: AIRequestLogStore
    private var panel: NSPanel?
    private var eventMonitor: Any?
    private var progressTask: Task<Void, Never>?

    init(requestLogStore: AIRequestLogStore) {
        self.requestLogStore = requestLogStore
    }

    func toggle() {
        if panel?.isVisible == true {
            hide()
        } else {
            show()
        }
    }

    func show() {
        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 860, height: 620),
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

            panel.contentView = NSHostingView(rootView: AskAIView(
                model: model,
                submit: { [weak self] in self?.submit() },
                chooseFolder: { [weak self] in self?.chooseFolder() },
                hide: { [weak self] in self?.hide() },
                clear: { [weak self] in self?.clear() }
            ))
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

    private func submit() {
        let question = model.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !model.isLoading else { return }

        syncMentionsFromQuery(question)
        let history = model.messages
        let context = AskAIContext(
            enabledSources: model.enabledSources,
            mcpSources: model.selectedMCPSources,
            folderURLs: model.selectedFolderSources.map(\.url)
        )
        let providerID = currentProviderID
        let folderSessionKey = Self.folderSessionKey(for: context.folderURLs)
        let cliSession = AskAICLISession(
            codexThreadID: providerID == .codexCLI && model.codexSessionFolderKey == folderSessionKey ? model.codexThreadID : nil,
            claudeSessionID: providerID == .claudeCLI && model.claudeSessionFolderKey == folderSessionKey ? model.claudeSessionID : nil
        )
        model.query = ""
        model.errorMessage = nil
        model.messages.append(AskAIMessage(role: .user, content: question))
        model.isLoading = true
        startProgress(for: context)

        Task {
            do {
                let answer = try await service.ask(
                    question,
                    history: history,
                    context: context,
                    logStore: requestLogStore,
                    cliSession: cliSession,
                    progressHandler: { [weak self] message in
                        Task { @MainActor in
                            self?.applyProviderProgress(message)
                        }
                    },
                    sessionUpdateHandler: { [weak self] providerID, sessionID in
                        Task { @MainActor in
                            self?.storeCLISession(providerID: providerID, sessionID: sessionID, folderKey: folderSessionKey)
                        }
                    }
                )
                model.messages.append(AskAIMessage(role: .assistant, content: answer))
            } catch {
                model.errorMessage = error.localizedDescription
                model.messages.append(AskAIMessage(role: .assistant, content: error.localizedDescription))
            }
            stopProgress()
            model.isLoading = false
            model.focusRequestID = UUID()
        }
    }

    private func chooseFolder() {
        let picker = NSOpenPanel()
        picker.title = "Choose Folder for Ask AI"
        picker.canChooseFiles = false
        picker.canChooseDirectories = true
        picker.allowsMultipleSelection = true
        picker.canCreateDirectories = false

        if picker.runModal() == .OK {
            for url in picker.urls {
                let source = AskAIFolderSource(alias: url.lastPathComponent, url: url)
                if !model.folderSources.contains(source) {
                    model.folderSources.append(source)
                }
                if !model.selectedFolderSources.contains(source) {
                    model.selectedFolderSources.append(source)
                }
            }
            if !model.selectedFolderSources.isEmpty {
                model.enabledSources.insert(.folder)
            }
            if case .folder = AskAIMentionParser.currentMention(in: model.query) {
                model.query = AskAIMentionParser.removingCurrentMention(in: model.query)
            }
        }
    }

    private func clear() {
        stopProgress()
        model.messages.removeAll()
        model.query = ""
        model.errorMessage = nil
        model.codexThreadID = nil
        model.codexSessionFolderKey = nil
        model.claudeSessionID = nil
        model.claudeSessionFolderKey = nil
        model.focusRequestID = UUID()
    }

    private func startProgress(for context: AskAIContext) {
        stopProgress()

        let providerID = GrammarProviderID(rawValue: UserDefaults.standard.string(forKey: AppDefaults.grammarProvider) ?? "") ?? .gemini
        let steps = AskAIProgressSteps.steps(for: providerID, context: context)
        model.progressDescription = steps.first ?? "\(providerID.displayName) is working on it"

        progressTask = Task { [weak self] in
            guard steps.count > 1 else { return }
            var index = 1
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, self.model.isLoading else { return }
                    self.model.progressDescription = steps[min(index, steps.count - 1)]
                }
                if index < steps.count - 1 {
                    index += 1
                }
            }
        }
    }

    private func stopProgress() {
        progressTask?.cancel()
        progressTask = nil
        model.progressDescription = ""
    }

    private func applyProviderProgress(_ message: String) {
        guard model.isLoading else { return }
        progressTask?.cancel()
        progressTask = nil
        model.progressDescription = message
    }

    private func storeCLISession(providerID: GrammarProviderID, sessionID: String, folderKey: String) {
        switch providerID {
        case .codexCLI:
            model.codexThreadID = sessionID
            model.codexSessionFolderKey = folderKey
        case .claudeCLI:
            model.claudeSessionID = sessionID
            model.claudeSessionFolderKey = folderKey
        case .gemini, .openAI, .anthropic, .languageTool, .openCode, .ollama:
            break
        }
    }

    private func syncMentionsFromQuery(_ query: String) {
        let typedMCP = AskAIMentionParser.mcpSources(in: query)
        if !typedMCP.isEmpty {
            model.selectedMCPSources.formUnion(typedMCP)
        }

        let typedFolders = AskAIMentionParser.folderSources(in: query, availableFolders: model.folderSources)
        for folder in typedFolders where !model.selectedFolderSources.contains(folder) {
            model.selectedFolderSources.append(folder)
        }

        if !model.selectedFolderSources.isEmpty {
            model.enabledSources.insert(.folder)
        }
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
            case kVK_Return where commandPressed,
                 kVK_ANSI_KeypadEnter where commandPressed:
                self.submit()
                return nil
            default:
                return event
            }
        }
    }

    private var currentProviderID: GrammarProviderID {
        GrammarProviderID(rawValue: UserDefaults.standard.string(forKey: AppDefaults.grammarProvider) ?? "") ?? .gemini
    }

    private static func folderSessionKey(for urls: [URL]) -> String {
        urls
            .map { $0.standardizedFileURL.path }
            .sorted()
            .joined(separator: "\n")
    }
}

struct AskAIView: View {
    @ObservedObject var model: AskAIModel
    let submit: () -> Void
    let chooseFolder: () -> Void
    let hide: () -> Void
    let clear: () -> Void

    @AppStorage(AppDefaults.grammarProvider) private var grammarProvider = GrammarProviderID.gemini.rawValue
    @FocusState private var inputFocused: Bool

    private var visibleMCPSources: Set<AskAIMCPSource> {
        model.selectedMCPSources.union(AskAIMentionParser.mcpSources(in: model.query))
    }

    private var visibleFolderSources: [AskAIFolderSource] {
        var sources = model.selectedFolderSources
        let typedFolders = AskAIMentionParser.folderSources(in: model.query, availableFolders: model.folderSources)
        for folder in typedFolders where !sources.contains(folder) {
            sources.append(folder)
        }
        return sources
    }

    var body: some View {
        ZStack {
            AskAIVisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
            VStack(spacing: 0) {
                header
                Divider()
                if !model.selectedFolderSources.isEmpty {
                    selectedFolderBar
                    Divider()
                }
                if mentionMode != nil {
                    mentionSuggestions
                    Divider()
                }
                messageArea
                Divider()
                footer
            }
        }
        .frame(minWidth: 760, minHeight: 540)
        .onAppear {
            inputFocused = true
        }
        .onChange(of: model.focusRequestID) { _, _ in
            inputFocused = true
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: hide) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(Color(NSColor.controlColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Close")

            Text(model.messages.isEmpty ? "Ask AI anything..." : "Ask Follow-up")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(model.messages.isEmpty ? Color(NSColor.placeholderTextColor) : Color(NSColor.labelColor))

            Spacer()

            Text(providerName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(NSColor.secondaryLabelColor))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor), in: Capsule())

            Button(action: clear) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .background(Color(NSColor.controlColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("New chat")
            .disabled(model.messages.isEmpty && model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 70)
    }

    private var mentionMode: AskAIMentionMode? {
        AskAIMentionParser.currentMention(in: model.query)
    }

    private var selectedFolderBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.selectedFolderSources) { source in
                    Button {
                        removeFolder(source)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "folder")
                                .font(.system(size: 12, weight: .semibold))
                            Text(source.alias)
                                .font(.system(size: 12, weight: .semibold))
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color(NSColor.secondaryLabelColor))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.16), in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.accentColor.opacity(0.35), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .help(source.url.path)
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 42)
    }

    @ViewBuilder
    private var mentionSuggestions: some View {
        switch mentionMode {
        case .mcp(let filter):
            suggestionList(
                title: "MCP sources",
                rows: filteredMCPSources(filter).map { source in
                    MentionSuggestionRow(
                        id: source.id,
                        title: source.mention,
                        subtitle: source.title,
                        systemImage: source.systemImage,
                        isSelected: visibleMCPSources.contains(source),
                        action: {
                            model.selectedMCPSources.insert(source)
                            replaceCurrentMention(with: source.mention)
                        }
                    )
                }
            )
        case .folder(let filter):
            suggestionList(
                title: "Folders",
                rows: folderSuggestionRows(filter)
            )
        case nil:
            EmptyView()
        }
    }

    private func folderSuggestionRows(_ filter: String) -> [MentionSuggestionRow] {
        var rows = filteredFolderSources(filter).map { source in
            MentionSuggestionRow(
                id: source.id,
                title: source.mention,
                subtitle: source.url.path,
                systemImage: "folder",
                isSelected: visibleFolderSources.contains(source),
                action: {
                    if model.selectedFolderSources.contains(source) {
                        removeFolder(source)
                    } else {
                        addFolder(source)
                    }
                    replaceCurrentMention(with: source.mention)
                }
            )
        }

        rows.append(
            MentionSuggestionRow(
                id: "choose-folder",
                title: "Choose folders...",
                subtitle: "Select one or more directories",
                systemImage: "folder.badge.plus",
                isSelected: false,
                action: chooseFolder
            )
        )

        if rows.count == 1 {
            rows.insert(
                MentionSuggestionRow(
                    id: "no-folders",
                    title: "No folders selected",
                    subtitle: "Choose folders first to make them available here",
                    systemImage: "folder",
                    isSelected: false,
                    action: chooseFolder
                ),
                at: 0
            )
        }

        return rows
    }

    private func suggestionList(title: String, rows: [MentionSuggestionRow]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color(NSColor.secondaryLabelColor))
                .textCase(.uppercase)

            ForEach(rows) { row in
                Button(action: row.action) {
                    HStack(spacing: 10) {
                        Image(systemName: row.systemImage)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(row.isSelected ? Color.accentColor : Color(NSColor.secondaryLabelColor))
                            .frame(width: 22)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title)
                                .font(.system(size: 13, weight: .semibold, design: row.title.hasPrefix("@") ? .monospaced : .default))
                                .foregroundStyle(Color(NSColor.labelColor))
                            Text(row.subtitle)
                                .font(.system(size: 11))
                                .foregroundStyle(Color(NSColor.secondaryLabelColor))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer()

                        if row.isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var messageArea: some View {
        Group {
            if model.messages.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(model.messages) { message in
                                AskAIMessageBubble(message: message)
                                    .id(message.id)
                            }

                            if model.isLoading {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text(model.progressDescription.isEmpty ? "\(providerName) is working on it" : model.progressDescription)
                                        .foregroundStyle(Color(NSColor.secondaryLabelColor))
                                }
                                .font(.system(size: 13))
                                .padding(.horizontal, 18)
                                .padding(.bottom, 8)
                            }
                        }
                        .padding(18)
                    }
                    .onChange(of: model.messages.count) { _, _ in
                        if let lastID = model.messages.last?.id {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()
            VStack(spacing: 8) {
                Text("Ask Anything")
                    .font(.system(size: 30, weight: .bold))
                Text("Type @ for MCP or @! for folders")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
            }
            Spacer()
        }
    }

    private var footer: some View {
        HStack(alignment: .bottom, spacing: 12) {
            Label("Quick AI", systemImage: "sparkles")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(NSColor.secondaryLabelColor))
                .padding(.bottom, 8)

            Button(action: clear) {
                Label("New chat", systemImage: "plus.message")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(model.messages.isEmpty && model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .padding(.bottom, 4)

            TextField(model.messages.isEmpty ? "Ask AI anything..." : "Ask follow-up...", text: $model.query, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .lineLimit(1...5)
                .focused($inputFocused)
                .onSubmit(submit)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color(NSColor.textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color(NSColor.separatorColor).opacity(0.75), lineWidth: 0.5)
                )

            if let error = model.errorMessage {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.red)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.bottom, 8)
            }

            Button(action: submit) {
                Label(model.messages.isEmpty ? "Ask AI" : "Ask Follow-up", systemImage: "return")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isLoading)
            .padding(.bottom, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 66)
    }

    private func filteredMCPSources(_ filter: String) -> [AskAIMCPSource] {
        let needle = filter.lowercased()
        guard !needle.isEmpty else { return AskAIMCPSource.allCases }
        return AskAIMCPSource.allCases.filter {
            $0.rawValue.lowercased().contains(needle) || $0.title.lowercased().contains(needle)
        }
    }

    private func filteredFolderSources(_ filter: String) -> [AskAIFolderSource] {
        let needle = filter.lowercased()
        guard !needle.isEmpty else { return model.folderSources }
        return model.folderSources.filter {
            $0.alias.lowercased().contains(needle) || $0.url.path.lowercased().contains(needle)
        }
    }

    private func replaceCurrentMention(with mention: String) {
        model.query = AskAIMentionParser.replacingCurrentMention(in: model.query, with: mention)
        inputFocused = true
    }

    private func addFolder(_ source: AskAIFolderSource) {
        if !model.folderSources.contains(source) {
            model.folderSources.append(source)
        }
        if !model.selectedFolderSources.contains(source) {
            model.selectedFolderSources.append(source)
        }
        model.enabledSources.insert(.folder)
    }

    private func removeFolder(_ source: AskAIFolderSource) {
        model.selectedFolderSources.removeAll { $0 == source }
        if model.selectedFolderSources.isEmpty {
            model.enabledSources.remove(.folder)
        }
    }

    private var providerName: String {
        (GrammarProviderID(rawValue: grammarProvider) ?? .gemini).displayName
    }
}

private struct MentionSuggestionRow: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void
}

private enum AskAIProgressSteps {
    static func steps(for providerID: GrammarProviderID, context: AskAIContext) -> [String] {
        let hasFolders = !context.folderURLs.isEmpty
        let folderLabel = context.folderURLs.count == 1 ? "selected folder" : "selected folders"

        switch providerID {
        case .codexCLI:
            return hasFolders ? [
                "Starting Codex CLI in read-only mode",
                "Codex CLI is opening the \(folderLabel)",
                "Codex CLI is inspecting relevant files",
                "Codex CLI is connecting the repo context",
                "Codex CLI is drafting the answer"
            ] : [
                "Starting Codex CLI in read-only mode",
                "Codex CLI is reading the question",
                "Codex CLI is drafting the answer"
            ]
        case .claudeCLI:
            return hasFolders ? [
                "Starting Claude Code in read-only mode",
                "Claude Code is opening the \(folderLabel)",
                "Claude Code is inspecting relevant files",
                "Claude Code is connecting the repo context",
                "Claude Code is drafting the answer"
            ] : [
                "Starting Claude Code",
                "Claude Code is reading the question",
                "Claude Code is drafting the answer"
            ]
        case .gemini, .openAI, .anthropic, .openCode, .ollama:
            let name = providerID.displayName
            return hasFolders ? [
                "Preparing local folder context",
                "Reading relevant files from the \(folderLabel)",
                "Sending context to \(name)",
                "\(name) is working through the answer",
                "Formatting the response"
            ] : [
                "Sending the question to \(name)",
                "\(name) is working through the answer",
                "Formatting the response"
            ]
        case .languageTool:
            return ["Preparing local grammar request"]
        }
    }
}

private struct AskAIMessageBubble: View {
    let message: AskAIMessage
    @State private var didCopy = false

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 80)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(message.role == .user ? "You" : "Tidy")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color(NSColor.secondaryLabelColor))
                        .textCase(.uppercase)

                    Spacer(minLength: 8)

                    if message.role == .assistant {
                        Button(action: copyResponse) {
                            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(didCopy ? Color.green : Color(NSColor.secondaryLabelColor))
                                .frame(width: 24, height: 24)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(didCopy ? "Copied" : "Copy response")
                    }
                }

                MarkdownText(message.content)
                    .font(.system(size: 14))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: 620, alignment: .leading)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(NSColor.separatorColor).opacity(0.65), lineWidth: message.role == .assistant ? 0.5 : 0)
            )

            if message.role == .assistant {
                Spacer(minLength: 80)
            }
        }
    }

    private var backgroundColor: Color {
        message.role == .user
            ? Color.accentColor.opacity(0.18)
            : Color(NSColor.controlBackgroundColor)
    }

    private func copyResponse() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.content, forType: .string)
        didCopy = true

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            didCopy = false
        }
    }
}

private struct MarkdownText: View {
    let content: String

    init(_ content: String) {
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(MarkdownBlock.blocks(from: content).enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inlineMarkdown(text))
                .font(.system(size: level == 1 ? 18 : 16, weight: .semibold))
                .foregroundStyle(Color(NSColor.labelColor))
                .padding(.top, level == 1 ? 2 : 1)
        case .paragraph(let text):
            Text(inlineMarkdown(text))
                .lineSpacing(3)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text("•")
                            .font(.system(size: 13, weight: .semibold))
                        Text(inlineMarkdown(item))
                            .lineSpacing(3)
                    }
                }
            }
        case .numbered(let items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text("\(index + 1).")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .frame(minWidth: 20, alignment: .trailing)
                        Text(inlineMarkdown(item))
                            .lineSpacing(3)
                    }
                }
            }
        case .code(let text):
            ScrollView(.horizontal, showsIndicators: true) {
                Text(text)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(NSColor.textBackgroundColor), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color(NSColor.separatorColor).opacity(0.7), lineWidth: 0.5)
            )
        case .rule:
            Divider()
                .padding(.vertical, 2)
        }
    }

    private func inlineMarkdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}

private enum MarkdownBlock {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullets([String])
    case numbered([String])
    case code(String)
    case rule

    static func blocks(from content: String) -> [MarkdownBlock] {
        let lines = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")

        var blocks: [MarkdownBlock] = []
        var paragraphLines: [String] = []
        var bulletItems: [String] = []
        var numberedItems: [String] = []
        var codeLines: [String] = []
        var looseCodeLines: [String] = []
        var isInsideFence = false

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            blocks.append(.paragraph(paragraphLines.joined(separator: " ")))
            paragraphLines.removeAll()
        }

        func flushBullets() {
            guard !bulletItems.isEmpty else { return }
            blocks.append(.bullets(bulletItems))
            bulletItems.removeAll()
        }

        func flushNumbered() {
            guard !numberedItems.isEmpty else { return }
            blocks.append(.numbered(numberedItems))
            numberedItems.removeAll()
        }

        func flushLooseCode() {
            guard !looseCodeLines.isEmpty else { return }
            blocks.append(.code(looseCodeLines.joined(separator: "\n")))
            looseCodeLines.removeAll()
        }

        func flushAllTextBlocks() {
            flushParagraph()
            flushBullets()
            flushNumbered()
            flushLooseCode()
        }

        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                flushAllTextBlocks()
                if isInsideFence {
                    blocks.append(.code(codeLines.joined(separator: "\n")))
                    codeLines.removeAll()
                    isInsideFence = false
                } else {
                    isInsideFence = true
                }
                continue
            }

            if isInsideFence {
                codeLines.append(rawLine)
                continue
            }

            if trimmed.isEmpty {
                flushAllTextBlocks()
                continue
            }

            if isRule(trimmed) {
                flushAllTextBlocks()
                blocks.append(.rule)
                continue
            }

            if isLooseCodeLine(rawLine) {
                flushParagraph()
                flushBullets()
                flushNumbered()
                looseCodeLines.append(rawLine)
                continue
            }

            if let heading = heading(from: trimmed) {
                flushAllTextBlocks()
                blocks.append(.heading(level: heading.level, text: heading.text))
                continue
            }

            if let bullet = bulletText(from: trimmed) {
                flushParagraph()
                flushNumbered()
                flushLooseCode()
                bulletItems.append(bullet)
                continue
            }

            if let numbered = numberedText(from: trimmed) {
                flushParagraph()
                flushBullets()
                flushLooseCode()
                numberedItems.append(numbered)
                continue
            }

            flushBullets()
            flushNumbered()
            flushLooseCode()
            paragraphLines.append(trimmed)
        }

        if isInsideFence, !codeLines.isEmpty {
            blocks.append(.code(codeLines.joined(separator: "\n")))
        }
        flushAllTextBlocks()
        return blocks.isEmpty ? [.paragraph(content)] : blocks
    }

    private static func heading(from line: String) -> (level: Int, text: String)? {
        let markers = line.prefix { $0 == "#" }
        guard !markers.isEmpty, markers.count <= 6 else { return nil }
        let text = line.dropFirst(markers.count).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return (markers.count, text)
    }

    private static func bulletText(from line: String) -> String? {
        guard line.count > 2 else { return nil }
        let first = line[line.startIndex]
        guard ["-", "*", "+"].contains(first) else { return nil }
        let second = line[line.index(after: line.startIndex)]
        guard second.isWhitespace else { return nil }
        return String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)
    }

    private static func numberedText(from line: String) -> String? {
        var index = line.startIndex
        guard line[index].isNumber else { return nil }
        while index < line.endIndex, line[index].isNumber {
            index = line.index(after: index)
        }
        guard index < line.endIndex, [".", ")"].contains(line[index]) else { return nil }
        let separatorIndex = line.index(after: index)
        guard separatorIndex < line.endIndex, line[separatorIndex].isWhitespace else { return nil }
        return String(line[line.index(after: separatorIndex)...]).trimmingCharacters(in: .whitespaces)
    }

    private static func isRule(_ line: String) -> Bool {
        line.count >= 3 && Set(line).isSubset(of: ["-", "_", "*"])
    }

    private static func isLooseCodeLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return line.hasPrefix("    ")
            || line.hasPrefix("\t")
            || trimmed.hasPrefix("├")
            || trimmed.hasPrefix("└")
            || trimmed.hasPrefix("│")
            || trimmed.hasPrefix("|--")
            || trimmed.hasPrefix("`--")
    }
}

private struct AskAIVisualEffectView: NSViewRepresentable {
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
