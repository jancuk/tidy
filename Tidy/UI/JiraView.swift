import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct JiraView: View {
    @EnvironmentObject private var jiraService: JiraService
    @AppStorage(AppDefaults.jiraProjectKey) private var projectKey = ""
    @AppStorage(AppDefaults.jiraAssigneeAccountID) private var assigneeAccountID = ""

    @AppStorage(AppDefaults.jiraWorkspaceMode) private var modeRawValue = JiraWorkspaceMode.workbench.rawValue
    @State private var selectedIssueID: JiraIssue.ID?
    @State private var searchText = ""
    @State private var selectedSavedView = JiraSavedView.all
    @State private var selectedStatuses: Set<String> = []
    @State private var selectedPriorities: Set<String> = []
    @State private var selectedTypes: Set<String> = []
    @State private var commentDrafts: [JiraIssue.ID: String] = [:]
    @State private var commentMentions: [JiraIssue.ID: [JiraUser]] = [:]
    @State private var commentDates: [JiraIssue.ID: [JiraCommentDateToken]] = [:]
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
            mode = .workbench
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
            workspaceTab(.workbench, icon: "hammer")
            workspaceTab(.standup, icon: "person.3.fill")
            workspaceTab(.pulse, icon: "chart.bar.xaxis")
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
        } else if mode == .standup, !jiraService.issues.isEmpty {
            JiraStandupView(
                issues: jiraService.issues,
                onOpenIssue: openIssue
            )
            .environmentObject(jiraService)
        } else if mode == .pulse, !jiraService.issues.isEmpty {
            JiraProjectPulseView(
                issues: jiraService.issues,
                notifications: jiraService.notifications,
                projectKey: projectKey,
                isFilteredToAssignee: !assigneeAccountID.isEmpty,
                onOpenIssue: openIssue
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
                JiraIssueDetailView(
                    issue: selectedIssue,
                    commentText: Binding(
                        get: { commentDrafts[selectedIssue.id] ?? "" },
                        set: { commentDrafts[selectedIssue.id] = $0 }
                    ),
                    mentions: Binding(
                        get: { commentMentions[selectedIssue.id] ?? [] },
                        set: { commentMentions[selectedIssue.id] = $0 }
                    ),
                    dates: Binding(
                        get: { commentDates[selectedIssue.id] ?? [] },
                        set: { commentDates[selectedIssue.id] = $0 }
                    )
                )
                    .environmentObject(jiraService)
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
                savedViewBar
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

    private var savedViewBar: some View {
        HStack(spacing: 5) {
            ForEach(JiraSavedView.allCases) { savedView in
                Button {
                    withAnimation(.easeInOut(duration: 0.12)) { selectedSavedView = savedView }
                } label: {
                    Label(savedView.title, systemImage: savedView.systemImage)
                        .font(.system(size: 9, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(
                            selectedSavedView == savedView
                                ? Color.white
                                : Color(NSColor.secondaryLabelColor)
                        )
                        .padding(.horizontal, 8)
                        .frame(height: 23)
                        .background(
                            selectedSavedView == savedView
                                ? Color.accentColor
                                : Color(NSColor.textBackgroundColor),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .help(savedView.help)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            let matchesSavedView = selectedSavedView.matches(issue, currentUser: jiraService.currentUser)
            return matchesQuery && matchesStatus && matchesPriority && matchesType && matchesSavedView
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
        get { JiraWorkspaceMode(rawValue: modeRawValue) ?? .workbench }
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
        mode = .workbench
    }

    private func openIssue(_ issue: JiraIssue) {
        selectedIssueID = issue.id
        selectedSavedView = .all
        resetFilters()
        mode = .workbench
    }
}

private enum JiraWorkspaceMode: String {
    case workbench = "issues"
    case standup
    case pulse
    case notifications

    var title: String {
        switch self {
        case .workbench: "Workbench"
        case .standup: "Standup"
        case .pulse: "Project Pulse"
        case .notifications: "Inbox"
        }
    }
}

private enum JiraSavedView: String, CaseIterable, Identifiable {
    case all
    case myQueue
    case needsReview
    case inQA
    case readyToShip

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .myQueue: "My Queue"
        case .needsReview: "Review"
        case .inQA: "QA"
        case .readyToShip: "Ship"
        }
    }

    var systemImage: String {
        switch self {
        case .all: "square.grid.2x2"
        case .myQueue: "person.crop.circle"
        case .needsReview: "eye"
        case .inQA: "checkmark.seal"
        case .readyToShip: "shippingbox"
        }
    }

    var help: String {
        switch self {
        case .all: "All tickets in the current sprint scope"
        case .myQueue: "Tickets assigned to you"
        case .needsReview: "Tickets waiting for code review"
        case .inQA: "Tickets currently in QA"
        case .readyToShip: "Tickets ready for release"
        }
    }

    func matches(_ issue: JiraIssue, currentUser: JiraUser?) -> Bool {
        switch self {
        case .all:
            true
        case .myQueue:
            issue.fields.assignee?.accountId == currentUser?.accountId
        case .needsReview:
            JiraWorkflowStatus.codeReview.matches(issue.fields.status.name)
        case .inQA:
            JiraWorkflowStatus.inQA.matches(issue.fields.status.name)
        case .readyToShip:
            JiraWorkflowStatus.readyForRelease.matches(issue.fields.status.name)
                || JiraWorkflowStatus.doneReleaseReady.matches(issue.fields.status.name)
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
    @Binding var commentText: String
    @Binding var mentions: [JiraUser]
    @Binding var dates: [JiraCommentDateToken]
    @State private var isPosting = false
    @State private var feedback: CommentFeedback?
    @State private var transitionFeedback: CommentFeedback?
    @State private var mentionQuery: String?
    @State private var mentionSuggestions: [JiraUser] = []
    @State private var isSearchingMentions = false
    @State private var isDatePickerPresented = false
    @State private var selectedDate = Date()

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    issueHeader
                    metadataGrid
                    descriptionSection
                    Divider().opacity(0.55)
                    conversationSection
                }
                .padding(.horizontal, 30)
                .padding(.vertical, 26)
                .frame(maxWidth: 820, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            Divider().opacity(0.65)

            VStack(spacing: 12) {
                workflowStrip
                Divider().opacity(0.45)
                commentComposer
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.bar)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .task(id: issue.id) {
            async let comments: Void = jiraService.loadComments(for: issue)
            async let transitions: Void = jiraService.loadTransitions(for: issue)
            _ = await (comments, transitions)
        }
        .task(id: mentionQuery) {
            guard let mentionQuery else {
                mentionSuggestions = []
                isSearchingMentions = false
                return
            }

            isSearchingMentions = true
            do {
                try await Task.sleep(for: .milliseconds(220))
                let users = try await jiraService.searchMentionUsers(matching: mentionQuery, for: issue)
                guard !Task.isCancelled else { return }
                mentionSuggestions = users
            } catch is CancellationError {
                return
            } catch {
                mentionSuggestions = []
            }
            isSearchingMentions = false
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

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Description", systemImage: "text.alignleft")
                .font(.system(size: 13, weight: .bold))

            let description = issue.fields.description?.plainText
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            Text(description.isEmpty ? "No description provided." : description)
                .font(.system(size: 12))
                .foregroundStyle(
                    description.isEmpty
                        ? Color(NSColor.tertiaryLabelColor)
                        : Color(NSColor.labelColor)
                )
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(
                    Color(NSColor.controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5)
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

    private var workflowStrip: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Label("Move ticket", systemImage: "arrow.triangle.branch")
                    .font(.system(size: 11, weight: .bold))
                Text(issue.fields.status.name)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(jiraStatusColor(issue.statusGroup))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(jiraStatusColor(issue.statusGroup).opacity(0.12), in: Capsule())
                if jiraService.loadingTransitionIssueIDs.contains(issue.id) {
                    ProgressView().controlSize(.small)
                }
                if let transitionFeedback {
                    Label(
                        transitionFeedback.message,
                        systemImage: transitionFeedback.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill"
                    )
                    .font(.system(size: 9))
                    .foregroundStyle(transitionFeedback.isError ? Color.red : Color.green)
                    .lineLimit(1)
                }
                Spacer()
                Menu {
                    ForEach(availableTransitions) { transition in
                        Button(transition.to.name) { move(using: transition) }
                    }
                } label: {
                    Label("Change Status", systemImage: "chevron.up.chevron.down")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(availableTransitions.isEmpty || isTransitioning)
            }

            HStack(spacing: 5) {
                ForEach(JiraWorkflowStatus.allCases) { status in
                    let transition = transition(to: status)
                    let isCurrent = status.matches(issue.fields.status.name)
                    Button {
                        if let transition { move(using: transition) }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: isCurrent ? "checkmark.circle.fill" : "circle")
                            Text(status.rawValue)
                                .lineLimit(1)
                        }
                        .font(.system(size: 9, weight: isCurrent ? .bold : .semibold))
                        .foregroundStyle(
                            isCurrent
                                ? Color.white
                                : jiraWorkflowStatusColor(status)
                        )
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, minHeight: 26)
                        .background(
                            isCurrent
                                ? jiraWorkflowStatusColor(status)
                                : jiraWorkflowStatusColor(status).opacity(transition == nil ? 0.05 : 0.11),
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(jiraWorkflowStatusColor(status).opacity(0.24), lineWidth: 0.5)
                        )
                        .opacity(!isCurrent && transition == nil ? 0.48 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(isCurrent || transition == nil || isTransitioning)
                    .help(isCurrent ? "Current status" : (transition == nil ? "Not available from the current status" : "Move to \(status.rawValue)"))
                }
            }
        }
    }

    private var commentComposer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Comment", systemImage: "bubble.left")
                    .font(.system(size: 11, weight: .bold))
                Spacer()
                Text("Draft and rich fields stay with this ticket")
                    .font(.system(size: 9))
                    .foregroundStyle(Color(NSColor.tertiaryLabelColor))
            }

            if mentionQuery != nil {
                mentionSuggestionsPanel
            }

            ZStack(alignment: .topLeading) {
                if commentText.isEmpty {
                    Text("Share progress, test notes, or a blocker…")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(NSColor.placeholderTextColor))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 9)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $commentText)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .padding(5)
                    .frame(minHeight: 62, maxHeight: 96)
            }
            .onChange(of: commentText) { _, newValue in
                handleComposerTextChange(newValue)
            }
            .background(Color(NSColor.textBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color(NSColor.separatorColor).opacity(0.65), lineWidth: 0.5)
            )

            HStack {
                Button {
                    insertMentionCommand()
                } label: {
                    Label("Mention", systemImage: "at")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Mention a Jira user")

                Button {
                    selectedDate = Date()
                    isDatePickerPresented = true
                } label: {
                    Label("Date", systemImage: "calendar")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Insert a Jira date")
                .popover(isPresented: $isDatePickerPresented, arrowEdge: .bottom) {
                    datePickerPopover
                }

                Text("@name · /date · ⌘↩")
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
    }

    private var mentionSuggestionsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Mention someone", systemImage: "at")
                    .font(.system(size: 10, weight: .semibold))
                Spacer()
                if isSearchingMentions {
                    ProgressView().controlSize(.mini)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)

            if !isSearchingMentions && mentionSuggestions.isEmpty {
                Text("No assignable Jira users found")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
            } else {
                ForEach(mentionSuggestions.prefix(6)) { user in
                    Button {
                        selectMention(user)
                    } label: {
                        HStack(spacing: 9) {
                            Text(initials(for: user.displayName))
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 24, height: 24)
                                .background(Color.accentColor.gradient, in: Circle())
                            VStack(alignment: .leading, spacing: 1) {
                                Text(user.displayName)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color(NSColor.labelColor))
                                if let emailAddress = user.emailAddress, !emailAddress.isEmpty {
                                    Text(emailAddress)
                                        .font(.system(size: 9))
                                        .foregroundStyle(Color(NSColor.secondaryLabelColor))
                                }
                            }
                            Spacer()
                            Image(systemName: "return")
                                .font(.system(size: 9))
                                .foregroundStyle(Color(NSColor.tertiaryLabelColor))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.accentColor.opacity(0.35), lineWidth: 0.75)
        )
    }

    private var datePickerPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Insert Jira date")
                .font(.system(size: 13, weight: .bold))
            DatePicker(
                "Date",
                selection: $selectedDate,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .labelsHidden()

            HStack {
                Button("Cancel") {
                    isDatePickerPresented = false
                }
                Spacer()
                Button("Insert Date") {
                    insertSelectedDate()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .frame(width: 270)
    }

    private var comments: [JiraComment] {
        jiraService.comments(for: issue)
    }

    private func postComment() {
        let text = commentText
        let commentMentions = mentions
        let commentDates = dates
        isPosting = true
        feedback = nil
        Task {
            defer { isPosting = false }
            do {
                try await jiraService.addComment(
                    text,
                    to: issue,
                    mentions: commentMentions,
                    dates: commentDates
                )
                commentText = ""
                mentions = []
                dates = []
                mentionQuery = nil
                feedback = CommentFeedback(message: "Posted", isError: false)
            } catch {
                feedback = CommentFeedback(message: error.localizedDescription, isError: true)
            }
        }
    }

    private func handleComposerTextChange(_ text: String) {
        if text.hasSuffix("/date") {
            commentText.removeLast("/date".count)
            mentionQuery = nil
            mentionSuggestions = []
            selectedDate = Date()
            isDatePickerPresented = true
            return
        }
        mentionQuery = activeMentionQuery(in: text)
    }

    private func activeMentionQuery(in text: String) -> String? {
        guard let atIndex = text.lastIndex(of: "@") else { return nil }
        if atIndex > text.startIndex {
            let previousIndex = text.index(before: atIndex)
            guard text[previousIndex].isWhitespace || text[previousIndex].isPunctuation else { return nil }
        }
        let queryStart = text.index(after: atIndex)
        let query = text[queryStart...]
        guard !query.contains(where: { $0.isWhitespace || $0 == "@" }) else { return nil }
        return String(query)
    }

    private func insertMentionCommand() {
        if !commentText.isEmpty, commentText.last?.isWhitespace != true {
            commentText.append(" ")
        }
        commentText.append("@")
        mentionQuery = ""
    }

    private func selectMention(_ user: JiraUser) {
        guard let atIndex = commentText.lastIndex(of: "@") else { return }
        commentText.replaceSubrange(atIndex..<commentText.endIndex, with: "@\(user.displayName) ")
        if !mentions.contains(where: { $0.accountId == user.accountId }) {
            mentions.append(user)
        }
        mentionQuery = nil
        mentionSuggestions = []
    }

    private func insertSelectedDate() {
        let token = JiraCommentDateToken(date: selectedDate)
        if !commentText.isEmpty, commentText.last?.isWhitespace != true {
            commentText.append(" ")
        }
        commentText.append("\(token.marker) ")
        dates.append(token)
        isDatePickerPresented = false
    }

    private func initials(for name: String) -> String {
        String(
            name.split(separator: " ")
                .prefix(2)
                .compactMap(\.first)
        )
        .uppercased()
    }

    private var availableTransitions: [JiraTransition] {
        jiraService.transitions(for: issue)
    }

    private var isTransitioning: Bool {
        jiraService.transitioningIssueIDs.contains(issue.id)
    }

    private func transition(to status: JiraWorkflowStatus) -> JiraTransition? {
        availableTransitions.first {
            status.matches($0.to.name) || status.matches($0.name)
        }
    }

    private func move(using transition: JiraTransition) {
        transitionFeedback = nil
        Task {
            do {
                try await jiraService.transition(issue, using: transition)
                transitionFeedback = CommentFeedback(message: "Moved to \(transition.to.name)", isError: false)
            } catch {
                transitionFeedback = CommentFeedback(message: error.localizedDescription, isError: true)
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

// MARK: - Project pulse

private struct JiraProjectPulseView: View {
    let issues: [JiraIssue]
    let notifications: [JiraNotification]
    let projectKey: String
    let isFilteredToAssignee: Bool
    let onOpenIssue: (JiraIssue) -> Void
    @State private var exportFeedback: JiraPulseExportFeedback?

    private var analytics: JiraSprintAnalytics {
        JiraSprintAnalytics(issues: issues, notifications: notifications)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                pulseHeader
                metricGrid

                if isFilteredToAssignee {
                    Label(
                        "Project Pulse reflects your current assignee scope. Choose Everyone to review the full team.",
                        systemImage: "line.3.horizontal.decrease.circle"
                    )
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.orange)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }

                HStack(alignment: .top, spacing: 14) {
                    workflowDistribution
                    attentionSummary
                }

                teamFlow
                attentionTickets
            }
            .padding(28)
            .frame(maxWidth: 1080)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var pulseHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Project Pulse")
                    .font(.system(size: 22, weight: .bold))
                Text("A current-sprint view of flow, workload, and work that needs attention.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
            }
            Spacer()
            Menu {
                Button {
                    export(.pdf)
                } label: {
                    Label("PDF Report", systemImage: "doc.richtext")
                }
                Button {
                    export(.csv)
                } label: {
                    Label("CSV Data", systemImage: "tablecells")
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Export the current sprint report")

            if let exportFeedback {
                Label(exportFeedback.message, systemImage: exportFeedback.systemImage)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(exportFeedback.isError ? Color.red : Color.green)
                    .lineLimit(1)
            }

            Text("\(analytics.total) sprint tickets")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color(NSColor.secondaryLabelColor))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color(NSColor.controlBackgroundColor), in: Capsule())
        }
    }

    private var metricGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
            spacing: 10
        ) {
            JiraPulseMetricCard(
                title: "Sprint completion",
                value: "\(Int((analytics.completionRate * 100).rounded()))%",
                detail: "\(analytics.completed) of \(analytics.total) complete",
                icon: "checkmark.circle.fill",
                tint: .green
            )
            JiraPulseMetricCard(
                title: "Active WIP",
                value: "\(analytics.active)",
                detail: "\(analytics.inReview) in code review",
                icon: "bolt.fill",
                tint: .blue
            )
            JiraPulseMetricCard(
                title: "Release queue",
                value: "\(analytics.readyForRelease)",
                detail: "Counted complete · \(analytics.inQA) in QA",
                icon: "shippingbox.fill",
                tint: .teal
            )
            JiraPulseMetricCard(
                title: "Needs attention",
                value: "\(analytics.attentionIssues.count)",
                detail: "\(analytics.aging) aging · \(analytics.highPriority) high",
                icon: "exclamationmark.triangle.fill",
                tint: analytics.attentionIssues.isEmpty ? .green : .orange
            )
        }
    }

    private var workflowDistribution: some View {
        JiraPulsePanel(title: "Workflow distribution", subtitle: "Where active-sprint work sits right now") {
            VStack(spacing: 10) {
                ForEach(analytics.statusCounts) { item in
                    HStack(spacing: 9) {
                        Circle()
                            .fill(jiraWorkflowStatusColor(item.status))
                            .frame(width: 7, height: 7)
                        Text(item.status.rawValue)
                            .font(.system(size: 10, weight: .medium))
                            .frame(width: 112, alignment: .leading)
                        GeometryReader { proxy in
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Color(NSColor.controlBackgroundColor))
                                .overlay(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                                        .fill(jiraWorkflowStatusColor(item.status).opacity(0.72))
                                        .frame(
                                            width: analytics.total == 0
                                                ? 0
                                                : proxy.size.width * CGFloat(item.count) / CGFloat(analytics.total)
                                        )
                                }
                        }
                        .frame(height: 7)
                        Text("\(item.count)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .frame(width: 22, alignment: .trailing)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var attentionSummary: some View {
        JiraPulsePanel(title: "Flow signals", subtitle: "Prompts for the next team conversation") {
            VStack(spacing: 0) {
                pulseSignal("Aging over 3 days", value: analytics.aging, icon: "clock.badge.exclamationmark", tint: .orange)
                Divider().opacity(0.45)
                pulseSignal("High priority", value: analytics.highPriority, icon: "flag.fill", tint: .red)
                Divider().opacity(0.45)
                pulseSignal("Unassigned", value: analytics.unassigned, icon: "person.crop.circle.badge.questionmark", tint: .purple)
                Divider().opacity(0.45)
                pulseSignal("Completed in 7 days", value: analytics.completedRecently, icon: "calendar.badge.checkmark", tint: .green)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func pulseSignal(_ title: String, value: Int, icon: String, tint: Color) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22)
            Text(title)
                .font(.system(size: 10, weight: .medium))
            Spacer()
            Text("\(value)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
        }
        .padding(.vertical, 9)
    }

    private var teamFlow: some View {
        JiraPulsePanel(
            title: "Team flow",
            subtitle: "Work distribution by assignee—not an employee score"
        ) {
            VStack(spacing: 0) {
                JiraTeamFlowHeader()
                Divider().opacity(0.55)
                ForEach(analytics.team) { member in
                    JiraTeamFlowRow(member: member)
                    if member.id != analytics.team.last?.id {
                        Divider().opacity(0.32)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var attentionTickets: some View {
        if !analytics.attentionIssues.isEmpty {
            JiraPulsePanel(
                title: "Tickets needing attention",
                subtitle: "High-priority, unassigned, or unchanged for more than three days"
            ) {
                LazyVStack(spacing: 6) {
                    ForEach(analytics.attentionIssues.prefix(8)) { issue in
                        Button {
                            onOpenIssue(issue)
                        } label: {
                            HStack(spacing: 10) {
                                RoundedRectangle(cornerRadius: 2, style: .continuous)
                                    .fill(jiraPriorityColor(issue.fields.priority?.name))
                                    .frame(width: 3, height: 28)
                                Text(issue.key)
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 72, alignment: .leading)
                                Text(issue.fields.summary)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Color(NSColor.labelColor))
                                    .lineLimit(1)
                                Spacer()
                                JiraStatusBadge(issue: issue)
                                if issue.fields.assignee == nil {
                                    Text("Unassigned")
                                        .font(.system(size: 9, weight: .semibold))
                                        .foregroundStyle(Color.purple)
                                }
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(Color(NSColor.tertiaryLabelColor))
                            }
                            .padding(.horizontal, 9)
                            .frame(height: 38)
                            .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func export(_ format: JiraPulseExportFormat) {
        exportFeedback = nil
        let panel = NSSavePanel()
        panel.title = "Export Project Pulse"
        panel.prompt = "Export"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowsOtherFileTypes = false
        panel.allowedContentTypes = [
            format == .pdf ? .pdf : .commaSeparatedText
        ]
        panel.nameFieldStringValue = JiraPulseExporter.suggestedFilename(
            projectKey: projectKey,
            format: format
        )

        guard panel.runModal() == .OK, let destination = panel.url else {
            return
        }

        do {
            let data = try JiraPulseExporter.data(
                for: format,
                issues: issues,
                notifications: notifications,
                projectKey: projectKey,
                isFilteredToAssignee: isFilteredToAssignee
            )
            try data.write(to: destination, options: .atomic)
            exportFeedback = JiraPulseExportFeedback(
                message: "\(format.displayName) exported",
                isError: false
            )
        } catch {
            exportFeedback = JiraPulseExportFeedback(
                message: error.localizedDescription,
                isError: true
            )
        }
    }
}

private struct JiraPulseExportFeedback {
    let message: String
    let isError: Bool

    var systemImage: String {
        isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
    }
}

private struct JiraPulseMetricCard: View {
    let title: String
    let value: String
    let detail: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
                Spacer()
                Image(systemName: icon)
                    .foregroundStyle(tint)
            }
            Text(value)
                .font(.system(size: 25, weight: .bold, design: .rounded))
            Text(detail)
                .font(.system(size: 9))
                .foregroundStyle(Color(NSColor.tertiaryLabelColor))
                .lineLimit(1)
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color(NSColor.separatorColor).opacity(0.45), lineWidth: 0.5)
        )
    }
}

private struct JiraPulsePanel<Content: View>: View {
    let title: String
    let subtitle: String
    let content: Content

    init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                Text(subtitle)
                    .font(.system(size: 9))
                    .foregroundStyle(Color(NSColor.tertiaryLabelColor))
            }
            content
        }
        .padding(15)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color(NSColor.separatorColor).opacity(0.45), lineWidth: 0.5)
        )
    }
}

private struct JiraTeamFlowHeader: View {
    var body: some View {
        HStack {
            Text("ASSIGNEE").frame(maxWidth: .infinity, alignment: .leading)
            Text("TOTAL").frame(width: 50)
            Text("ACTIVE").frame(width: 50)
            Text("REVIEW").frame(width: 50)
            Text("QA").frame(width: 42)
            Text("DONE").frame(width: 50)
            Text("AT RISK").frame(width: 58)
        }
        .font(.system(size: 8, weight: .bold))
        .foregroundStyle(Color(NSColor.tertiaryLabelColor))
        .padding(.vertical, 6)
    }
}

private struct JiraTeamFlowRow: View {
    let member: JiraTeamFlowMember

    var body: some View {
        HStack {
            HStack(spacing: 8) {
                Text(initials)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Color.accentColor.gradient, in: Circle())
                Text(member.name)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            value(member.assigned, width: 50)
            value(member.active, width: 50)
            value(member.inReview, width: 50)
            value(member.inQA, width: 42)
            value(member.completed, width: 50)
            value(member.atRisk, width: 58, tint: member.atRisk > 0 ? .orange : .secondary)
        }
        .padding(.vertical, 7)
    }

    private var initials: String {
        member.name.split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()
    }

    private func value(_ value: Int, width: CGFloat, tint: Color = .secondary) -> some View {
        Text("\(value)")
            .font(.system(size: 10, weight: value > 0 ? .bold : .regular, design: .monospaced))
            .foregroundStyle(value > 0 ? tint : Color(NSColor.tertiaryLabelColor))
            .frame(width: width)
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
