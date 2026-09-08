import SwiftUI

struct NotificationCenterView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var notificationService: UnifiedNotificationService
    @State private var expandedSources: Set<MCPIntegrationSource> = []
    @State private var selectedSource: MCPIntegrationSource?
    @State private var search = ""

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceHeader(title: "Notifications", subtitle: "Your work, in perspective.") {
                Button { appState.openMCPSettings() } label: { Image(systemName: "slider.horizontal.3") }
                    .accessibilityLabel("Integration settings").help("Integration settings")
                Button { Task { await notificationService.refresh() } } label: {
                    if notificationService.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else { Label("Refresh", systemImage: "arrow.clockwise") }
                }.disabled(notificationService.isRefreshing)
            }
            navigation
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if search.isEmpty && selectedSource == nil { introduction }
                    connectionState
                    if selectedSource == nil && search.isEmpty { briefing }
                    HStack {
                        Text(search.isEmpty ? (selectedSource?.title ?? "Across your sources") : "Search results")
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Label("Read-only", systemImage: "eye").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    if visibleSources.isEmpty {
                        WorkspaceEmptyState(title: "No matching updates", detail: "Try another phrase or clear your search.", icon: "magnifyingglass")
                    }
                    ForEach(visibleSources) { source in sourceCard(source) }
                }
                .padding(.horizontal, 32).padding(.vertical, 30)
                .frame(maxWidth: 930).frame(maxWidth: .infinity)
            }
        }.background(WorkspaceDesign.canvas)
    }

    private var navigation: some View {
        HStack(spacing: 7) {
            filterButton("Briefing", source: nil)
            ForEach(UnifiedNotificationService.notificationSources) { source in
                filterButton(source == .googleCalendar ? "Calendar" : source.title, source: source)
            }
            Spacer(minLength: 12)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search updates", text: $search).textFieldStyle(.plain)
                    .accessibilityLabel("Search notification summaries")
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).accessibilityLabel("Clear notification search")
                }
            }.font(.system(size: 12)).padding(9).frame(width: 190)
                .background(WorkspaceDesign.inset, in: RoundedRectangle(cornerRadius: 9))
        }.padding(.horizontal, 28).padding(.vertical, 12)
            .overlay(alignment: .bottom) { WorkspaceDesign.border.frame(height: 1) }
    }

    private func filterButton(_ title: String, source: MCPIntegrationSource?) -> some View {
        Button { selectedSource = source } label: {
            HStack(spacing: 6) {
                if let source { Image(systemName: source.notificationSystemImage) }
                Text(title)
                if let source, notificationService.sourceErrors[source] != nil {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                }
            }.font(.system(size: 12, weight: selectedSource == source ? .semibold : .regular))
                .foregroundStyle(selectedSource == source ? Color.primary : Color.secondary)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(selectedSource == source ? WorkspaceDesign.inset : .clear, in: Capsule())
        }.buttonStyle(.plain).accessibilityAddTraits(selectedSource == source ? .isSelected : [])
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Text("A clearer view of your day.").font(.system(size: 32, design: .serif))
            Text("Catch up on conversations, replies, and the meetings ahead.")
                .font(.system(size: 14)).foregroundStyle(.secondary)
        }.padding(.top, 4)
    }

    private var connectionState: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: notificationService.sourceErrors.isEmpty ? "clock" : "exclamationmark.circle")
                .foregroundStyle(notificationService.sourceErrors.isEmpty ? Color.secondary : Color.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(connectionTitle).font(.system(size: 12, weight: .medium))
                if let date = notificationService.lastUpdatedAt {
                    Text("Last refresh: \(date.formatted(date: .abbreviated, time: .shortened)). Saved summaries may have changed at the source.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    Text("Connect your sources in settings, then refresh when you're ready.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if notificationService.digests.isEmpty {
                Button("Connect sources") { appState.openMCPSettings() }.buttonStyle(WorkspaceButtonStyle())
            }
        }.padding(14).background(WorkspaceDesign.inset, in: RoundedRectangle(cornerRadius: 12))
    }

    private var connectionTitle: String {
        if notificationService.isRefreshing { return "Checking your sources…" }
        if !notificationService.sourceErrors.isEmpty { return "Some sources couldn't refresh. Check the details below." }
        if !notificationService.digests.isEmpty && !notificationService.connectionStatus.hasPrefix("Connected") {
            return "Showing saved summaries · connection not checked this session"
        }
        return notificationService.connectionStatus
    }

    private var briefing: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 9) {
                Image("TidyLogo").resizable().frame(width: 26, height: 26)
                Text("Your briefing").font(.system(size: 14, weight: .semibold))
                Spacer()
                if let date = notificationService.briefing?.generatedAt {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            if notificationService.isRefreshing && notificationService.briefing == nil {
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text("Putting the pieces together…").font(.system(size: 14)).foregroundStyle(.secondary)
                }.padding(.vertical, 22)
            } else if let brief = notificationService.briefing, !NotificationReadingContent.containsSourceData(brief.summary) {
                NotificationMarkdownView(text: brief.summary)
            } else if notificationService.briefing != nil {
                Text("This saved briefing needs a fresh summary.").font(.system(size: 19, design: .serif))
                Text("Some source data couldn't be summarized cleanly. Read the available source summaries below, or refresh to try again.")
                    .font(.system(size: 14)).foregroundStyle(.secondary).lineSpacing(5)
            } else {
                Text("The important things, in one place.").font(.system(size: 24, design: .serif))
                Text("Your briefing brings together source updates so you can decide what deserves your attention. Refreshing reads your sources without posting messages or changing tasks.")
                    .font(.system(size: 14)).foregroundStyle(.secondary).lineSpacing(5)
            }
        }.padding(26).frame(maxWidth: .infinity, alignment: .leading)
            .background(WorkspaceDesign.surface, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(WorkspaceDesign.border))
    }

    private func sourceCard(_ source: MCPIntegrationSource) -> some View {
        let digest = notificationService.digests.first { $0.source == source }
        let error = notificationService.sourceErrors[source]
        let readable = digest.flatMap(NotificationReadingContent.readableSummary)
        return VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: source.notificationSystemImage).font(.system(size: 17))
                    .foregroundStyle(tint(source)).frame(width: 40, height: 40)
                    .background(tint(source).opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text(source.title).font(.system(size: 14, weight: .semibold))
                    Text(source.notificationSubtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Text(error != nil ? "Refresh failed" : notificationService.isRefreshing ? "Refreshing…" : digest != nil ? "Saved summary" : "Not loaded")
                    .font(.system(size: 11)).foregroundStyle(error != nil ? Color.orange : Color.secondary)
            }
            if let error {
                DisclosureGroup("Connection details") {
                    Text(error).font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                    Button("Open integration settings") { appState.openMCPSettings() }.buttonStyle(WorkspaceButtonStyle())
                }.font(.system(size: 12)).foregroundStyle(.orange)
            }
            if let readable, !readable.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if selectedSource != nil || !search.isEmpty {
                    NotificationMarkdownView(text: readable)
                } else {
                    Text(.init(readable)).font(.system(size: 14)).lineSpacing(5).lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button { selectedSource = source } label: { Label("Read summary", systemImage: "arrow.right") }
                        .buttonStyle(.plain).font(.system(size: 12, weight: .medium))
                }
            } else {
                Text(digest == nil ? "No summary yet. Refresh to check this source." : "The saved text contains incomplete source data. Refresh for a readable summary.")
                    .font(.system(size: 14)).foregroundStyle(.secondary).lineSpacing(5)
            }
            if let digest {
                HStack {
                    Text("Saved \(digest.fetchedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Button(expandedSources.contains(source) ? "Hide source details" : "Source details") {
                        if expandedSources.contains(source) { expandedSources.remove(source) }
                        else { expandedSources.insert(source) }
                    }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                if expandedSources.contains(source) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Retrieved with \(digest.toolName)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                        if !digest.rawPreview.isEmpty || readable == nil {
                            Text(digest.rawPreview.isEmpty ? digest.summary : digest.rawPreview)
                                .font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                        } else {
                            Text("Original source data is not retained between sessions.").font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .background(WorkspaceDesign.inset, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }.padding(22).background(WorkspaceDesign.surface, in: RoundedRectangle(cornerRadius: 17))
            .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(WorkspaceDesign.border))
    }

    private var visibleSources: [MCPIntegrationSource] {
        let sources = selectedSource.map { [$0] } ?? UnifiedNotificationService.notificationSources
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sources }
        return sources.filter { source in
            let digest = notificationService.digests.first { $0.source == source }
            let text = [source.title, digest.flatMap(NotificationReadingContent.readableSummary) ?? "", notificationService.sourceErrors[source] ?? ""].joined(separator: " ")
            return text.localizedCaseInsensitiveContains(query)
        }
    }

    private func tint(_ source: MCPIntegrationSource) -> Color {
        switch source {
        case .slack: .purple
        case .gmail: .red
        case .googleCalendar: .blue
        case .jira: .indigo
        case .newRelic: .green
        }
    }
}

private struct NotificationMarkdownView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                        HStack(alignment: .top, spacing: 12) {
                            Circle().fill(Color.secondary).frame(width: 4, height: 4).padding(.top, 9)
                            Text(.init(String(trimmed.dropFirst(2)))).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        Text(.init(trimmed)).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }.font(.system(size: 15)).lineSpacing(6).textSelection(.enabled)
    }
}
