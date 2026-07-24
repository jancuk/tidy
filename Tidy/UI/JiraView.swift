import AppKit
import SwiftUI

struct JiraView: View {
    @EnvironmentObject private var jiraService: JiraService
    @AppStorage(AppDefaults.jiraProjectKey) private var projectKey = ""
    @AppStorage(AppDefaults.jiraAssigneeAccountID) private var assigneeAccountID = ""

    @AppStorage(AppDefaults.jiraWorkspaceMode) private var modeRawValue = JiraWorkspaceMode.issues.rawValue
    @State private var selectedIssueID: JiraIssue.ID?
    @State private var searchText = ""
    @State private var selectedStatuses: Set<String> = []
    @State private var selectedPriorities: Set<String> = []
    @State private var selectedTypes: Set<String> = []
    @State private var isFindingCurrentUser = false
    @State private var isScopePresented = false

    var body: some View {
        VStack(spacing: 0) {
            workspaceHeader
            Divider().opacity(0.55)
            workspaceContent
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onChange(of: jiraService.issues) { _, _ in selectFirstIssueIfNeeded() }
        .onChange(of: jiraService.requestedIssueID) { _, issueID in
            guard let issueID else { return }
            selectedIssueID = issueID
            mode = .issues
        }
        .onChange(of: jiraService.notificationCenterRequest) { _, _ in
            mode = .notifications
        }
    }

    // MARK: - Workspace shell

    private var workspaceHeader: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.gradient)
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 1) {
                Text("Jira")
                    .font(.system(size: 17, weight: .bold))
                Text(projectKey.isEmpty ? "Active sprint workspace" : "\(projectKey.uppercased()) · Active sprint")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
            }

            workspaceTabs
                .padding(.leading, 12)

            Spacer()

            Button {
                isScopePresented.toggle()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "scope")
                    Text(scopeLabel)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color(NSColor.tertiaryLabelColor))
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .popover(isPresented: $isScopePresented, arrowEdge: .bottom) {
                scopePopover
            }

            Button(action: refresh) {
                if jiraService.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Refresh Jira")
            .disabled(!canRefresh || jiraService.isLoading)
        }
        .padding(.horizontal, 20)
        .frame(height: 68)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var workspaceTabs: some View {
        HStack(spacing: 2) {
            workspaceTab(.issues, icon: "rectangle.stack")
            workspaceTab(.notifications, icon: "bell")
        }
        .padding(3)
        .background(Color(NSColor.windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(NSColor.separatorColor).opacity(0.55), lineWidth: 0.5)
        )
    }

    private func workspaceTab(_ tab: JiraWorkspaceMode, icon: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.14)) { mode = tab }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(tab.title)
                if tab == .notifications, jiraService.unreadCount > 0 {
                    Text("\(jiraService.unreadCount)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.red, in: Capsule())
                }
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(mode == tab ? Color(NSColor.labelColor) : Color(NSColor.secondaryLabelColor))
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(
                mode == tab ? Color(NSColor.controlBackgroundColor) : .clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .shadow(color: mode == tab ? .black.opacity(0.08) : .clear, radius: 2, y: 1)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var workspaceContent: some View {
        if !jiraService.isConfigured {
            setupEmptyState
        } else if jiraService.isLoading && jiraService.issues.isEmpty {
            issueWorkspace
        } else if let error = jiraService.errorMessage, jiraService.issues.isEmpty {
            errorState(error)
        } else if mode == .notifications {
            JiraNotificationCenterView(
                notifications: jiraService.notifications,
                unreadIDs: jiraService.unreadNotificationIDs,
                onOpen: openNotification,
                onMarkAllRead: jiraService.markAllNotificationsRead
            )
        } else if jiraService.issues.isEmpty {
            issueWorkspace
        } else {
            issueWorkspace
        }
    }

    private var setupEmptyState: some View {
        ContentUnavailableView {
            Label("Connect Jira Cloud", systemImage: "link.badge.plus")
        } description: {
            Text("Add your Jira site, account email, and API token to start.")
        } actions: {
            SettingsLink {
                Text("Open Jira Settings")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Jira couldn’t sync", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again", action: refresh)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Scope

    private var scopePopover: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Sprint scope")
                    .font(.system(size: 14, weight: .bold))
                Text("Choose which active-sprint tickets appear.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Project key")
                    .font(.system(size: 11, weight: .semibold))
                TextField("e.g. ENG", text: $projectKey)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Assignee account ID")
                        .font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Text("Optional")
                        .font(.system(size: 9))
                        .foregroundStyle(Color(NSColor.tertiaryLabelColor))
                }
                TextField("All assignees", text: $assigneeAccountID)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button {
                    findCurrentUser()
                } label: {
                    if isFindingCurrentUser {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Use Me", systemImage: "person.crop.circle.badge.checkmark")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isFindingCurrentUser)

                if !assigneeAccountID.isEmpty {
                    Button("Show Everyone") { assigneeAccountID = "" }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                }

                Spacer()
                Button("Apply") {
                    isScopePresented = false
                    resetFilters()
                    refresh()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(projectKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 330)
    }

    // MARK: - Issue browser

    private var issueWorkspace: some View {
        HStack(spacing: 0) {
            ticketSidebar
                .frame(width: 360)
            Divider().opacity(0.65)

            if let selectedIssue {
                JiraIssueDetailView(issue: selectedIssue)
                    .environmentObject(jiraService)
                    .id(selectedIssue.id)
            } else {
                ContentUnavailableView(
                    "Select a ticket",
                    systemImage: "rectangle.and.hand.point.up.left",
                    description: Text("Choose a ticket to review its conversation and activity.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var ticketSidebar: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                searchField
                statusFilterBar
                filterRow
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor))

            Divider().opacity(0.55)

            if jiraService.isLoading && jiraService.issues.isEmpty {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Syncing active sprint…")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(NSColor.secondaryLabelColor))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredIssues.isEmpty {
                if jiraService.issues.isEmpty {
                    ContentUnavailableView {
                        Label("Ready to sync", systemImage: "arrow.triangle.2.circlepath")
                    } description: {
                        Text("Load tickets from your active Jira sprint when you're ready.")
                    } actions: {
                        Button("Load Sprint", action: refresh)
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView.search(text: searchText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(filteredIssues) { issue in
                            Button {
                                selectedIssueID = issue.id
                            } label: {
                                JiraIssueRow(issue: issue, isSelected: selectedIssueID == issue.id)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(10)
                }
            }

            Divider().opacity(0.55)
            HStack {
                Text("\(filteredIssues.count) of \(jiraService.issues.count) tickets")
                Spacer()
                if let lastUpdated = jiraService.lastUpdated {
                    Text("Synced \(lastUpdated, style: .relative)")
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(Color(NSColor.tertiaryLabelColor))
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Color(NSColor.controlBackgroundColor))
        }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color(NSColor.tertiaryLabelColor))
            TextField("Search key, title, or status", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(NSColor.tertiaryLabelColor))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 31)
        .background(Color(NSColor.textBackgroundColor), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color(NSColor.separatorColor).opacity(0.55), lineWidth: 0.5)
        )
    }

    private var statusFilterBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                statusFilterButton(title: "All", isSelected: selectedStatuses.isEmpty) {
                    selectedStatuses.removeAll()
                }

                ForEach(Array(JiraWorkflowStatus.allCases.prefix(3))) { status in
                    workflowStatusButton(status)
                }
            }

            HStack(spacing: 6) {
                ForEach(Array(JiraWorkflowStatus.allCases.dropFirst(3))) { status in
                    workflowStatusButton(status)
                }
            }
        }
        .accessibilityLabel("Filter by Jira status")
    }

    private func workflowStatusButton(_ status: JiraWorkflowStatus) -> some View {
        statusFilterButton(
            title: status.rawValue,
            isSelected: selectedStatuses.contains(status.rawValue),
            tint: jiraWorkflowStatusColor(status)
        ) {
            if selectedStatuses.contains(status.rawValue) {
                selectedStatuses.remove(status.rawValue)
            } else {
                selectedStatuses.insert(status.rawValue)
            }
        }
    }

    private func statusFilterButton(
        title: String,
        isSelected: Bool,
        tint: Color = .accentColor,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if isSelected && title != "All" {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                }
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color.white : Color(NSColor.secondaryLabelColor))
            .padding(.horizontal, 9)
            .frame(height: 25)
            .background(
                isSelected ? tint : Color(NSColor.textBackgroundColor),
                in: Capsule()
            )
            .overlay {
                if !isSelected {
                    Capsule()
                        .stroke(Color(NSColor.separatorColor).opacity(0.65), lineWidth: 0.5)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var filterRow: some View {
        HStack(spacing: 6) {
            JiraMultiFilterMenu(
                title: "Priority",
                icon: "flag",
                options: availablePriorities,
                selection: $selectedPriorities
            )
            JiraMultiFilterMenu(
                title: "Type",
                icon: "square.stack.3d.up",
                options: availableTypes,
                selection: $selectedTypes
            )
            Spacer()
            if hasActiveFilters {
                Button("Clear", action: resetFilters)
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .font(.system(size: 10, weight: .medium))
            }
        }
    }

    private var filteredIssues: [JiraIssue] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return jiraService.issues.filter { issue in
            let matchesQuery = query.isEmpty
                || issue.key.localizedCaseInsensitiveContains(query)
                || issue.fields.summary.localizedCaseInsensitiveContains(query)
                || issue.fields.status.name.localizedCaseInsensitiveContains(query)
            let matchesStatus = selectedStatuses.isEmpty || selectedStatuses.contains { selectedStatus in
                JiraWorkflowStatus(rawValue: selectedStatus)?.matches(issue.fields.status.name) == true
            }
            let matchesPriority = selectedPriorities.isEmpty || selectedPriorities.contains(issue.fields.priority?.name ?? "No priority")
            let matchesType = selectedTypes.isEmpty || selectedTypes.contains(issue.fields.issueType.name)
            return matchesQuery && matchesStatus && matchesPriority && matchesType
        }
    }

    private var availablePriorities: [String] {
        Array(Set(jiraService.issues.map { $0.fields.priority?.name ?? "No priority" })).sorted()
    }

    private var availableTypes: [String] {
        Array(Set(jiraService.issues.map(\.fields.issueType.name))).sorted()
    }

    private var hasActiveFilters: Bool {
        !selectedStatuses.isEmpty || !selectedPriorities.isEmpty || !selectedTypes.isEmpty
    }

    private var selectedIssue: JiraIssue? {
        jiraService.issues.first { $0.id == selectedIssueID }
    }

    private var scopeLabel: String {
        let project = projectKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !project.isEmpty else { return "Set sprint scope" }
        return assigneeAccountID.isEmpty ? "\(project.uppercased()) · Everyone" : "\(project.uppercased()) · My tickets"
    }

    private var canRefresh: Bool {
        jiraService.isConfigured && !projectKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var mode: JiraWorkspaceMode {
        get { JiraWorkspaceMode(rawValue: modeRawValue) ?? .issues }
        nonmutating set { modeRawValue = newValue.rawValue }
    }

    // MARK: - Actions

    private func refresh() {
        Task {
            await jiraService.loadActiveSprintIssues(
                projectKey: projectKey,
                assigneeAccountID: assigneeAccountID
            )
            selectFirstIssueIfNeeded()
        }
    }

    private func findCurrentUser() {
        isFindingCurrentUser = true
        Task {
            defer { isFindingCurrentUser = false }
            do {
                assigneeAccountID = try await jiraService.testConnection().accountId
            } catch {
                // Connection errors remain available through the main Jira state.
            }
        }
    }

    private func selectFirstIssueIfNeeded() {
        if selectedIssue == nil { selectedIssueID = filteredIssues.first?.id ?? jiraService.issues.first?.id }
    }

    private func resetFilters() {
        selectedStatuses.removeAll()
        selectedPriorities.removeAll()
        selectedTypes.removeAll()
    }

    private func openNotification(_ notification: JiraNotification) {
        jiraService.markNotificationRead(notification)
        selectedIssueID = notification.issueID
        mode = .issues
    }
}

private enum JiraWorkspaceMode: String {
    case issues
    case notifications

    var title: String {
        switch self {
        case .issues: "Tickets"
        case .notifications: "Notifications"
        }
    }
}

// MARK: - Ticket list

private struct JiraMultiFilterMenu: View {
    let title: String
    let icon: String
    let options: [String]
    @Binding var selection: Set<String>

    var body: some View {
        Menu {
            if !selection.isEmpty {
                Button("All \(title.lowercased())") { selection.removeAll() }
                Divider()
            }
            ForEach(options, id: \.self) { option in
                Button {
                    if selection.contains(option) {
                        selection.remove(option)
                    } else {
                        selection.insert(option)
                    }
                } label: {
                    if selection.contains(option) {
                        Label(option, systemImage: "checkmark")
                    } else {
                        Text(option)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                Text(title)
                if !selection.isEmpty {
                    Text("\(selection.count)")
                        .font(.system(size: 8, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.18), in: Capsule())
                }
            }
            .font(.system(size: 10, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}

private struct JiraIssueRow: View {
    let issue: JiraIssue
    let isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(jiraPriorityColor(issue.fields.priority?.name))
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Text(issue.key)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.accentColor)
                    JiraStatusBadge(issue: issue)
                    Spacer()
                    if let updated = issue.updatedDate {
                        Text(updated, style: .relative)
                            .font(.system(size: 9))
                            .foregroundStyle(Color(NSColor.tertiaryLabelColor))
                    }
                }

                Text(issue.fields.summary)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(NSColor.labelColor))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 5) {
                    Label(issue.fields.issueType.name, systemImage: "square.stack.3d.up")
                    Text("·")
                    Label(issue.fields.priority?.name ?? "No priority", systemImage: "flag.fill")
                        .foregroundStyle(jiraPriorityColor(issue.fields.priority?.name))
                    if let assignee = issue.fields.assignee?.displayName {
                        Text("·")
                        Text(assignee)
                            .lineLimit(1)
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(Color(NSColor.secondaryLabelColor))
            }
            .padding(.vertical, 10)
            .padding(.trailing, 10)
        }
        .padding(.leading, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isSelected
                ? Color.accentColor.opacity(0.13)
                : (isHovered ? Color(NSColor.controlBackgroundColor) : Color.clear),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(isSelected ? Color.accentColor.opacity(0.32) : Color.clear, lineWidth: 0.7)
        )
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.1), value: isHovered)
    }
}

private struct JiraStatusBadge: View {
    let issue: JiraIssue

    var body: some View {
        Text(issue.fields.status.name)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(jiraStatusColor(issue.statusGroup))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(jiraStatusColor(issue.statusGroup).opacity(0.12), in: Capsule())
    }
}

// MARK: - Issue detail & comments

private struct JiraIssueDetailView: View {
    @EnvironmentObject private var jiraService: JiraService
    let issue: JiraIssue
    @State private var commentText = ""
    @State private var isPosting = false
    @State private var feedback: CommentFeedback?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                issueHeader
                metadataGrid
                Divider().opacity(0.55)
                conversationSection
                commentComposer
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 26)
            .frame(maxWidth: 820, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .task(id: issue.id) {
            await jiraService.loadComments(for: issue)
        }
    }

    private var issueHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(issue.key)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.accentColor)
                Text("·")
                    .foregroundStyle(Color(NSColor.tertiaryLabelColor))
                Text(issue.fields.issueType.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
                Spacer()
                Button {
                    if let url = jiraService.issueURL(for: issue) { NSWorkspace.shared.open(url) }
                } label: {
                    Label("Open in Jira", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Text(issue.fields.summary)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color(NSColor.labelColor))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var metadataGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            JiraMetadataCard(
                title: "Status",
                value: issue.fields.status.name,
                icon: issue.statusGroup.systemImage,
                tint: jiraStatusColor(issue.statusGroup)
            )
            JiraMetadataCard(
                title: "Priority",
                value: issue.fields.priority?.name ?? "No priority",
                icon: "flag.fill",
                tint: jiraPriorityColor(issue.fields.priority?.name)
            )
            JiraMetadataCard(
                title: "Assignee",
                value: issue.fields.assignee?.displayName ?? "Unassigned",
                icon: "person.fill",
                tint: .purple
            )
            JiraMetadataCard(
                title: "Last updated",
                value: issue.updatedDate.map { $0.formatted(.relative(presentation: .named)) } ?? "Unknown",
                icon: "clock.fill",
                tint: .secondary
            )
        }
    }

    private var conversationSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Conversation", systemImage: "bubble.left.and.bubble.right")
                    .font(.system(size: 14, weight: .bold))
                Text("\(comments.count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(NSColor.controlBackgroundColor), in: Capsule())
                Spacer()
                Button {
                    Task { await jiraService.loadComments(for: issue) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Refresh comments")
            }

            if jiraService.loadingCommentIssueIDs.contains(issue.id) && comments.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading comments…")
                }
                .font(.system(size: 11))
                .foregroundStyle(Color(NSColor.secondaryLabelColor))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 20)
            } else if let error = jiraService.commentErrorsByIssueID[issue.id], comments.isEmpty {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.red)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            } else if comments.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "bubble.left")
                        .foregroundStyle(Color(NSColor.tertiaryLabelColor))
                    Text("No comments yet. Start the conversation below.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(NSColor.secondaryLabelColor))
                }
                .padding(.vertical, 12)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(comments) { jiraComment in
                        JiraCommentRow(comment: jiraComment, issue: issue)
                            .environmentObject(jiraService)
                    }
                }
            }
        }
    }

    private var commentComposer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add a comment")
                .font(.system(size: 13, weight: .semibold))

            ZStack(alignment: .topLeading) {
                if commentText.isEmpty {
                    Text("Share an update, ask a question, or leave context…")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(NSColor.placeholderTextColor))
                        .padding(.horizontal, 13)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $commentText)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(7)
                    .frame(minHeight: 100, maxHeight: 170)
            }
            .background(Color(NSColor.textBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color(NSColor.separatorColor).opacity(0.65), lineWidth: 0.5)
            )

            HStack {
                Text("⌘↩ to post")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(NSColor.tertiaryLabelColor))
                if let feedback {
                    Label(feedback.message, systemImage: feedback.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(feedback.isError ? Color.red : Color.green)
                        .lineLimit(1)
                }
                Spacer()
                Button(action: postComment) {
                    if isPosting {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Posting…")
                        }
                    } else {
                        Label("Post Comment", systemImage: "paperplane.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPosting)
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5)
        )
    }

    private var comments: [JiraComment] {
        jiraService.comments(for: issue)
    }

    private func postComment() {
        let text = commentText
        isPosting = true
        feedback = nil
        Task {
            defer { isPosting = false }
            do {
                try await jiraService.addComment(text, to: issue)
                commentText = ""
                feedback = CommentFeedback(message: "Posted", isError: false)
            } catch {
                feedback = CommentFeedback(message: error.localizedDescription, isError: true)
            }
        }
    }

    private struct CommentFeedback {
        let message: String
        let isError: Bool
    }
}

private struct JiraMetadataCard: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(tint.opacity(0.12))
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 29, height: 29)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color(NSColor.tertiaryLabelColor))
                    .textCase(.uppercase)
                Text(value)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(NSColor.labelColor))
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color(NSColor.separatorColor).opacity(0.45), lineWidth: 0.5)
        )
    }
}

private struct JiraCommentRow: View {
    @EnvironmentObject private var jiraService: JiraService
    let comment: JiraComment
    let issue: JiraIssue
    @State private var isEditing = false
    @State private var editText = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Text(initials)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(avatarColor.gradient, in: Circle())

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text(comment.author.displayName)
                        .font(.system(size: 11, weight: .semibold))
                    if comment.author.accountId == jiraService.currentUser?.accountId {
                        Text("You")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.1), in: Capsule())
                    }
                    if let created = comment.createdDate {
                        Text(created, style: .relative)
                            .font(.system(size: 9))
                            .foregroundStyle(Color(NSColor.tertiaryLabelColor))
                    }
                    if comment.wasEdited {
                        Text("edited")
                            .font(.system(size: 9))
                            .foregroundStyle(Color(NSColor.tertiaryLabelColor))
                    }
                    Spacer()
                    if canEdit && !isEditing {
                        Menu {
                            Button {
                                editText = comment.text
                                isEditing = true
                            } label: {
                                Label("Edit Comment", systemImage: "pencil")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .frame(width: 22, height: 18)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                }

                if isEditing {
                    TextEditor(text: $editText)
                        .font(.system(size: 12))
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .frame(minHeight: 76)
                        .background(Color(NSColor.textBackgroundColor), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(Color.accentColor.opacity(0.5), lineWidth: 0.8)
                        )
                    HStack {
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 9))
                                .foregroundStyle(Color.red)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button("Cancel") { isEditing = false }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        Button {
                            save()
                        } label: {
                            isSaving ? AnyView(ProgressView().controlSize(.small)) : AnyView(Text("Save"))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                    }
                } else {
                    Text(comment.text)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(NSColor.labelColor))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(13)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(NSColor.separatorColor).opacity(0.45), lineWidth: 0.5)
        )
    }

    private var canEdit: Bool {
        comment.author.accountId != nil && comment.author.accountId == jiraService.currentUser?.accountId
    }

    private var initials: String {
        let parts = comment.author.displayName.split(separator: " ")
        return parts.prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }

    private var avatarColor: Color {
        let palette: [Color] = [.blue, .purple, .teal, .indigo, .orange]
        return palette[abs(comment.author.displayName.hashValue) % palette.count]
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            defer { isSaving = false }
            do {
                try await jiraService.updateComment(editText, comment: comment, on: issue)
                isEditing = false
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Notification center

private struct JiraNotificationCenterView: View {
    let notifications: [JiraNotification]
    let unreadIDs: Set<String>
    let onOpen: (JiraNotification) -> Void
    let onMarkAllRead: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Sprint notifications")
                            .font(.system(size: 20, weight: .bold))
                        Text("Status, priority, and assignee changes from tickets in your current sprint scope.")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(NSColor.secondaryLabelColor))
                    }
                    Spacer()
                    if !unreadIDs.isEmpty {
                        Button("Mark All Read", action: onMarkAllRead)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }

                if notifications.first?.isFallback == true {
                    Label(
                        "Detailed changelog access isn’t available for this account, so Tidy is showing recently updated tickets.",
                        systemImage: "info.circle"
                    )
                    .font(.system(size: 10))
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                if notifications.isEmpty {
                    ContentUnavailableView(
                        "No recent changes",
                        systemImage: "bell.slash",
                        description: Text("Refresh Jira to check your active sprint.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(notifications) { notification in
                            Button {
                                onOpen(notification)
                            } label: {
                                JiraNotificationRow(
                                    notification: notification,
                                    isUnread: unreadIDs.contains(notification.id)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
}

private struct JiraNotificationRow: View {
    let notification: JiraNotification
    let isUnread: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(isUnread ? Color.accentColor : Color.clear)
                .frame(width: 7, height: 7)
                .padding(.top, 7)

            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(notificationTint.opacity(0.12))
                Image(systemName: notificationIcon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(notificationTint)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(notification.issueKey)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.accentColor)
                    Text(notification.title)
                        .font(.system(size: 12, weight: isUnread ? .bold : .semibold))
                    Spacer()
                    Text(notification.createdAt, style: .relative)
                        .font(.system(size: 9))
                        .foregroundStyle(Color(NSColor.tertiaryLabelColor))
                }
                Text(notification.detail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(NSColor.labelColor))
                Text(notification.issueSummary)
                    .font(.system(size: 10))
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Label(notification.priority, systemImage: "flag.fill")
                        .foregroundStyle(jiraPriorityColor(notification.priority))
                    Text("·")
                    Text(notification.status)
                    if let actor = notification.actor {
                        Text("·")
                        Text(actor)
                    }
                }
                .font(.system(size: 9))
                .foregroundStyle(Color(NSColor.tertiaryLabelColor))
            }
        }
        .padding(13)
        .background(
            isHovered ? Color(NSColor.controlBackgroundColor) : Color.clear,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(NSColor.separatorColor).opacity(0.4), lineWidth: 0.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { isHovered = $0 }
    }

    private var notificationIcon: String {
        let title = notification.title.lowercased()
        if title.contains("priority") { return "flag.fill" }
        if title.contains("assignee") { return "person.fill" }
        if title.contains("status") { return "arrow.triangle.2.circlepath" }
        return "bell.fill"
    }

    private var notificationTint: Color {
        let title = notification.title.lowercased()
        if title.contains("priority") { return jiraPriorityColor(notification.priority) }
        if title.contains("assignee") { return .purple }
        if title.contains("status") { return .blue }
        return .orange
    }
}

// MARK: - Visual semantics

private func jiraStatusColor(_ group: JiraStatusGroup) -> Color {
    switch group {
    case .all: .secondary
    case .toDo: .orange
    case .inProgress: .blue
    case .done: .green
    }
}

private func jiraWorkflowStatusColor(_ status: JiraWorkflowStatus) -> Color {
    switch status {
    case .toDo: .orange
    case .codeReview: .purple
    case .readyForRelease: .teal
    case .doneReleaseReady: .green
    case .inQA: .indigo
    case .inProgress: .blue
    }
}

private func jiraPriorityColor(_ priority: String?) -> Color {
    let value = priority?.lowercased() ?? ""
    if value.contains("highest") || value.contains("blocker") || value.contains("critical") || value.contains("p0") {
        return .red
    }
    if value.contains("high") || value.contains("p1") {
        return .orange
    }
    if value.contains("low") || value.contains("p3") || value.contains("p4") {
        return .green
    }
    return .blue
}
