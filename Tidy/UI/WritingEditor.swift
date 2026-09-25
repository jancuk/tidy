import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct WritingEditor: View {
    @EnvironmentObject private var productivity: ProductivityService
    @Environment(\.dismiss) private var dismiss
    private let originalItem: ProductivityItem
    @State private var item: ProductivityItem
    @State private var source: String
    @State private var tags: String
    @State private var focused = false
    @State private var focusMode = false
    @State private var preview = false
    @State private var action: MarkdownEditorAction?
    @State private var goal = 0
    @State private var status = ""
    @State private var exportError: String?
    @State private var confirmDiscard = false
    @State private var draftSaved = false
    @State private var showDetails = false

    init(item: ProductivityItem, draft: WritingDraft?, startsInReadingMode: Bool = false) {
        let restored = draft?.item ?? item
        originalItem = restored
        _item = State(initialValue: restored)
        _source = State(initialValue: draft?.source ?? item.markdownSource)
        _tags = State(initialValue: restored.tags.joined(separator: ", "))
        _preview = State(initialValue: draft == nil && startsInReadingMode)
    }

    private var words: Int { WritingMetrics.wordCount(source) }
    private var hasContent: Bool { !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if !focusMode {
                HStack {
                    MarkdownToolbar { action = MarkdownEditorAction(kind: $0); preview = false }
                    Picker("Writing view", selection: $preview) {
                        Text("Write").tag(false)
                        Text("Preview").tag(true)
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 145)
                }.padding(.horizontal, 24).padding(.vertical, 12)
            }
            ZStack(alignment: .topLeading) {
                if preview {
                    ScrollView {
                        MarkdownDocumentView(source: source).textSelection(.enabled)
                            .padding(32).frame(maxWidth: 740).frame(maxWidth: .infinity)
                    }.accessibilityIdentifier("writing-preview")
                } else {
                    if source.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Start with one sentence.").font(.system(size: 30, design: .serif))
                            Text("An unfinished thought is a perfectly good beginning.")
                                .font(.system(size: 14))
                        }.foregroundStyle(.tertiary).padding(.horizontal, 39).padding(.top, 39)
                            .allowsHitTesting(false)
                    }
                    MarkdownSourceEditor(text: $source, isFocused: $focused, action: action,
                                         accessibilityLabel: "Writing document")
                        .padding(32)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(WorkspaceDesign.surface)
            if !focusMode {
                HStack(spacing: 12) {
                    Image(systemName: "tag").foregroundStyle(.secondary)
                    TextField("Add tags, separated by commas", text: $tags).textFieldStyle(.plain)
                        .accessibilityLabel("Writing tags")
                    Toggle("Pin to Today", isOn: $item.pinned).toggleStyle(.checkbox)
                }.font(.system(size: 12)).padding(.horizontal, 28).padding(.vertical, 14)
            }
            footer
            if let error = exportError ?? productivity.writingDraftError ?? productivity.errorMessage {
                HStack {
                    Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                    if !productivity.writingDraftsReady {
                        Button("Retry") { productivity.reloadWritingDrafts(); persist() }
                    }
                }.padding(.horizontal, 24).padding(.bottom, 12)
            }
        }
        .frame(minWidth: 740, idealWidth: 880, maxWidth: 1000, minHeight: 580, idealHeight: 740)
        .background(WorkspaceDesign.canvas)
        .interactiveDismissDisabled()
        .onAppear { persist(); focused = true }
        .onChange(of: source) { _, _ in persist(); status = "" }
        .onChange(of: tags) { _, _ in persist() }
        .onChange(of: item.pinned) { _, _ in persist() }
        .onChange(of: item.priority) { _, _ in persist() }
        .onChange(of: item.plannedDay) { _, _ in persist() }
        .onChange(of: item.dueAt) { _, _ in persist() }
        .onChange(of: item.reminderEnabled) { _, _ in persist() }
        .onChange(of: preview) { _, value in if value { action = nil } }
        .confirmationDialog("Discard this draft? Your saved note will stay unchanged.", isPresented: $confirmDiscard) {
            Button("Discard draft", role: .destructive) {
                if productivity.discardWritingDraft(item.id) { dismiss() }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.and.pencil").font(.system(size: 19)).foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text("Writing room").font(.system(size: 14, weight: .semibold))
                Text(draftSaved ? (productivity.writingDrafts.contains { $0.id == item.id } ? "Draft saved on this Mac" : "Saved to your workspace") : "Draft not saved")
                    .font(.system(size: 11)).foregroundStyle(draftSaved ? Color.secondary : .orange)
                    .accessibilityIdentifier("writing-save-status")
            }
            Spacer()
            Button { showDetails.toggle() } label: {
                Image(systemName: "slider.horizontal.3")
            }.buttonStyle(WorkspaceButtonStyle()).accessibilityLabel("Note details")
                .popover(isPresented: $showDetails) { noteDetails }
            Button { focusMode.toggle(); preview = false } label: {
                Label(focusMode ? "Exit focus" : "Focus", systemImage: focusMode ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
            }.buttonStyle(WorkspaceButtonStyle()).help("Hide formatting and organization controls")
            Menu {
                Button("Copy Markdown") { copy() }
                Button("Export Markdown…") { export() }
                Divider()
                Button("Save as a new note") { finish(asCopy: true) }.disabled(!hasContent || !productivity.storageReady)
                Button("Discard draft…", role: .destructive) { confirmDiscard = true }
            } label: { Image(systemName: "ellipsis").frame(width: 24, height: 24) }
                .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Writing options")
            Button("Close") { close() }.keyboardShortcut(.cancelAction).buttonStyle(WorkspaceButtonStyle())
        }.padding(.horizontal, 24).padding(.vertical, 18)
    }

    private var noteDetails: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Organize this note").font(.headline)
            Picker("Priority", selection: $item.priority) {
                ForEach(ProductivityPriority.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Add to a daily plan", isOn: Binding(
                get: { item.plannedDay != nil },
                set: { item.plannedDay = $0 ? productivity.calendar.startOfDay(for: productivity.now) : nil }
            ))
            if item.plannedDay != nil {
                DatePicker("Plan for", selection: Binding(get: { item.plannedDay ?? productivity.now }, set: { item.plannedDay = $0 }), displayedComponents: .date)
            }
            Toggle("Set a due date / reminder", isOn: Binding(
                get: { item.dueAt != nil },
                set: {
                    item.dueAt = $0 ? productivity.now.addingTimeInterval(3600) : nil
                    if !$0 { item.reminderEnabled = false }
                }
            ))
            if item.dueAt != nil {
                DatePicker("When", selection: Binding(get: { item.dueAt ?? productivity.now }, set: { item.dueAt = $0 }))
                Toggle("Notify me on this Mac", isOn: $item.reminderEnabled)
                if item.reminderEnabled && !productivity.snapshot.preferences.notificationsEnabled {
                    Button("Enable macOS alerts") { Task { await productivity.setNotificationsEnabled(true) } }
                }
                Text("Reminders are scheduled when you save the note.").font(.caption).foregroundStyle(.secondary)
            }
            if let source = item.source {
                Label(source.appName ?? "Captured text", systemImage: "link").font(.caption)
                if let url = CaptureSource.safeURL(source.url?.absoluteString) { Link("Open source", destination: url) }
            }
            if let message = productivity.reminderMessage { Text(message).font(.caption).foregroundStyle(.orange) }
        }.padding(22).frame(width: 360)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text("\(words) \(words == 1 ? "word" : "words")").monospacedDigit()
                    if goal > 0 {
                        Text(words >= goal ? "You reached your goal." : "\(max(0, goal - words)) to your goal")
                            .foregroundStyle(words >= goal ? Color.green : .secondary)
                    } else if words > 0 {
                        Text("\(max(1, Int(ceil(Double(words) / 200)))) min read").foregroundStyle(.secondary)
                    }
                }.font(.system(size: 11))
                if goal > 0 { ProgressView(value: min(Double(words), Double(goal)), total: Double(goal)).frame(width: 190) }
            }
            Menu {
                Button("No word goal") { goal = 0 }
                ForEach([100, 300, 500, 1000], id: \.self) { value in
                    Button("\(value) words") { goal = value }
                }
            } label: { Label(goal > 0 ? "\(goal) words" : "Set a small goal", systemImage: "scope") }
                .menuStyle(.borderlessButton).fixedSize().font(.system(size: 11))
            Spacer()
            if !status.isEmpty { Text(status).font(.caption).foregroundStyle(.secondary) }
            Button("Copy", action: copy).buttonStyle(WorkspaceButtonStyle()).disabled(!hasContent)
            Button("Save note") { finish() }.keyboardShortcut("s", modifiers: .command)
                .buttonStyle(WorkspaceButtonStyle(prominent: true))
                .disabled(!hasContent || !productivity.storageReady || !productivity.writingDraftsReady)
        }.padding(.horizontal, 24).padding(.vertical, 16)
    }

    @discardableResult private func persist() -> Bool {
        item.tags = tags.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if item == originalItem, source == originalItem.markdownSource,
           productivity.snapshot.items.contains(where: { $0.id == item.id }),
           !productivity.writingDrafts.contains(where: { $0.id == item.id }) {
            draftSaved = true
            return true
        }
        draftSaved = productivity.keepWritingDraft(item: item, source: source)
        return draftSaved
    }

    private func close() {
        guard persist() else { return }
        if !hasContent, !productivity.discardWritingDraft(item.id) { return }
        dismiss()
    }

    private func finish(asCopy: Bool = false) {
        guard persist() else { return }
        if productivity.finishWriting(item, source: source, asCopy: asCopy) { dismiss() }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(source, forType: .string)
        status = "Copied"
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "\(String(MarkdownDocument.plainTitle(from: source).prefix(80)).replacingOccurrences(of: "/", with: "-" )).md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try source.write(to: url, atomically: true, encoding: .utf8)
            exportError = nil
            status = "Exported"
        } catch { exportError = "Could not export: \(error.localizedDescription)" }
    }
}

struct WritingLaunchpad: View {
    @EnvironmentObject private var productivity: ProductivityService

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Make room for your words.").font(.system(size: 23, design: .serif))
                    Text("A rough idea, a thoughtful email, your next big thing.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Start writing") { start(.blank) }
                    .buttonStyle(WorkspaceButtonStyle(prominent: true)).accessibilityIdentifier("start-writing")
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 125), spacing: 10)], spacing: 10) {
                ForEach(WritingStarter.allCases) { starter in
                    Button { start(starter) } label: {
                        VStack(alignment: .leading, spacing: 9) {
                            Image(systemName: starter.icon).font(.system(size: 18)).foregroundStyle(Color.accentColor)
                            Text(starter.title).font(.system(size: 12, weight: .semibold))
                            Text(starter.detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                        }.frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading).padding(14)
                            .background(WorkspaceDesign.surface, in: RoundedRectangle(cornerRadius: 13))
                            .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(WorkspaceDesign.border))
                            .contentShape(RoundedRectangle(cornerRadius: 13))
                    }.buttonStyle(.plain).accessibilityLabel("Start \(starter.title.lowercased())")
                }
            }
            if !productivity.writingDrafts.isEmpty {
                HStack {
                    Text("PICK UP WHERE YOU LEFT OFF").font(.system(size: 10, weight: .semibold)).tracking(1)
                    Spacer()
                    Text("\(productivity.writingDrafts.count) drafts · on this Mac").font(.system(size: 11))
                }.foregroundStyle(.secondary)
                ForEach(productivity.writingDrafts) { draft in
                    Button { productivity.editorItem = draft.item } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.badge.clock").foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(draft.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                Text("\(WritingMetrics.wordCount(draft.source)) words · Edited \(draft.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("Continue").font(.system(size: 12)).foregroundStyle(.secondary)
                            Image(systemName: "arrow.up.right").font(.system(size: 11))
                        }.padding(14).background(WorkspaceDesign.inset, in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain).accessibilityLabel("Continue draft: \(draft.title)")
                }
            }
            if let error = productivity.writingDraftError {
                Text(error).font(.caption).foregroundStyle(.red)
                if !productivity.writingDraftsReady { Button("Retry loading drafts") { productivity.reloadWritingDrafts() } }
            }
        }
    }

    private func start(_ starter: WritingStarter) {
        var item = ProductivityItem(kind: .note)
        item.setMarkdownSource(starter.source)
        productivity.editorItem = item
    }
}
