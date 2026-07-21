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
        case .gemini, .openAI, .anthropic, .deepSeek, .languageTool, .openCode, .ollama:
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
            AskAIVisualEffectView(material: .sidebar, blendingMode: .behindWindow)
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

    // MARK: - Header

    private var header: some View {
        ZStack {
            // Centered title stack
            VStack(spacing: 2) {
                Text("Ask AI")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(NSColor.labelColor))
                Text(providerName)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
            }

            HStack(spacing: 0) {
                // Back / close
                Button(action: hide) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Close (Esc)")

                Spacer()

                // New conversation
                Button(action: clear) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 17))
                        .foregroundStyle(
                            model.messages.isEmpty && model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? Color(NSColor.tertiaryLabelColor)
                                : Color.accentColor
                        )
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("New Conversation")
                .disabled(model.messages.isEmpty && model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, 4)
        .frame(height: 52)
    }

    // MARK: - Folder / Mention bars

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
                        HStack(spacing: 5) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 11, weight: .semibold))
                            Text(source.alias)
                                .font(.system(size: 12, weight: .medium))
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color(NSColor.secondaryLabelColor))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                        .overlay(Capsule().stroke(Color.accentColor.opacity(0.25), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .help(source.url.path)
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 40)
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
                title: "Choose folders…",
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
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color(NSColor.secondaryLabelColor))
                .textCase(.uppercase)
                .padding(.horizontal, 4)

            ForEach(rows) { row in
                Button(action: row.action) {
                    HStack(spacing: 10) {
                        Image(systemName: row.systemImage)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(row.isSelected ? Color.accentColor : Color(NSColor.secondaryLabelColor))
                            .frame(width: 22)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title)
                                .font(.system(size: 13, weight: .medium, design: row.title.hasPrefix("@") ? .monospaced : .default))
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
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.7), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Message area

    private var messageArea: some View {
        Group {
            if model.messages.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(model.messages) { message in
                                AskAIMessageBubble(message: message)
                                    .id(message.id)
                            }

                            if model.isLoading {
                                loadingBubble
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 20)
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

    private var loadingBubble: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // AI avatar
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 26, height: 26)

            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                if !model.progressDescription.isEmpty {
                    Text(model.progressDescription)
                        .font(.system(size: 14))
                        .foregroundStyle(Color(NSColor.secondaryLabelColor))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5)
            )

            Spacer(minLength: 80)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 72, height: 72)
                Image(systemName: "sparkles")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(spacing: 8) {
                Text("Ask Anything")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Color(NSColor.labelColor))
                Text("Type @ to include MCP or folder context")
                    .font(.system(size: 15))
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 0) {
            if let error = model.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.06))
            }

            ZStack(alignment: .bottomTrailing) {
                TextField(
                    model.messages.isEmpty ? "Message…" : "Reply…",
                    text: $model.query,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .lineLimit(1...6)
                .focused($inputFocused)
                .onSubmit(submit)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .padding(.trailing, 48)

                Button(action: submit) {
                    ZStack {
                        Circle()
                            .fill(sendButtonColor)
                        Image(systemName: "arrow.up")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .disabled(model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isLoading)
                .padding(.trailing, 10)
                .padding(.bottom, 8)
                .animation(.easeInOut(duration: 0.15), value: model.query.isEmpty)
            }
            .background(
                Color(NSColor.textBackgroundColor),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5)
            )
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    private var sendButtonColor: Color {
        model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isLoading
            ? Color(NSColor.tertiaryLabelColor)
            : Color.accentColor
    }

    // MARK: - Helpers

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

// MARK: - Supporting types

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
        case .gemini, .openAI, .anthropic, .deepSeek, .openCode, .ollama:
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

// MARK: - Message bubble

private struct AskAIMessageBubble: View {
    let message: AskAIMessage
    @State private var isHovered = false
    @State private var didCopy = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.role == .user {
                Spacer(minLength: 80)
            }

            if message.role == .assistant {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 26, height: 26)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 5) {
                MarkdownText(message.content)
                    .font(.system(size: 14))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(message.role == .user ? Color.white : Color(NSColor.labelColor))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(bubbleBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(
                                message.role == .assistant
                                    ? Color(NSColor.separatorColor).opacity(0.5)
                                    : Color.clear,
                                lineWidth: 0.5
                            )
                    )

                if message.role == .assistant {
                    Button(action: copyResponse) {
                        HStack(spacing: 4) {
                            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                            Text(didCopy ? "Copied" : "Copy")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(didCopy ? Color.green : Color(NSColor.tertiaryLabelColor))
                    }
                    .buttonStyle(.plain)
                    .help(didCopy ? "Copied!" : "Copy response")
                    .opacity(isHovered ? 1 : 0)
                    .animation(.easeInOut(duration: 0.15), value: isHovered)
                }
            }
            .frame(maxWidth: 560, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .assistant {
                Spacer(minLength: 80)
            }
        }
        .onHover { isHovered = $0 }
    }

    private var bubbleBackground: Color {
        message.role == .user
            ? Color.accentColor
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

// MARK: - Markdown renderer

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
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(NSColor.textBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(NSColor.separatorColor).opacity(0.6), lineWidth: 0.5)
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

// MARK: - Visual effect background

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
