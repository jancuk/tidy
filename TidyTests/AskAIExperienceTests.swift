import AppKit
import SwiftUI
import Testing
@testable import Tidy

struct AskAIExperienceTests {
    @MainActor @Test func conversationsPersistRenameDeleteAndExport() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = AskAIConversationStore(directory: root)
        let message = AskAIMessage(role: .assistant, content: "**Useful** answer\n\n```swift\nlet n = 1\n```", providerName: "Example")
        var chat = AskAIConversation(title: "Question", messages: [AskAIMessage(role: .user, content: "Explain"), message])
        try store.save(chat)
        try store.rename(chat.id, title: "Renamed")
        let reopened = AskAIConversationStore(directory: root)
        #expect(reopened.conversations.first?.title == "Renamed")
        #expect(reopened.conversations.first?.messages.last?.providerName == "Example")
        #expect(chat.markdown.contains("## You\n\nExplain"))
        #expect(chat.markdown.contains(message.content))
        chat.messages.append(AskAIMessage(role: .user, content: "Next"))
        try store.save(chat)
        #expect(store.conversations.count == 1)
        try store.delete(chat.id)
        #expect(AskAIConversationStore(directory: root).conversations.isEmpty)
    }

    @MainActor @Test func damagedConversationStorageIsNotOverwritten() throws {
        let root = temporaryRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("ai-conversations.json")
        try Data("damaged original".utf8).write(to: file)
        let store = AskAIConversationStore(directory: root)
        #expect(store.errorMessage != nil)
        #expect(throws: TextActionError.self) { try store.save(AskAIConversation(title: "New", messages: [AskAIMessage(role: .user, content: "Hi")])) }
        #expect(throws: TextActionError.self) { try store.clear() }
        #expect(try String(contentsOf: file, encoding: .utf8) == "damaged original")
    }

    @MainActor @Test func newChatDiscardsLateAnswersAndProviderCallbacks() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        var continuation: CheckedContinuation<String, Never>?
        var oldRequest: AskAIRequest?
        let controller = makeController(root) { request in
            if request.question == "Old question" {
                oldRequest = request
                return await withCheckedContinuation { continuation = $0 }
            }
            return "Fresh answer"
        }
        controller.model.query = "Old question"
        let oldTask = try #require(controller.submit())
        for _ in 0..<100 where continuation == nil { await Task.yield() }
        let pending = try #require(continuation)
        #expect(controller.newConversation())
        controller.model.query = "Fresh question"
        await controller.submit()?.value
        pending.resume(returning: "Late answer")
        oldRequest?.progress("Stale progress")
        oldRequest?.sessionUpdate(.codexCLI, "old-session")
        await oldTask.value
        await Task.yield()
        #expect(controller.model.messages.map(\.content) == ["Fresh question", "Fresh answer"])
        #expect(controller.model.codexThreadID == nil)
        #expect(controller.model.progressDescription.isEmpty)
        #expect(controller.conversations.conversations.count == 2)
    }

    @MainActor @Test func failureAndRetryDoNotAddErrorsOrDuplicateQuestionsToHistory() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        var requests: [AskAIRequest] = []
        let controller = makeController(root) { request in
            requests.append(request)
            if requests.count == 1 { throw TextActionError.invalid("Offline") }
            return requests.count == 2 ? "First answer" : "Improved answer"
        }
        controller.model.query = "Explain"
        await controller.submit()?.value
        #expect(controller.model.messages.map(\.content) == ["Explain"])
        #expect(controller.model.errorMessage == "Offline")
        await controller.retry()?.value
        #expect(controller.model.messages.map(\.content) == ["Explain", "First answer"])
        await controller.retry()?.value
        #expect(controller.model.messages.map(\.content) == ["Explain", "Improved answer"])
        #expect(requests.allSatisfy { $0.history.isEmpty })
        #expect(controller.model.errorMessage == nil)
    }

    @MainActor @Test func editsApplyOnlyOnSendAndTemporaryChatsDoNotPersist() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        var requests: [AskAIRequest] = []
        let controller = makeController(root) { request in requests.append(request); return "Answer to " + request.question }
        controller.model.query = "First"
        await controller.submit()?.value
        controller.model.query = "Second"
        await controller.submit()?.value
        let original = controller.model.messages
        controller.edit(original[0])
        controller.model.query = "Revised"
        #expect(controller.model.messages == original)
        await controller.submit()?.value
        #expect(controller.model.messages.map(\.content) == ["Revised", "Answer to Revised"])
        #expect(requests.last?.history.isEmpty == true)
        #expect(controller.newConversation(temporary: true))
        controller.model.query = "Temporary thought"
        await controller.submit()?.value
        #expect(requests.last?.isTemporary == true)
        #expect(controller.conversations.conversations.count == 1)
        #expect(!controller.conversations.conversations.flatMap(\.messages).contains { $0.content.contains("Temporary thought") })
    }

    @Test func markdownKeepsCodeLanguageTablesQuotesAndNumberedStarts() {
        let blocks = AskAIMarkdownBlock.parse("# Plan\n\nA **clear** answer.\n\n```swift\nlet text = \"---\"\n\nprint(text)\n```\n\n| Name | Value |\n| --- | ---: |\n| One | 1 |\n\n> Keep this.\n\n3. Third\n4. Fourth")
        #expect(blocks.contains(.code(language: "swift", content: "let text = \"---\"\n\nprint(text)")))
        #expect(blocks.contains(.table(headings: ["Name", "Value"], rows: [["One", "1"]])))
        #expect(blocks.contains(.quote("Keep this.")))
        #expect(blocks.contains(.list(["Third", "Fourth"], start: 3)))
        #expect(AskAIMarkdownBlock.parse("````text\n```\n````") == [.code(language: "text", content: "```")])
        #expect(AskAIMarkdownBlock.parse("```swift\nlet x = 1") == [.code(language: "swift", content: "let x = 1")])
    }

    @MainActor @Test func removedSourcesStayRemovedAndProviderIsCaptured() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        var captured: AskAIRequest?
        let controller = makeController(root) { captured = $0; return "Answer" }
        let folder = AskAIFolderSource(alias: "Example", url: root)
        controller.model.folderSources = [folder]
        controller.model.selectedFolderSources = [folder]
        controller.model.selectedMCPSources = [.gmail]
        controller.model.query = "Explain @!Example and @mcp-gmail"
        controller.removeContext(folder)
        controller.removeContext(.gmail)
        #expect(controller.model.query == "Explain @!Example and @mcp-gmail")
        controller.model.providerID = .deepSeek
        await controller.submit()?.value
        #expect(captured?.context.folderURLs.isEmpty == true)
        #expect(captured?.context.mcpSources.isEmpty == true)
        #expect(captured?.providerID == .deepSeek)
        #expect(controller.model.messages.first?.contextLabels == [])
        controller.addContext(folder)
        controller.addContext(.gmail)
        controller.model.query = "Use those sources again"
        await controller.submit()?.value
        #expect(captured?.context.folderURLs == [root])
        #expect(captured?.context.mcpSources == [.gmail])
    }

    @MainActor @Test func stoppingRegenerationKeepsOriginalAnswerAndDraft() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        var continuation: CheckedContinuation<String, Never>?
        var count = 0
        let controller = makeController(root) { _ in
            count += 1
            if count == 1 { return "Original answer" }
            return await withCheckedContinuation { continuation = $0 }
        }
        controller.model.query = "Question"
        await controller.submit()?.value
        let pendingTask = try #require(controller.retry())
        for _ in 0..<100 where continuation == nil { await Task.yield() }
        let pending = try #require(continuation)
        controller.model.query = "A follow-up draft"
        controller.stop()
        pending.resume(returning: "Late replacement")
        await pendingTask.value
        #expect(controller.model.messages.map(\.content) == ["Question", "Original answer"])
        #expect(controller.model.query == "A follow-up draft")
        #expect(!controller.model.isLoading)
        #expect(controller.model.notice != nil)
    }

    @MainActor @Test func temporaryRequestsDoNotPersistDiagnostics() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let log = AIRequestLogStore(directory: root)
        for provider in [GrammarProviderID.languageTool, .codexCLI, .claudeCLI] {
            do {
                _ = try await AskAIService().ask("Private thought", history: [],
                    context: AskAIContext(enabledSources: [], mcpSources: [], folderURLs: []),
                    logStore: log, providerID: provider, isTemporary: true)
                Issue.record("Unsupported temporary provider should fail before sending")
            } catch {}
        }
        await Task.yield()
        #expect(log.entries.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("ai-requests.json").path))
    }

    @MainActor @Test func chatRendersInLightAndDarkAppearance() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = makeController(root) { _ in "Answer" }
        controller.model.title = "A clearer approach to async work"
        controller.model.messages = [
            AskAIMessage(role: .user, content: "How can I keep a SwiftUI view responsive while loading data?"),
            AskAIMessage(role: .assistant, content: "Keep UI state on the **main actor**, and let asynchronous work suspend without blocking it.\n\n### A small example\n\n```swift\n.task {\n    let items = try await service.fetchItems()\n    self.items = items\n}\n```\n\n- Cancel work when the view disappears.\n- Show a useful loading state.\n- Keep errors separate from the content.", providerName: "DeepSeek")
        ]
        try controller.conversations.save(AskAIConversation(title: "A plan for the week", messages: [AskAIMessage(role: .user, content: "Help me plan my week")]))
        try controller.conversations.save(controller.transcript)
        for (name, dark, width, height, empty) in [("light", false, 1060, 760, false), ("dark", true, 1060, 760, false),
                                                  ("compact", true, 760, 560, false), ("welcome", true, 760, 560, true)] {
            if empty { controller.model.messages = []; controller.model.title = "New chat"; controller.model.conversationID = UUID() }
            let view = NSHostingView(rootView: AskAIView(model: controller.model, store: controller.conversations, controller: controller)
                .environment(\.colorScheme, dark ? .dark : .light))
            let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: width, height: height), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = view
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            window.orderBack(nil)
            try await Task.sleep(for: .milliseconds(200))
            view.layoutSubtreeIfNeeded()
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let data = try #require(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("Tidy-chat-\(name).png"))
            window.close()
        }
    }

    @MainActor @Test func nativeComposerPreservesPlainTextAndReturnBehavior() async throws {
        var text = "Explain this code"
        var submissions = 0
        let host = NSHostingView(rootView: AskAIComposer(text: Binding(get: { text }, set: { text = $0 }),
            focusRequest: UUID(), submit: { submissions += 1 }))
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 500, height: 150),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderBack(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(100))
        func editor(in view: NSView) -> NSTextView? {
            if let text = view as? NSTextView { return text }
            return view.subviews.compactMap { editor(in: $0) }.first
        }
        let input = try #require(editor(in: host))
        window.makeFirstResponder(input)
        input.setSelectedRange(NSRange(location: input.string.utf16.count, length: 0))
        let shiftedReturn = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.shift],
            timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
        input.keyDown(with: shiftedReturn)
        input.insertText("{\"b\":2}", replacementRange: input.selectedRange())
        #expect(text == "Explain this code\n{\"b\":2}")
        #expect(submissions == 0)
        let sendReturn = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
        input.keyDown(with: sendReturn)
        #expect(submissions == 1)
        #expect(!input.isAutomaticQuoteSubstitutionEnabled)
        #expect(!input.isRichText)
    }

    @MainActor private func makeController(_ root: URL, responder: @escaping AskAIController.Responder) -> AskAIController {
        AskAIController(requestLogStore: AIRequestLogStore(directory: root), conversations: AskAIConversationStore(directory: root), responder: responder)
    }
    private func temporaryRoot() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("TidyChatTests-\(UUID())") }
}
