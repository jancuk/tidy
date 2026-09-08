import AppKit
import SwiftUI

@MainActor
final class TextActionController: ObservableObject {
    typealias Transform = (String, TextAction, String, String, GrammarProviderID) async throws -> String
    private let transform: Transform
    @Published private(set) var original = ""
    @Published private(set) var result = ""
    @Published private(set) var isLoading = false
    @Published private(set) var isReplacing = false
    @Published private(set) var didReplace = false
    @Published private(set) var canReplace = false
    @Published var actionID = "grammar"
    @Published var message: String?
    @Published var errorMessage: String?
    @Published var search = ""
    let store: TextActionStore
    var captureToToday: ((String, ProductivityKind, CaptureSource) -> Bool)?
    var askAI: ((String) -> Void)?
    var manageActions: (() -> Void)?
    private let selectionService: SelectedTextService
    private let logStore: AIRequestLogStore
    private let corrections: CorrectionLogStore
    private var selection: SelectedTextService.Selection?
    private var source = CaptureSource()
    private var panel: NSPanel?
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var resultProviderID = ""

    var actions: [TextAction] { TextAction.builtins + store.actions }
    var action: TextAction? { actions.first { $0.id == actionID } }

    init(store: TextActionStore, selectionService: SelectedTextService, logStore: AIRequestLogStore, corrections: CorrectionLogStore,
         transform: @escaping Transform = { text, action, language, tone, provider in
             try await AskAIService().transform(text, action: action, language: language, tone: tone, providerID: provider)
         }) {
        self.transform = transform
        self.store = store
        self.selectionService = selectionService
        self.logStore = logStore
        self.corrections = corrections
    }

    func showSelection(actionID: String? = nil, captureKind: ProductivityKind? = nil) {
        guard !isReplacing else { return }
        cancel()
        let request = generation
        task = Task {
            do {
                let selected = try await selectionService.capture()
                guard request == generation, !Task.isCancelled else { return }
                if let captureKind, captureToToday?(selected.text, captureKind, selected.source) == true { return }
                prepare(text: selected.text, source: selected.source, actionID: actionID)
                selection = selected
                canReplace = selectionService.canReplace(selected)
                present()
                if captureKind != nil { errorMessage = "Could not save to Today. Open Today to check your workspace storage, then retry." }
            } catch {
                guard request == generation, !Task.isCancelled else { return }
                prepare(text: "", source: CaptureSource(), actionID: actionID)
                errorMessage = error.localizedDescription
                present()
            }
        }
    }

    func show(text: String, source: CaptureSource = CaptureSource(), actionID: String? = nil) {
        guard !isReplacing else { return }
        cancel()
        prepare(text: text, source: source, actionID: actionID)
        present()
    }

    func updateOriginal(_ text: String) {
        guard !isReplacing, !didReplace else { return }
        original = text
        selection = nil
        canReplace = false
        invalidateResult()
    }

    func invalidateResult() {
        guard !isReplacing, !didReplace else { return }
        cancel()
        result = ""
        didReplace = false
        message = nil
        errorMessage = nil
    }

    @discardableResult
    func run() -> Task<Void, Never>? {
        guard let action, !isReplacing, !didReplace else { return nil }
        invalidateResult()
        guard !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { errorMessage = "Enter or select text first."; return nil }
        guard original.count <= 100_000 else { errorMessage = "Use up to 100,000 characters."; return nil }
        let text = original
        let language = UserDefaults.standard.string(forKey: AppDefaults.textActionLanguage) ?? "English"
        let tone = UserDefaults.standard.string(forKey: AppDefaults.textActionTone) ?? "Professional"
        guard action.kind != .translate || !language.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Enter a target language."; return nil
        }
        let provider = GrammarProviderID(rawValue: UserDefaults.standard.string(forKey: AppDefaults.grammarProvider) ?? "") ?? .gemini
        let grammarProviders = GrammarCorrectionPipeline.configuredProviderIDs().filter(TextAction.supportsProvider)
        let request = generation
        isLoading = true
        task = Task {
            let start = Date()
            do {
                let output: String
                let usedProvider: String
                if action.isLocal { output = try action.localResult(for: text); usedProvider = "local" }
                else if action.kind == .grammar {
                    guard !grammarProviders.isEmpty else {
                        throw TextActionError.invalid("Choose a text-only grammar provider in Settings. CLI providers with filesystem tools are unavailable in Text Actions.")
                    }
                    let correction = try await GrammarCorrectionPipeline.correct(text, providerIDs: grammarProviders)
                    output = correction.correctedText
                    usedProvider = correction.providerID
                } else {
                    output = try await transform(text, action, language, tone, provider)
                    usedProvider = provider.rawValue
                }
                guard request == generation, !Task.isCancelled else { return }
                guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AskAIError.emptyAnswer }
                result = output
                resultProviderID = usedProvider
                message = output == text ? "No text changes needed." : "Review the result before replacing or copying."
                if !action.isLocal {
                    logStore.append(AIRequestLogEntry(providerName: GrammarProviderID(rawValue: usedProvider)?.displayName ?? usedProvider,
                                                     requestPreview: String(text.prefix(100)), durationMs: Int(Date().timeIntervalSince(start) * 1000), source: "text-action"))
                }
            } catch {
                guard request == generation, !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
            if request == generation { isLoading = false }
        }
        return task
    }

    func replace() {
        guard let selection, !result.isEmpty, !isLoading, !isReplacing, !didReplace else { return }
        let output = result
        isReplacing = true
        task = Task {
            defer { isReplacing = false; present() }
            do {
                try await selectionService.replace(selection, with: output)
                didReplace = true
                canReplace = false
                corrections.append(original: original, corrected: output, providerID: resultProviderID)
                message = "Replaced. Restore original remains available while the document is unchanged."
                errorMessage = nil
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func restore() {
        guard didReplace, !isReplacing else { return }
        isReplacing = true
        task = Task {
            defer { isReplacing = false; present() }
            do {
                try await selectionService.restoreOriginal()
                didReplace = false
                message = "Original restored. Select the text again to make another replacement."
                errorMessage = nil
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func copy(original copyOriginal: Bool = false) {
        let text = copyOriginal ? original : result
        guard !text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        message = copyOriginal ? "Original copied." : "Result copied as plain text."
    }

    func capture(_ kind: ProductivityKind, useResult: Bool) {
        let text = useResult ? result : original
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if captureToToday?(text, kind, source) == true { message = "Saved as a \(kind.title.lowercased()) in Today." }
        else { errorMessage = "Could not save to Today. Check your workspace storage and retry." }
    }

    func continueInAskAI() {
        let text = result.isEmpty ? original : result
        hide()
        askAI?(text)
    }

    func hide() { if !isReplacing { cancel(); panel?.orderOut(nil) } }

    private func cancel() { task?.cancel(); generation = UUID(); isLoading = false }

    private func prepare(text: String, source: CaptureSource, actionID: String?) {
        original = text
        self.source = source
        selection = nil
        result = ""
        canReplace = false
        didReplace = false
        message = nil
        errorMessage = nil
        search = ""
        self.actionID = actionID ?? "grammar"
    }

    private func present() {
        if panel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 940, height: 650),
                                styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            panel.title = "Text Actions"
            panel.isReleasedWhenClosed = false
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentMinSize = NSSize(width: 820, height: 560)
            panel.contentView = NSHostingView(rootView: TextActionView().environmentObject(self).environmentObject(store))
            panel.center()
            self.panel = panel
        }
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

struct TextActionView: View {
    @EnvironmentObject private var model: TextActionController
    @EnvironmentObject private var store: TextActionStore
    @AppStorage(AppDefaults.textActionLanguage) private var language = "English"
    @AppStorage(AppDefaults.textActionTone) private var tone = "Professional"
    @State private var showChanges = false

    private var actions: [TextAction] {
        (TextAction.builtins + store.actions).filter { model.search.isEmpty || $0.title.localizedCaseInsensitiveContains(model.search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Text Actions", systemImage: "text.badge.star").font(.headline)
                Spacer()
                Menu("Save to Today") {
                    Button("Original as task") { model.capture(.task, useResult: false) }
                    Button("Original as note") { model.capture(.note, useResult: false) }
                    if !model.result.isEmpty {
                        Button("Result as task") { model.capture(.task, useResult: true) }
                        Button("Result as note") { model.capture(.note, useResult: true) }
                    }
                }.fixedSize()
                Button("Ask AI") { model.continueInAskAI() }.disabled(model.original.isEmpty)
                Button("Close") { model.hide() }.keyboardShortcut(.cancelAction)
            }.padding(16)
            Divider()
            HSplitView {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Find an action", text: $model.search).textFieldStyle(.roundedBorder)
                    List(selection: Binding<String?>(get: { model.actionID }, set: { if let value = $0 { model.actionID = value } })) {
                        ForEach(actions) { action in
                            HStack {
                                Text(action.title)
                                Spacer()
                                if action.isLocal { Image(systemName: "lock").help("Runs locally without AI") }
                            }.tag(action.id)
                        }
                    }.listStyle(.sidebar)
                    Button("Manage custom actions…") { model.hide(); model.manageActions?() }
                        .font(.caption)
                    Text("⌘↩ Run · ⌘⇧↩ Replace\n⌘R Retry · Esc Close").font(.caption).foregroundStyle(.secondary)
                }.padding(12).frame(minWidth: 205, idealWidth: 225, maxWidth: 270)
                    .disabled(model.didReplace)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(model.action?.title ?? "Choose an action").font(.title2)
                        Spacer()
                        if model.isLoading { ProgressView().controlSize(.small) }
                    }
                    if model.action?.kind == .translate {
                        TextField("Target language", text: $language).textFieldStyle(.roundedBorder)
                            .disabled(model.didReplace)
                    }
                    if model.action?.kind == .tone {
                        Picker("Tone", selection: $tone) {
                            ForEach(["Professional", "Friendly", "Casual", "Confident", "Empathetic"], id: \.self) { Text($0) }
                        }.disabled(model.didReplace)
                    }
                    Text(model.action?.isLocal == true ? "Runs on your Mac." : "Uses your configured AI provider. Local-only AI settings apply.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading) {
                            Text("Original").font(.caption.bold())
                            TextActionInput(text: Binding(get: { model.original }, set: model.updateOriginal))
                                .disabled(model.isLoading || model.didReplace)
                            Button("Copy original") { model.copy(original: true) }.disabled(model.original.isEmpty)
                        }
                        VStack(alignment: .leading) {
                            HStack {
                                Text("Result").font(.caption.bold())
                                Spacer()
                                Toggle("Changes", isOn: $showChanges).toggleStyle(.checkbox).font(.caption)
                            }
                            ScrollView {
                                if showChanges && !model.result.isEmpty && model.original.components(separatedBy: "\n").count < 200 && model.result.components(separatedBy: "\n").count < 200 {
                                    VStack(alignment: .leading, spacing: 3) {
                                        ForEach(TextDiffTool.lineDiff(old: model.original, new: model.result)) { row in
                                            Text((row.kind == .added ? "+ " : row.kind == .removed ? "− " : "  ") + row.text)
                                                .foregroundStyle(row.kind == .added ? Color.green : row.kind == .removed ? Color.red : Color.primary)
                                                .textSelection(.enabled)
                                        }
                                    }.font(.system(size: 12, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading)
                                } else {
                                    Text(model.result.isEmpty ? "Run an action to preview the result." : model.result)
                                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                        .accessibilityIdentifier("text-action-result")
                                }
                            }.padding(10).frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color(NSColor.textBackgroundColor))
                            Button("Copy result") { model.copy() }.keyboardShortcut("c", modifiers: [.command, .shift])
                                .disabled(model.result.isEmpty || model.isLoading)
                        }
                    }.frame(maxHeight: .infinity)
                    if let error = model.errorMessage { Text(error).font(.callout).foregroundStyle(.red).textSelection(.enabled).accessibilityIdentifier("text-action-error") }
                    if let message = model.message { Text(message).font(.caption).foregroundStyle(.secondary) }
                    if !model.canReplace && !model.didReplace && !model.original.isEmpty {
                        Text("Copy the result to paste manually when the source app cannot verify replacement.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    HStack {
                        Button(model.isLoading ? "Cancel" : "Run action") { if model.isLoading { model.invalidateResult() } else { model.run() } }
                            .keyboardShortcut(.return, modifiers: .command)
                            .accessibilityIdentifier("text-action-run")
                            .disabled(model.didReplace)
                        Button("Retry") { model.run() }.keyboardShortcut("r", modifiers: .command)
                            .disabled(model.result.isEmpty || model.isLoading || model.didReplace)
                        Spacer()
                        if model.didReplace {
                            Button("Restore original") { model.restore() }.buttonStyle(.borderedProminent)
                        } else {
                            Button("Replace selection") { model.replace() }.buttonStyle(.borderedProminent)
                                .keyboardShortcut(.return, modifiers: [.command, .shift])
                                .disabled(!model.canReplace || model.result.isEmpty || model.isLoading)
                        }
                    }
                }.padding(18).frame(minWidth: 520)
            }.disabled(model.isReplacing)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onChange(of: model.actionID) { _, _ in model.invalidateResult() }
        .onChange(of: language) { _, _ in model.invalidateResult() }
        .onChange(of: tone) { _, _ in model.invalidateResult() }
    }
}

private struct TextActionInput: NSViewRepresentable {
    @Binding var text: String
    @Environment(\.isEnabled) private var isEnabled

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        if let editor = scrollView.documentView as? NSTextView {
            editor.isRichText = false
            editor.isAutomaticQuoteSubstitutionEnabled = false
            editor.isAutomaticDashSubstitutionEnabled = false
            editor.isAutomaticTextReplacementEnabled = false
            editor.isAutomaticSpellingCorrectionEnabled = false
            editor.isAutomaticLinkDetectionEnabled = false
            editor.font = .systemFont(ofSize: 13)
            editor.textColor = .textColor
            editor.setAccessibilityLabel("Original text")
            editor.setAccessibilityIdentifier("text-action-original")
            editor.delegate = context.coordinator
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        guard let editor = scrollView.documentView as? NSTextView else { return }
        editor.isEditable = isEnabled
        if editor.string != text { editor.string = text }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            text.wrappedValue = editor.string
        }
    }
}
