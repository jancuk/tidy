import AppKit
import SwiftUI

struct AskAIView: View {
    @ObservedObject var model: AskAIModel
    @ObservedObject var store: AskAIConversationStore
    let controller: AskAIController
    @AppStorage(AppDefaults.appearanceMode) private var appearanceMode = "system"
    @State private var sidebarVisible = true
    @State private var historySearch = ""
    @State private var contextVisible = false
    @State private var isNearBottom = true
    @State private var renameTarget: AskAIConversation?
    @State private var renameTitle = ""
    @State private var deleteTarget: AskAIConversation?
    @State private var copiedConversation = false
    @State private var compactLayout = false

    var body: some View {
        HStack(spacing: 0) {
            if sidebarVisible { sidebar.frame(width: 220); Divider() }
            VStack(spacing: 0) {
                header
                messageArea
                composer
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(WorkspaceDesign.canvas)
        .preferredColorScheme(appearanceMode == "dark" ? .dark : appearanceMode == "light" ? .light : nil)
        .frame(minWidth: 760, minHeight: 560)
        .onGeometryChange(for: Bool.self) { $0.size.width < 900 || $0.size.height < 650 } action: { compactLayout = $0 }
        .onChange(of: model.providerID) { _, _ in controller.providerChanged() }
        .alert("Rename chat", isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })) {
            TextField("Chat title", text: $renameTitle)
            Button("Cancel", role: .cancel) { renameTarget = nil }
            Button("Save") { if let renameTarget { controller.rename(renameTarget, title: renameTitle) }; renameTarget = nil }
        }
        .alert("Delete this chat?", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })) {
            Button("Cancel", role: .cancel) { deleteTarget = nil }
            Button("Delete", role: .destructive) { if let deleteTarget { controller.delete(deleteTarget) }; deleteTarget = nil }
        } message: { Text("This removes the conversation saved on this Mac.") }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 9) {
                Image("TidyLogo").resizable().frame(width: 27, height: 27)
                Text("Tidy").font(.system(size: 17, weight: .semibold))
                Spacer()
                Text("ASK AI").font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(.secondary)
            }.padding(.top, 8)
            Button { controller.newConversation() } label: {
                Label("New chat", systemImage: "square.and.pencil").frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(WorkspaceButtonStyle()).help("New chat · ⌘N").accessibilityIdentifier("ask-ai-new-chat")
            WorkspaceSearchField(text: $historySearch, placeholder: "Search chats", label: "Search chats")
            VStack(alignment: .leading, spacing: 8) {
                Text("RECENT").font(.system(size: 10, weight: .semibold)).tracking(1.5).foregroundStyle(.tertiary)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(filteredConversations) { chat in
                            Button { controller.select(chat) } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(chat.title).font(.system(size: 12, weight: chat.id == model.conversationID ? .medium : .regular))
                                        .lineLimit(2).multilineTextAlignment(.leading)
                                    Text(chat.updatedAt, style: .date).font(.system(size: 10)).foregroundStyle(.tertiary)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                                    .background(chat.id == model.conversationID ? WorkspaceDesign.border.opacity(0.55) : .clear,
                                                in: RoundedRectangle(cornerRadius: 9))
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityIdentifier("ask-ai-chat-\(chat.id)")
                                .contextMenu {
                                    Button("Rename…") { renameTitle = chat.title; renameTarget = chat }
                                    Button("Delete…", role: .destructive) { deleteTarget = chat }
                                }
                        }
                        if filteredConversations.isEmpty {
                            Text(historySearch.isEmpty ? "Your conversations will appear here." : "No matching chats.")
                                .font(.system(size: 12)).foregroundStyle(.tertiary).padding(.vertical, 14)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            Button { controller.newConversation(temporary: true) } label: {
                Label("Temporary chat", systemImage: "bubble.left.and.bubble.right")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }.buttonStyle(.plain).accessibilityIdentifier("ask-ai-temporary")
            Label("History stays on this Mac", systemImage: "lock")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        }.padding(18).background(WorkspaceDesign.surface.opacity(0.55))
    }

    private var header: some View {
        HStack(spacing: 12) {
            iconButton("sidebar.left", label: "Toggle chat history") { sidebarVisible.toggle() }
            VStack(alignment: .leading, spacing: 3) {
                Text(model.isTemporary ? "Temporary chat" : model.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Menu {
                    Picker("Provider for this chat", selection: $model.providerID) {
                        ForEach(GrammarProviderID.allCases.filter { $0 != .languageTool && $0 != .jevCodex }) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(model.providerID.displayName)
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                    }.font(.system(size: 11)).foregroundStyle(.secondary)
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().disabled(model.isLoading).help("AI provider for this chat")
            }
            Spacer()
            Menu {
                Button("Copy conversation") {
                    copy(controller.transcript.markdown); copiedConversation = true
                }.disabled(model.messages.isEmpty)
                Button("Export as Markdown…") { controller.exportConversation() }.disabled(model.messages.isEmpty)
                Button("New temporary chat") { controller.newConversation(temporary: true) }
            } label: { Image(systemName: "ellipsis").frame(width: 26, height: 28) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Conversation actions")
            iconButton("xmark", label: "Close Ask AI") { controller.hide() }
        }.padding(.horizontal, 22).padding(.vertical, 16)
            .overlay(alignment: .bottom) { WorkspaceDesign.border.opacity(0.6).frame(height: 1) }
    }

    private var messageArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if model.messages.isEmpty { welcome }
                    ForEach(model.messages) { message in
                        AskAIMessageRow(message: message, canEdit: !model.isLoading,
                                        canRetry: !model.isLoading && message.id == model.messages.last?.id,
                                        edit: { controller.edit(message) }, retry: { controller.retry() })
                            .id(message.id)
                    }
                    if model.isLoading {
                        HStack(spacing: 12) {
                            ProgressView().controlSize(.small)
                            Text(model.progressDescription).font(.system(size: 13)).foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }.accessibilityIdentifier("ask-ai-progress")
                    }
                    if let error = model.errorMessage {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Couldn’t complete the response", systemImage: "exclamationmark.circle").font(.system(size: 13, weight: .medium))
                            Text(error).font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled)
                            if model.messages.contains(where: { $0.role == .user }) {
                                Button("Try again") { controller.retry() }.buttonStyle(WorkspaceButtonStyle()).disabled(model.isLoading)
                            }
                        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityIdentifier("ask-ai-error")
                    }
                    if let notice = model.notice {
                        HStack {
                            Text(notice).font(.system(size: 12)).foregroundStyle(.secondary)
                            Button("Retry") { controller.retry() }.buttonStyle(.plain).disabled(model.isLoading)
                        }
                    }
                    Color.clear.frame(height: 1).id("chat-bottom")
                }.frame(maxWidth: 680).padding(.horizontal, compactLayout ? 24 : 30).padding(.vertical, compactLayout ? 16 : 32)
                    .frame(maxWidth: .infinity)
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentSize.height - geometry.visibleRect.maxY < 90
            } action: { _, nearBottom in isNearBottom = nearBottom }
            .onChange(of: model.messages) { _, messages in
                if isNearBottom || messages.last?.role == .user { proxy.scrollTo("chat-bottom", anchor: .bottom) }
            }
            .onChange(of: model.isLoading) { _, _ in if isNearBottom { proxy.scrollTo("chat-bottom", anchor: .bottom) } }
            .onChange(of: model.conversationID) { _, _ in proxy.scrollTo("chat-bottom", anchor: .bottom) }
            .overlay(alignment: .bottomTrailing) {
                if !isNearBottom && !model.messages.isEmpty {
                    Button { withAnimation { proxy.scrollTo("chat-bottom", anchor: .bottom) } } label: {
                        Label("Latest", systemImage: "arrow.down")
                    }.buttonStyle(WorkspaceButtonStyle()).padding(16)
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: compactLayout ? 14 : 24) {
            Image(systemName: "sparkle").font(.system(size: compactLayout ? 22 : 32, weight: .light)).foregroundStyle(Color.accentColor)
            Text("What would you like\nto work on?").font(.system(size: compactLayout ? 28 : 36, weight: .regular, design: .serif)).lineSpacing(2)
            Text("A fresh perspective, a clearer draft, or help with the next step.")
                .font(.system(size: compactLayout ? 12 : 14)).foregroundStyle(.secondary).lineSpacing(4)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                starter("Write something", detail: "Find the right words", icon: "pencil.line", prompt: "Help me write ")
                starter("Understand code", detail: "Work through a problem", icon: "chevron.left.forwardslash.chevron.right", prompt: "Explain this code and suggest improvements:\n\n")
                starter("Make a plan", detail: "Turn an idea into steps", icon: "list.bullet", prompt: "Help me make a practical plan for ")
                starter("Explore an idea", detail: "Think it through together", icon: "sparkle.magnifyingglass", prompt: "Help me explore this idea from different angles:\n\n")
            }.padding(.top, 6)
        }.padding(.vertical, compactLayout ? 4 : 26).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func starter(_ title: String, detail: String, icon: String, prompt: String) -> some View {
        Button { model.query = prompt; model.focusRequestID = UUID() } label: {
            VStack(alignment: .leading, spacing: 10) {
                if !compactLayout { Image(systemName: icon).font(.system(size: 15)).foregroundStyle(.secondary) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 12, weight: .medium))
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(compactLayout ? 12 : 16)
                .background(WorkspaceDesign.surface, in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(WorkspaceDesign.border))
        }.buttonStyle(.plain)
    }

    private var composer: some View {
        VStack(spacing: 10) {
            if let error = model.storageError ?? store.errorMessage {
                Text(error).font(.system(size: 11)).foregroundStyle(.orange).textSelection(.enabled)
            }
            if copiedConversation {
                Text("Conversation copied.").font(.system(size: 11)).foregroundStyle(.secondary)
                    .task { try? await Task.sleep(for: .seconds(2)); copiedConversation = false }
            }
            if model.editingMessageID != nil {
                HStack {
                    Label("Editing message · later replies will be replaced when you send", systemImage: "pencil")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") { controller.cancelEdit() }.buttonStyle(.plain).font(.system(size: 11))
                }
            }
            if AskAIMentionParser.currentMention(in: model.query) != nil { mentionSuggestions }
            VStack(alignment: .leading, spacing: 4) {
                if !model.selectedFolderSources.isEmpty || !model.selectedMCPSources.isEmpty { contextChips }
                ZStack(alignment: .topLeading) {
                    if model.query.isEmpty {
                        Text("Ask anything, or add context…").font(.system(size: 15)).foregroundStyle(.tertiary)
                            .padding(.top, 8).padding(.leading, 9).allowsHitTesting(false)
                    }
                    AskAIComposer(text: $model.query, focusRequest: model.focusRequestID) { controller.submit() }
                }
                HStack(spacing: 12) {
                    Button { contextVisible.toggle() } label: {
                        Label("Add context", systemImage: "plus").font(.system(size: 11, weight: .medium))
                    }.buttonStyle(.plain).foregroundStyle(.secondary).disabled(model.isLoading)
                        .popover(isPresented: $contextVisible, arrowEdge: .top) { contextPicker }
                    Spacer()
                    if model.isLoading {
                        Button { controller.stop() } label: { Image(systemName: "stop.fill").font(.system(size: 11)).frame(width: 32, height: 32) }
                            .buttonStyle(.plain).background(Color.primary, in: Circle()).foregroundStyle(WorkspaceDesign.canvas)
                            .help("Stop response").accessibilityLabel("Stop response").accessibilityIdentifier("ask-ai-stop")
                    } else {
                        Button { controller.submit() } label: { Image(systemName: "arrow.up").font(.system(size: 14, weight: .semibold)).frame(width: 32, height: 32) }
                            .buttonStyle(.plain).background(Color.primary, in: Circle()).foregroundStyle(WorkspaceDesign.canvas)
                            .opacity(model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.25 : 1)
                            .disabled(model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .help("Send message · Return").accessibilityLabel("Send message").accessibilityIdentifier("ask-ai-send")
                    }
                }.padding(.horizontal, 8).padding(.bottom, 6)
            }.padding(10).background(WorkspaceDesign.surface, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(WorkspaceDesign.border))
                .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
            HStack {
                Text(model.isTemporary ? "Not saved by Tidy. Provider policies still apply." : "Sent to " + model.providerID.displayName + " · Saved on this Mac")
                Spacer()
                Text("⇧↩ New line")
            }.font(.system(size: 10)).foregroundStyle(.tertiary)
        }.frame(maxWidth: 720).padding(.horizontal, 24).padding(.bottom, 18).padding(.top, 8)
            .frame(maxWidth: .infinity).background(WorkspaceDesign.canvas)
    }

    private var contextChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(model.selectedFolderSources) { source in
                    chip(source.alias, icon: "folder") { removeFolder(source) }.help(source.url.path)
                }
                ForEach(AskAIMCPSource.allCases.filter { model.selectedMCPSources.contains($0) }) { source in
                    chip(source.title, icon: source.systemImage) { controller.removeContext(source) }
                }
            }.padding(6)
        }.disabled(model.isLoading)
    }

    private var contextPicker: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Give your question context").font(.headline)
            Text("Only selected sources are included with your messages.").font(.caption).foregroundStyle(.secondary)
            Button { contextVisible = false; controller.chooseFolder() } label: {
                Label("Choose folders…", systemImage: "folder.badge.plus")
            }.buttonStyle(WorkspaceButtonStyle())
            Divider()
            Text("Connected sources").font(.caption).foregroundStyle(.secondary)
            ForEach(AskAIMCPSource.allCases) { source in
                Toggle(source.title, isOn: Binding(get: { model.selectedMCPSources.contains(source) }, set: { enabled in
                    if enabled { controller.addContext(source) } else { controller.removeContext(source) }
                }))
            }
        }.padding(20).frame(width: 280)
    }

    private var mentionSuggestions: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                switch AskAIMentionParser.currentMention(in: model.query) {
                case .mcp(let filter):
                    ForEach(AskAIMCPSource.allCases.filter { filter.isEmpty || $0.mention.localizedCaseInsensitiveContains(filter) || $0.title.localizedCaseInsensitiveContains(filter) }) { source in
                        Button {
                            controller.addContext(source)
                            model.query = AskAIMentionParser.replacingCurrentMention(in: model.query, with: source.mention)
                            model.focusRequestID = UUID()
                        } label: { Label(source.title, systemImage: source.systemImage).frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(WorkspaceButtonStyle())
                    }
                case .folder(let filter):
                    ForEach(model.folderSources.filter { filter.isEmpty || $0.alias.localizedCaseInsensitiveContains(filter) }) { source in
                        Button {
                            controller.addContext(source)
                            model.query = AskAIMentionParser.replacingCurrentMention(in: model.query, with: source.mention)
                        } label: { Label(source.alias, systemImage: "folder").frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(WorkspaceButtonStyle())
                    }
                    Button("Choose folders…") { controller.chooseFolder() }.buttonStyle(WorkspaceButtonStyle())
                case nil: EmptyView()
                }
            }
        }.frame(maxHeight: 150).padding(10).background(WorkspaceDesign.surface, in: RoundedRectangle(cornerRadius: 12)).disabled(model.isLoading)
    }

    private func chip(_ title: String, icon: String, remove: @escaping () -> Void) -> some View {
        Button(action: remove) {
            HStack(spacing: 5) { Image(systemName: icon); Text(title).lineLimit(1); Image(systemName: "xmark").font(.system(size: 8)) }
                .font(.system(size: 10)).padding(.horizontal, 9).padding(.vertical, 6)
                .background(WorkspaceDesign.inset, in: Capsule())
        }.buttonStyle(.plain).accessibilityLabel("Remove " + title + " context")
    }

    private func removeFolder(_ source: AskAIFolderSource) {
        controller.removeContext(source)
    }

    private var filteredConversations: [AskAIConversation] {
        store.conversations.filter { historySearch.isEmpty || $0.title.localizedCaseInsensitiveContains(historySearch) || $0.messages.contains { $0.content.localizedCaseInsensitiveContains(historySearch) } }
    }

    private func iconButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 13)).frame(width: 28, height: 28) }
            .buttonStyle(.plain).foregroundStyle(.secondary).help(label).accessibilityLabel(label)
    }

    private func copy(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
}

private struct AskAIMessageRow: View {
    let message: AskAIMessage
    let canEdit: Bool
    let canRetry: Bool
    let edit: () -> Void
    let retry: () -> Void
    @State private var didCopy = false

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 10) {
            if message.role == .assistant {
                HStack(spacing: 7) {
                    Image(systemName: "sparkle").foregroundStyle(Color.accentColor)
                    Text(message.providerName ?? "Assistant").foregroundStyle(.secondary)
                }.font(.system(size: 11, weight: .medium))
            }
            if message.role == .user {
                HStack {
                    Spacer(minLength: 60)
                    Text(message.content).font(.system(size: 14)).lineSpacing(5).textSelection(.enabled)
                        .padding(.horizontal, 18).padding(.vertical, 13)
                        .background(WorkspaceDesign.inset, in: RoundedRectangle(cornerRadius: 17))
                }
                if let labels = message.contextLabels, !labels.isEmpty {
                    Label(labels.joined(separator: " · "), systemImage: "paperclip")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            } else {
                AskAIMarkdown(content: message.content).textSelection(.enabled)
                    .accessibilityIdentifier("ask-ai-answer")
            }
            HStack(spacing: 15) {
                Button {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(message.content, forType: .string); didCopy = true
                } label: { Label(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc") }
                    .task(id: didCopy) { if didCopy { try? await Task.sleep(for: .seconds(2)); didCopy = false } }
                if message.role == .user && canEdit { Button(action: edit) { Label("Edit", systemImage: "pencil") } }
                if message.role == .assistant && canRetry { Button(action: retry) { Label("Try again", systemImage: "arrow.clockwise") } }
            }.font(.system(size: 10)).foregroundStyle(.secondary).buttonStyle(.plain)
        }.frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }
}
