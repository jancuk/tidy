import AppKit
import SwiftUI

struct ClipboardListView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var clipboardService: ClipboardService
    @State private var selectedID: Int64?
    @State private var codeFont = false
    @State private var copiedID: Int64?

    private var selectedEntry: ClipboardEntry? {
        clipboardService.entries.first { $0.id == selectedID } ?? clipboardService.entries.first
    }

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceHeader(title: "Clipboard", subtitle: "Find it again. Read it in full. Keep moving.") {
                Text("\(clipboardService.entries.count) \(clipboardService.entries.count == 1 ? "item" : "items")").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            HSplitView {
                VStack(spacing: 0) {
                    WorkspaceSearchField(text: $clipboardService.query, placeholder: "Search clipboard", label: "Search clipboard history")
                        .padding(16)
                    ClipboardFiltersView(service: clipboardService).padding(.horizontal, 16).padding(.bottom, 10)
                    if let error = clipboardService.errorMessage { Text(error).font(.caption).foregroundStyle(.red) }
                    if clipboardService.entries.isEmpty {
                        WorkspaceEmptyState(title: "Nothing here yet", detail: clipboardService.query.isEmpty ? "Text you copy appears here." : "Try another word or clear your search.", icon: "doc.on.clipboard")
                    } else {
                        List(selection: $selectedID) {
                            ForEach(clipboardService.entries) { entry in
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        if entry.isPinned { Image(systemName: "pin.fill").foregroundStyle(.orange) }
                                        if !entry.collection.isEmpty { Text(entry.collection).font(.caption).foregroundStyle(.secondary) }
                                    }
                                    Text(entry.preview).font(.system(size: 13, weight: .medium)).lineLimit(3)
                                    HStack {
                                        Text(entry.sourceAppName ?? "Clipboard")
                                        Spacer()
                                        Text(entry.createdAt, style: .relative)
                                    }.font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 9).tag(entry.id)
                                .listRowSeparator(.hidden)
                                .contextMenu {
                                    Button("Copy as plain text") { copy(entry) }
                                    Button(entry.isPinned ? "Unpin" : "Pin favorite") { clipboardService.togglePin(entry) }
                                    Button("Text actions…") { appState.openTextActions(entry: entry) }
                                    Button("Save as task") { appState.captureToToday(entry.content, kind: .task, source: entry.captureSource) }
                                    Button("Save as note") { appState.captureToToday(entry.content, kind: .note, source: entry.captureSource) }
                                    Button("Delete", role: .destructive) { clipboardService.delete(entry) }
                                }
                            }
                        }.listStyle(.plain).scrollContentBackground(.hidden)
                    }
                }.frame(minWidth: 250, idealWidth: 300, maxWidth: 370)
                    .background(WorkspaceDesign.canvas)
                if let entry = selectedEntry {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(entry.sourceAppName ?? "Clipboard item").font(.system(size: 18, weight: .semibold))
                                Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button { codeFont.toggle() } label: {
                                Label("Code font", systemImage: codeFont ? "checkmark" : "chevron.left.forwardslash.chevron.right")
                            }.buttonStyle(WorkspaceButtonStyle()).accessibilityValue(codeFont ? "On" : "Off")
                            Button { copy(entry) } label: {
                                Label(copiedID == entry.id ? "Copied" : "Copy", systemImage: copiedID == entry.id ? "checkmark" : "doc.on.doc")
                            }.buttonStyle(WorkspaceButtonStyle(prominent: true))
                        }.padding(24)
                        HStack {
                            ClipboardEntryActions(entry: entry, service: clipboardService,
                                                  transform: { appState.openTextActions(entry: entry, actionID: $0) },
                                                  capture: { appState.captureToToday(entry.content, kind: $0, source: entry.captureSource) })
                            Text(entry.isPinned ? "Pinned · kept until removed" : "Automatically removed by retention settings").font(.caption).foregroundStyle(.secondary)
                        }.padding(.horizontal, 24).padding(.bottom, 12)
                        ScrollView {
                            Text(entry.content)
                                .font(.system(size: 15, design: codeFont ? .monospaced : .default))
                                .lineSpacing(7).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(26)
                        }.background(WorkspaceDesign.surface, in: RoundedRectangle(cornerRadius: 18))
                            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(WorkspaceDesign.border))
                            .padding(.horizontal, 24)
                        HStack {
                            Text("\(entry.charCount.formatted()) characters · Full saved content")
                            Spacer()
                            Image(systemName: "lock").accessibilityLabel("Stored locally")
                        }.font(.system(size: 11)).foregroundStyle(.secondary).padding(24)
                    }.frame(minWidth: 390, maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    WorkspaceEmptyState(title: "A place for what you copy.", detail: "Select an item to read its full content and copy it again.", icon: "doc.text.magnifyingglass")
                        .frame(minWidth: 390)
                }
            }
        }.background(WorkspaceDesign.canvas)
        .onAppear { selectedID = selectedEntry?.id }
        .onChange(of: clipboardService.entries) { _, _ in selectedID = selectedEntry?.id }
    }

    private func copy(_ entry: ClipboardEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.content, forType: .string)
        copiedID = entry.id
    }
}

struct CorrectionLogView: View {
    @EnvironmentObject private var correctionLogStore: CorrectionLogStore
    @State private var search = ""
    @State private var expanded: Set<UUID> = []
    @State private var copiedID: UUID?
    @State private var confirmClear = false

    private var results: [CorrectionLogEntry] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return correctionLogStore.entries.filter { query.isEmpty || [$0.original, $0.corrected, $0.providerID].joined(separator: " ").localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceHeader(title: "Corrections", subtitle: "A clearer version, with the original close by.") {
                Menu {
                    Button("Clear history…", role: .destructive) { confirmClear = true }
                        .disabled(correctionLogStore.entries.isEmpty)
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize().help("Correction history options")
            }
            HStack {
                WorkspaceSearchField(text: $search, placeholder: "Search corrections", label: "Search corrections")
                Spacer()
                Text("\(results.count) \(results.count == 1 ? "correction" : "corrections")").font(.system(size: 12)).foregroundStyle(.secondary)
            }.padding(.horizontal, 28).padding(.vertical, 16)
            if results.isEmpty {
                WorkspaceEmptyState(title: search.isEmpty ? "Your words, a little clearer." : "No matching corrections",
                                    detail: search.isEmpty ? "Applied grammar corrections appear here, with both versions saved for reference." : "Try a different phrase or provider.", icon: "text.badge.checkmark")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(results) { entry in
                            VStack(alignment: .leading, spacing: 18) {
                                HStack {
                                    Label(GrammarProviderID(rawValue: entry.providerID)?.displayName ?? entry.providerID, systemImage: "sparkles")
                                    Spacer()
                                    Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                                }.font(.system(size: 11)).foregroundStyle(.secondary)
                                Text(entry.corrected).font(.system(size: 16)).lineSpacing(6)
                                    .lineLimit(expanded.contains(entry.id) ? nil : 4).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if expanded.contains(entry.id) && !entry.original.isEmpty {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text("ORIGINAL").font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
                                        Text(entry.original).font(.system(size: 14)).lineSpacing(6).textSelection(.enabled)
                                    }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                                        .background(WorkspaceDesign.inset, in: RoundedRectangle(cornerRadius: 12))
                                }
                                HStack {
                                    Button(expanded.contains(entry.id) ? "Collapse" : "Read & compare") {
                                        if expanded.contains(entry.id) { expanded.remove(entry.id) } else { expanded.insert(entry.id) }
                                    }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary)
                                    Spacer()
                                    Button(copiedID == entry.id ? "Copied" : "Copy corrected") {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(entry.corrected, forType: .string)
                                        copiedID = entry.id
                                    }.buttonStyle(WorkspaceButtonStyle()).controlSize(.small)
                                }
                            }.padding(24).background(WorkspaceDesign.surface, in: RoundedRectangle(cornerRadius: 18))
                                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(WorkspaceDesign.border))
                        }
                    }.padding(28).frame(maxWidth: 940).frame(maxWidth: .infinity)
                }
            }
        }.background(WorkspaceDesign.canvas)
        .confirmationDialog("Clear correction history?", isPresented: $confirmClear) {
            Button("Clear history", role: .destructive) { correctionLogStore.clear() }
        } message: { Text("This removes the saved originals and corrections from this Mac.") }
    }
}
