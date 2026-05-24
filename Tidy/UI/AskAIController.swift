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
    @Published var errorMessage: String?
    @Published var focusRequestID = UUID()
}

@MainActor
final class AskAIController {
    private let model = AskAIModel()
    private let service = AskAIService()
    private var panel: NSPanel?
    private var eventMonitor: Any?

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
        model.query = ""
        model.errorMessage = nil
        model.messages.append(AskAIMessage(role: .user, content: question))
        model.isLoading = true

        Task {
            do {
                let answer = try await service.ask(question, history: history, context: context)
                model.messages.append(AskAIMessage(role: .assistant, content: answer))
            } catch {
                model.errorMessage = error.localizedDescription
                model.messages.append(AskAIMessage(role: .assistant, content: error.localizedDescription))
            }
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
        model.messages.removeAll()
        model.query = ""
        model.errorMessage = nil
        model.focusRequestID = UUID()
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
                                    Text("Thinking...")
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

private struct AskAIMessageBubble: View {
    let message: AskAIMessage

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 80)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(message.role == .user ? "You" : "Tidy")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
                    .textCase(.uppercase)
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
}

private struct MarkdownText: View {
    let content: String

    init(_ content: String) {
        self.content = content
    }

    var body: some View {
        Text(attributedContent)
    }

    private var attributedContent: AttributedString {
        if let attributed = try? AttributedString(markdown: content) {
            return attributed
        }
        return AttributedString(content)
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
