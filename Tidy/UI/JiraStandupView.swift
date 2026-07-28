import AppKit
import SwiftUI

struct JiraStandupView: View {
    @EnvironmentObject private var jiraService: JiraService

    let issues: [JiraIssue]
    let onOpenIssue: (JiraIssue) -> Void

    @State private var mode = JiraStandupMode.myUpdate
    @State private var drafts: [String: JiraStandupDraft] = [:]
    @State private var loadedDraftAccountID: String?
    @State private var isPosting = false
    @State private var feedback: StandupFeedback?
    @State private var inspectedIssue: JiraIssue?
    @State private var mentionsByIssueID: [String: [JiraUser]] = [:]
    @State private var datesByIssueID: [String: [JiraCommentDateToken]] = [:]

    var body: some View {
        VStack(spacing: 0) {
            standupHeader
            Divider().opacity(0.55)

            if mode == .myUpdate {
                myUpdateView
            } else {
                teamBoardView
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .task(id: jiraService.currentUser?.accountId) {
            loadDraftsIfNeeded()
            if jiraService.standupUpdates.isEmpty {
                await jiraService.loadStandupUpdates(for: issues)
            }
        }
        .onChange(of: drafts) { _, _ in saveDrafts() }
        .inspector(
            isPresented: Binding(
                get: { inspectedIssue != nil },
                set: { if !$0 { inspectedIssue = nil } }
            )
        ) {
            if let inspectedIssue {
                JiraStandupIssueInspector(
                    issue: inspectedIssue,
                    updates: jiraService.standupUpdates.filter { $0.issueID == inspectedIssue.id },
                    onOpenInWorkbench: { onOpenIssue(inspectedIssue) },
                    onDismiss: { self.inspectedIssue = nil }
                )
                .environmentObject(jiraService)
                .inspectorColumnWidth(min: 340, ideal: 390, max: 460)
            }
        }
    }

    private var standupHeader: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Daily Standup")
                    .font(.system(size: 19, weight: .bold))
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
            }

            HStack(spacing: 2) {
                standupTab(.myUpdate)
                standupTab(.teamBoard)
            }
            .padding(3)
            .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Spacer()

            if mode == .teamBoard {
                Button {
                    Task { await jiraService.loadStandupUpdates(for: issues) }
                } label: {
                    if jiraService.isLoadingStandup {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Refresh Updates", systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(jiraService.isLoadingStandup)
            }
        }
        .padding(.horizontal, 24)
        .frame(height: 66)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func standupTab(_ tab: JiraStandupMode) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.14)) { mode = tab }
        } label: {
            Label(tab.title, systemImage: tab.systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(mode == tab ? Color(NSColor.labelColor) : Color(NSColor.secondaryLabelColor))
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(
                    mode == tab ? Color(NSColor.windowBackgroundColor) : .clear,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - My update

    private var myUpdateView: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    myUpdateIntroduction

                    if myIssues.isEmpty {
                        ContentUnavailableView(
                            "No assigned sprint tickets",
                            systemImage: "person.crop.circle.badge.questionmark",
                            description: Text("Refresh Jira or choose Everyone so Tidy can find tickets assigned to you.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 320)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Ticket updates")
                                    .font(.system(size: 14, weight: .bold))
                                Text("\(includedDrafts.count) selected")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Color.accentColor)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.1), in: Capsule())
                                Spacer()
                                Button("Select Active") { selectActiveTickets() }
                                    .buttonStyle(.borderless)
                                    .controlSize(.small)
                            }

                            ForEach(myIssues) { issue in
                                JiraStandupDraftRow(
                                    issue: issue,
                                    draft: draftBinding(for: issue),
                                    mentions: mentionBinding(for: issue),
                                    dates: dateBinding(for: issue),
                                    onInspect: { inspectedIssue = issue }
                                )
                            }
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity, alignment: .top)
            }

            Divider().opacity(0.55)

            standupPreview
                .frame(width: 320)
        }
    }

    private var myUpdateIntroduction: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text("What changed, what’s next, and what’s blocked?")
                    .font(.system(size: 14, weight: .bold))
                Text("Select the tickets you’ll mention. Each update is posted as a Jira comment, so context stays with the work.")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(15)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(Color(NSColor.separatorColor).opacity(0.45), lineWidth: 0.5)
        )
    }

    private var standupPreview: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Today’s update")
                    .font(.system(size: 15, weight: .bold))
                Text("Preview what your team will see in Jira.")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
            }

            HStack(spacing: 8) {
                previewMetric(
                    value: includedDrafts.filter { $0.state == .ongoing }.count,
                    label: "Ongoing",
                    tint: .blue
                )
                previewMetric(
                    value: includedDrafts.filter { $0.state == .blocked }.count,
                    label: "Blocked",
                    tint: .red
                )
                previewMetric(
                    value: includedDrafts.filter { $0.state == .done }.count,
                    label: "Done",
                    tint: .green
                )
            }

            Divider().opacity(0.5)

            if includedDrafts.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "checklist")
                        .font(.system(size: 22))
                        .foregroundStyle(Color(NSColor.tertiaryLabelColor))
                    Text("Select tickets to build your update.")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(NSColor.secondaryLabelColor))
                }
                .frame(maxWidth: .infinity, minHeight: 130)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(includedDrafts) { draft in
                            if let issue = issueByID[draft.issueID] {
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text(issue.key)
                                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                                            .foregroundStyle(Color.accentColor)
                                        Spacer()
                                        Label(draft.state.rawValue, systemImage: draft.state.systemImage)
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundStyle(standupStateColor(draft.state))
                                    }
                                    Text(draft.note.isEmpty ? "Add an update before posting" : draft.note)
                                        .font(.system(size: 10))
                                        .foregroundStyle(
                                            draft.note.isEmpty
                                                ? Color(NSColor.placeholderTextColor)
                                                : Color(NSColor.labelColor)
                                        )
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(10)
                                .background(Color(NSColor.windowBackgroundColor), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                    }
                }
            }

            Spacer()

            if let feedback {
                Label(feedback.message, systemImage: feedback.isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(feedback.isError ? Color.red : Color.green)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: postStandup) {
                if isPosting {
                    HStack(spacing: 7) {
                        ProgressView().controlSize(.small)
                        Text("Sharing update…")
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    Label(
                        "Post \(validDrafts.count) Jira Update\(validDrafts.count == 1 ? "" : "s")",
                        systemImage: "paperplane.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(validDrafts.isEmpty || isPosting)

            Text("Only selected tickets with a written update will be posted.")
                .font(.system(size: 8))
                .foregroundStyle(Color(NSColor.tertiaryLabelColor))
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(20)
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func previewMetric(value: Int, label: String, tint: Color) -> some View {
        VStack(spacing: 3) {
            Text("\(value)")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
            Text(label)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Color(NSColor.secondaryLabelColor))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Team board

    private var teamBoardView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                teamMetrics

                if let error = jiraService.standupErrorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.red)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Team check-in")
                            .font(.system(size: 15, weight: .bold))
                        Text("Blockers appear first, followed by members still waiting to check in.")
                            .font(.system(size: 10))
                            .foregroundStyle(Color(NSColor.secondaryLabelColor))
                    }
                    Spacer()
                    Text("Updates are read from today’s Jira comments")
                        .font(.system(size: 9))
                        .foregroundStyle(Color(NSColor.tertiaryLabelColor))
                }

                if jiraService.isLoadingStandup && jiraService.standupUpdates.isEmpty {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Reading today’s ticket updates…")
                            .font(.system(size: 10))
                            .foregroundStyle(Color(NSColor.secondaryLabelColor))
                    }
                    .frame(maxWidth: .infinity, minHeight: 260)
                } else {
                    LazyVStack(spacing: 9) {
                        ForEach(teamMembers) { member in
                            JiraStandupMemberCard(
                                member: member,
                                onInspectIssue: { inspectedIssue = $0 }
                            )
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 1050)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    private var teamMetrics: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
            spacing: 10
        ) {
            JiraStandupMetricCard(
                title: "Checked in",
                value: "\(checkedInCount)/\(teamMembers.count)",
                detail: "Team members today",
                icon: "person.2.fill",
                tint: .blue
            )
            JiraStandupMetricCard(
                title: "Blockers",
                value: "\(blockerCount)",
                detail: blockerCount == 0 ? "No explicit blockers" : "Needs team attention",
                icon: "exclamationmark.octagon.fill",
                tint: blockerCount == 0 ? .green : .red
            )
            JiraStandupMetricCard(
                title: "Ongoing",
                value: "\(ongoingCount)",
                detail: "Updates shared today",
                icon: "arrow.triangle.2.circlepath",
                tint: .indigo
            )
            JiraStandupMetricCard(
                title: "Awaiting update",
                value: "\(max(teamMembers.count - checkedInCount, 0))",
                detail: "Follow up in standup",
                icon: "clock.fill",
                tint: .orange
            )
        }
    }

    // MARK: - Data

    private var myIssues: [JiraIssue] {
        guard let accountID = jiraService.currentUser?.accountId else { return [] }
        return issues
            .filter {
                $0.fields.assignee?.accountId == accountID
                    && (!$0.isCompleted || wasUpdatedToday($0))
            }
            .sorted {
                if $0.statusGroup != $1.statusGroup {
                    return $0.statusGroup == .inProgress
                }
                return ($0.updatedDate ?? .distantPast) > ($1.updatedDate ?? .distantPast)
            }
    }

    private var issueByID: [String: JiraIssue] {
        Dictionary(uniqueKeysWithValues: issues.map { ($0.id, $0) })
    }

    private var includedDrafts: [JiraStandupDraft] {
        drafts.values
            .filter(\.isIncluded)
            .sorted {
                guard let left = issueByID[$0.issueID], let right = issueByID[$1.issueID] else {
                    return $0.issueID < $1.issueID
                }
                return left.key.localizedStandardCompare(right.key) == .orderedAscending
            }
    }

    private var validDrafts: [JiraStandupDraft] {
        includedDrafts.filter {
            !$0.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var teamMembers: [JiraStandupMemberSnapshot] {
        let checkedInAccountIDs = Set(jiraService.standupUpdates.compactMap(\.authorAccountID))
        let assignedIssues = issues.filter {
            guard let assignee = $0.fields.assignee else { return false }
            return !$0.isCompleted
                || wasUpdatedToday($0)
                || (assignee.accountId.map { checkedInAccountIDs.contains($0) } ?? false)
        }
        let grouped = Dictionary(grouping: assignedIssues) {
            $0.fields.assignee?.accountId ?? $0.fields.assignee?.displayName ?? "unknown"
        }

        return grouped.compactMap { accountID, memberIssues in
            guard let assignee = memberIssues.first?.fields.assignee else { return nil }
            let updates = jiraService.standupUpdates.filter {
                if let authorID = $0.authorAccountID {
                    return authorID == accountID
                }
                return $0.authorName == assignee.displayName
            }
            return JiraStandupMemberSnapshot(
                id: accountID,
                name: assignee.displayName,
                updates: updates,
                issues: memberIssues
            )
        }
        .sorted {
            if $0.blockerCount != $1.blockerCount { return $0.blockerCount > $1.blockerCount }
            if $0.hasCheckedIn != $1.hasCheckedIn { return !$0.hasCheckedIn }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private var checkedInCount: Int {
        teamMembers.filter(\.hasCheckedIn).count
    }

    private var blockerCount: Int {
        jiraService.standupUpdates.filter { $0.state == .blocked }.count
    }

    private var ongoingCount: Int {
        jiraService.standupUpdates.filter { $0.state == .ongoing }.count
    }

    private func draftBinding(for issue: JiraIssue) -> Binding<JiraStandupDraft> {
        Binding(
            get: {
                drafts[issue.id] ?? defaultDraft(for: issue)
            },
            set: {
                drafts[issue.id] = $0
            }
        )
    }

    private func defaultDraft(for issue: JiraIssue) -> JiraStandupDraft {
        JiraStandupDraft(
            issueID: issue.id,
            state: issue.statusGroup == .done ? .done : .ongoing,
            note: suggestedNote(for: issue),
            isIncluded: issue.statusGroup == .inProgress
                || JiraWorkflowStatus.readyForRelease.matches(issue.fields.status.name)
        )
    }

    private func mentionBinding(for issue: JiraIssue) -> Binding<[JiraUser]> {
        Binding(
            get: { mentionsByIssueID[issue.id] ?? [] },
            set: { mentionsByIssueID[issue.id] = $0 }
        )
    }

    private func dateBinding(for issue: JiraIssue) -> Binding<[JiraCommentDateToken]> {
        Binding(
            get: { datesByIssueID[issue.id] ?? [] },
            set: { datesByIssueID[issue.id] = $0 }
        )
    }

    private func suggestedNote(for issue: JiraIssue) -> String {
        if issue.isCompleted {
            return "Completed and ready for the next handoff."
        }
        if JiraWorkflowStatus.codeReview.matches(issue.fields.status.name) {
            return "In code review; addressing feedback."
        }
        if JiraWorkflowStatus.inQA.matches(issue.fields.status.name) {
            return "In QA; following validation and fixes."
        }
        if JiraWorkflowStatus.readyForRelease.matches(issue.fields.status.name) {
            return "Ready for release."
        }
        if JiraWorkflowStatus.inProgress.matches(issue.fields.status.name) {
            return "Continuing implementation."
        }
        return ""
    }

    private func wasUpdatedToday(_ issue: JiraIssue) -> Bool {
        guard let updatedDate = issue.updatedDate else { return false }
        return Calendar.current.isDateInToday(updatedDate)
    }

    private func loadDraftsIfNeeded() {
        guard let accountID = jiraService.currentUser?.accountId,
              loadedDraftAccountID != accountID else {
            return
        }
        loadedDraftAccountID = accountID

        if let data = UserDefaults.standard.data(forKey: draftStorageKey),
           let stored = try? JSONDecoder().decode([JiraStandupDraft].self, from: data) {
            drafts = Dictionary(uniqueKeysWithValues: stored.map { ($0.issueID, $0) })
        }

        for issue in myIssues where drafts[issue.id] == nil {
            drafts[issue.id] = defaultDraft(for: issue)
        }
    }

    private func saveDrafts() {
        guard loadedDraftAccountID == jiraService.currentUser?.accountId,
              let data = try? JSONEncoder().encode(Array(drafts.values)) else {
            return
        }
        UserDefaults.standard.set(data, forKey: draftStorageKey)
    }

    private var draftStorageKey: String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        let day = String(
            format: "%04d%02d%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
        return "jira-standup-draft-\(jiraService.currentUser?.accountId ?? "unknown")-\(day)"
    }

    private func selectActiveTickets() {
        for issue in myIssues {
            var draft = drafts[issue.id] ?? defaultDraft(for: issue)
            draft.isIncluded = issue.statusGroup == .inProgress
                || JiraWorkflowStatus.readyForRelease.matches(issue.fields.status.name)
            drafts[issue.id] = draft
        }
    }

    private func postStandup() {
        let updates = validDrafts
        guard !updates.isEmpty else { return }
        feedback = nil
        isPosting = true

        Task {
            defer { isPosting = false }
            do {
                let result = try await jiraService.postStandup(
                    drafts: updates,
                    for: issues,
                    mentionsByIssueID: mentionsByIssueID,
                    datesByIssueID: datesByIssueID
                )
                for issueID in result.postedIssueIDs {
                    drafts[issueID]?.isIncluded = false
                    mentionsByIssueID[issueID] = []
                    datesByIssueID[issueID] = []
                }
                if result.errorsByIssueKey.isEmpty {
                    feedback = StandupFeedback(
                        message: "Shared \(result.postedIssueIDs.count) update\(result.postedIssueIDs.count == 1 ? "" : "s") with Jira.",
                        isError: false
                    )
                } else {
                    let failedKeys = result.errorsByIssueKey.keys.sorted().joined(separator: ", ")
                    feedback = StandupFeedback(
                        message: "Posted \(result.postedIssueIDs.count). Couldn’t post: \(failedKeys).",
                        isError: true
                    )
                }
            } catch {
                feedback = StandupFeedback(message: error.localizedDescription, isError: true)
            }
        }
    }
}

private enum JiraStandupMode: String, CaseIterable {
    case myUpdate
    case teamBoard

    var title: String {
        switch self {
        case .myUpdate: "My Update"
        case .teamBoard: "Team Board"
        }
    }

    var systemImage: String {
        switch self {
        case .myUpdate: "square.and.pencil"
        case .teamBoard: "person.3.fill"
        }
    }
}

private struct StandupFeedback {
    let message: String
    let isError: Bool
}

private struct JiraStandupDraftRow: View {
    let issue: JiraIssue
    @Binding var draft: JiraStandupDraft
    @Binding var mentions: [JiraUser]
    @Binding var dates: [JiraCommentDateToken]
    let onInspect: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Toggle("", isOn: $draft.isIncluded)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Text(issue.key)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.accentColor)
                    JiraStandupStatusPill(status: issue.fields.status.name, group: issue.statusGroup)
                    Spacer()
                    Button(action: onInspect) {
                        Label("Details", systemImage: "sidebar.right")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("View ticket details without leaving Standup")
                    Picker("Standup status", selection: $draft.state) {
                        ForEach(JiraStandupState.allCases) { state in
                            Label(state.rawValue, systemImage: state.systemImage)
                                .tag(state)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .frame(width: 118)
                }

                Button(action: onInspect) {
                    HStack(spacing: 6) {
                        Text(issue.fields.summary)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(NSColor.labelColor))
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                        Spacer()
                        Image(systemName: "info.circle")
                            .foregroundStyle(Color(NSColor.tertiaryLabelColor))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                JiraStandupRichComposer(
                    issue: issue,
                    text: $draft.note,
                    mentions: $mentions,
                    dates: $dates,
                    placeholder: placeholder,
                    leadingIcon: draft.state.systemImage,
                    leadingTint: standupStateColor(draft.state),
                    compact: true
                )
            }
        }
        .padding(13)
        .background(
            draft.isIncluded
                ? Color.accentColor.opacity(0.06)
                : Color(NSColor.controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    draft.isIncluded
                        ? Color.accentColor.opacity(0.28)
                        : Color(NSColor.separatorColor).opacity(0.4),
                    lineWidth: 0.6
                )
        )
        .opacity(draft.isIncluded ? 1 : 0.72)
    }

    private var placeholder: String {
        switch draft.state {
        case .ongoing: "What changed and what will you do next?"
        case .blocked: "What is blocked, why, and who can help?"
        case .done: "What was completed or handed off?"
        }
    }
}

private struct JiraStandupMemberSnapshot: Identifiable {
    let id: String
    let name: String
    let updates: [JiraStandupUpdate]
    let issues: [JiraIssue]

    var hasCheckedIn: Bool { !updates.isEmpty }
    var blockerCount: Int { updates.filter { $0.state == .blocked }.count }
    var lastUpdate: Date? { updates.map(\.createdAt).max() }
    var activeIssues: [JiraIssue] { issues.filter { !$0.isCompleted } }
}

private struct JiraStandupMemberCard: View {
    let member: JiraStandupMemberSnapshot
    let onInspectIssue: (JiraIssue) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text(initials)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(avatarColor.gradient, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(member.name)
                        .font(.system(size: 12, weight: .bold))
                    if let lastUpdate = member.lastUpdate {
                        Text("Checked in \(lastUpdate, style: .relative)")
                            .font(.system(size: 9))
                            .foregroundStyle(Color(NSColor.secondaryLabelColor))
                    } else {
                        Text("Waiting for today’s update")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.orange)
                    }
                }

                Spacer()

                if member.blockerCount > 0 {
                    Label("\(member.blockerCount) blocker\(member.blockerCount == 1 ? "" : "s")", systemImage: "exclamationmark.octagon.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.09), in: Capsule())
                } else if member.hasCheckedIn {
                    Label("Checked in", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.green)
                }
            }

            if member.updates.isEmpty {
                VStack(spacing: 5) {
                    ForEach(member.activeIssues.prefix(3)) { issue in
                        Button {
                            onInspectIssue(issue)
                        } label: {
                            HStack(spacing: 8) {
                                Text(issue.key)
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Color.accentColor)
                                Text(issue.fields.summary)
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color(NSColor.labelColor))
                                    .lineLimit(1)
                                Spacer()
                                JiraStandupStatusPill(status: issue.fields.status.name, group: issue.statusGroup)
                            }
                            .padding(.horizontal, 9)
                            .frame(height: 31)
                            .background(Color(NSColor.windowBackgroundColor), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                VStack(spacing: 6) {
                    ForEach(member.updates) { update in
                        Button {
                            if let issue = member.issues.first(where: { $0.id == update.issueID }) {
                                onInspectIssue(issue)
                            }
                        } label: {
                            HStack(alignment: .top, spacing: 9) {
                                Image(systemName: update.state.systemImage)
                                    .foregroundStyle(standupStateColor(update.state))
                                    .frame(width: 17)
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(update.issueKey)
                                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                                            .foregroundStyle(Color.accentColor)
                                        Text(update.state.rawValue)
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundStyle(standupStateColor(update.state))
                                    }
                                    Text(update.note)
                                        .font(.system(size: 10))
                                        .foregroundStyle(Color(NSColor.labelColor))
                                        .multilineTextAlignment(.leading)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(Color(NSColor.tertiaryLabelColor))
                            }
                            .padding(9)
                            .background(Color(NSColor.windowBackgroundColor), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(
                    member.blockerCount > 0
                        ? Color.red.opacity(0.3)
                        : Color(NSColor.separatorColor).opacity(0.45),
                    lineWidth: 0.6
                )
        )
    }

    private var initials: String {
        member.name.split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()
    }

    private var avatarColor: Color {
        let palette: [Color] = [.blue, .purple, .teal, .indigo, .orange]
        return palette[abs(member.name.hashValue) % palette.count]
    }
}

private struct JiraStandupRichComposer: View {
    @EnvironmentObject private var jiraService: JiraService

    let issue: JiraIssue
    @Binding var text: String
    @Binding var mentions: [JiraUser]
    @Binding var dates: [JiraCommentDateToken]
    let placeholder: String
    let leadingIcon: String
    let leadingTint: Color
    let compact: Bool

    @State private var mentionQuery: String?
    @State private var mentionSuggestions: [JiraUser] = []
    @State private var isSearchingMentions = false
    @State private var isDatePickerPresented = false
    @State private var selectedDate = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if mentionQuery != nil {
                mentionSuggestionsPanel
            }

            HStack(alignment: compact ? .center : .top, spacing: 8) {
                Image(systemName: leadingIcon)
                    .foregroundStyle(leadingTint)
                    .frame(width: 18)
                    .padding(.top, compact ? 0 : 7)

                if compact {
                    TextField(placeholder, text: $text)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                } else {
                    ZStack(alignment: .topLeading) {
                        if text.isEmpty {
                            Text(placeholder)
                                .font(.system(size: 10))
                                .foregroundStyle(Color(NSColor.placeholderTextColor))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 7)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $text)
                            .font(.system(size: 11))
                            .scrollContentBackground(.hidden)
                            .padding(0)
                            .frame(minHeight: 62, maxHeight: 86)
                    }
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, compact ? 7 : 5)
            .background(
                Color(NSColor.textBackgroundColor),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color(NSColor.separatorColor).opacity(0.55), lineWidth: 0.6)
            )
            .onChange(of: text) { _, newValue in
                handleTextChange(newValue)
            }

            HStack(spacing: 10) {
                Button(action: insertMentionCommand) {
                    Label("Mention", systemImage: "at")
                }
                .buttonStyle(.borderless)
                .help("Mention a Jira user")

                Button {
                    selectedDate = Date()
                    isDatePickerPresented = true
                } label: {
                    Label("Date", systemImage: "calendar")
                }
                .buttonStyle(.borderless)
                .help("Insert a Jira date")
                .popover(isPresented: $isDatePickerPresented, arrowEdge: .bottom) {
                    datePickerPopover
                }

                Spacer()
                Text("@ or @ name · /date")
                    .font(.system(size: 8))
                    .foregroundStyle(Color(NSColor.tertiaryLabelColor))
            }
            .font(.system(size: 9, weight: .medium))
            .controlSize(.mini)
        }
        .task(id: mentionQuery) {
            guard let mentionQuery else {
                mentionSuggestions = []
                isSearchingMentions = false
                return
            }

            isSearchingMentions = true
            do {
                try await Task.sleep(for: .milliseconds(180))
                let users = try await jiraService.searchMentionUsers(
                    matching: mentionQuery,
                    for: issue
                )
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

    private var mentionSuggestionsPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Mention someone", systemImage: "at")
                    .font(.system(size: 9, weight: .semibold))
                Spacer()
                if isSearchingMentions {
                    ProgressView().controlSize(.mini)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)

            if !isSearchingMentions && mentionSuggestions.isEmpty {
                Text("No assignable Jira users found")
                    .font(.system(size: 9))
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
                    .padding(.horizontal, 9)
                    .padding(.bottom, 7)
            } else {
                ForEach(mentionSuggestions.prefix(compact ? 4 : 6)) { user in
                    Button {
                        selectMention(user)
                    } label: {
                        HStack(spacing: 8) {
                            Text(initials(for: user.displayName))
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 21, height: 21)
                                .background(Color.accentColor.gradient, in: Circle())
                            Text(user.displayName)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color(NSColor.labelColor))
                            Spacer()
                            if let emailAddress = user.emailAddress, !emailAddress.isEmpty {
                                Text(emailAddress)
                                    .font(.system(size: 8))
                                    .foregroundStyle(Color(NSColor.tertiaryLabelColor))
                                    .lineLimit(1)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(
            Color(NSColor.controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color.accentColor.opacity(0.35), lineWidth: 0.7)
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

    private func handleTextChange(_ value: String) {
        if value.hasSuffix("/date") {
            text.removeLast("/date".count)
            mentionQuery = nil
            mentionSuggestions = []
            selectedDate = Date()
            isDatePickerPresented = true
            return
        }
        mentionQuery = activeMentionQuery(in: value)
    }

    private func activeMentionQuery(in value: String) -> String? {
        guard let atIndex = value.lastIndex(of: "@") else { return nil }
        if atIndex > value.startIndex {
            let previousIndex = value.index(before: atIndex)
            guard value[previousIndex].isWhitespace || value[previousIndex].isPunctuation else {
                return nil
            }
        }

        let queryStart = value.index(after: atIndex)
        let fragment = String(value[queryStart...])
        guard !fragment.contains("\n"), fragment.count <= 60 else { return nil }

        for user in mentions {
            guard fragment.hasPrefix(user.displayName) else { continue }
            let remainder = fragment.dropFirst(user.displayName.count)
            if remainder.isEmpty || remainder.first?.isWhitespace == true {
                return nil
            }
        }

        return fragment.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func insertMentionCommand() {
        if !text.isEmpty, text.last?.isWhitespace != true {
            text.append(" ")
        }
        text.append("@")
        mentionQuery = ""
    }

    private func selectMention(_ user: JiraUser) {
        guard let atIndex = text.lastIndex(of: "@") else { return }
        text.replaceSubrange(atIndex..<text.endIndex, with: "@\(user.displayName) ")
        if !mentions.contains(where: { $0.accountId == user.accountId }) {
            mentions.append(user)
        }
        mentionQuery = nil
        mentionSuggestions = []
    }

    private func insertSelectedDate() {
        let token = JiraCommentDateToken(date: selectedDate)
        if !text.isEmpty, text.last?.isWhitespace != true {
            text.append(" ")
        }
        text.append("\(token.marker) ")
        dates.append(token)
        isDatePickerPresented = false
    }

    private func initials(for name: String) -> String {
        String(name.split(separator: " ").prefix(2).compactMap(\.first)).uppercased()
    }
}

private struct JiraStandupIssueInspector: View {
    @EnvironmentObject private var jiraService: JiraService

    let issue: JiraIssue
    let updates: [JiraStandupUpdate]
    let onOpenInWorkbench: () -> Void
    let onDismiss: () -> Void
    @State private var commentText = ""
    @State private var commentMentions: [JiraUser] = []
    @State private var commentDates: [JiraCommentDateToken] = []
    @State private var isPostingComment = false
    @State private var commentFeedback: StandupFeedback?

    var body: some View {
        VStack(spacing: 0) {
            inspectorHeader
            Divider().opacity(0.55)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ticketSummary
                    descriptionSection
                    standupUpdateSection
                    recentConversationSection
                    commentSection
                }
                .padding(18)
            }

            Divider().opacity(0.55)
            inspectorActions
        }
        .background(Color(NSColor.windowBackgroundColor))
        .task(id: issue.id) {
            await jiraService.loadComments(for: issue)
        }
    }

    private var inspectorHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.13))
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text("Standup context")
                    .font(.system(size: 13, weight: .bold))
                Text("Review without leaving the team board")
                    .font(.system(size: 9))
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
            }
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 24, height: 24)
                    .background(Color(NSColor.controlBackgroundColor), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Close ticket details")
        }
        .padding(14)
        .background(.bar)
    }

    private var ticketSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Text(issue.key)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.accentColor)
                JiraStandupStatusPill(status: issue.fields.status.name, group: issue.statusGroup)
                Spacer()
                if let priority = issue.fields.priority?.name {
                    Label(priority, systemImage: "flag.fill")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Color(NSColor.secondaryLabelColor))
                }
            }

            Text(issue.fields.summary)
                .font(.system(size: 16, weight: .bold))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Label(issue.fields.assignee?.displayName ?? "Unassigned", systemImage: "person.fill")
                Label(
                    issue.updatedDate?.formatted(.relative(presentation: .named)) ?? "Unknown",
                    systemImage: "clock"
                )
            }
            .font(.system(size: 9))
            .foregroundStyle(Color(NSColor.secondaryLabelColor))
        }
    }

    private var descriptionSection: some View {
        inspectorSection(title: "Description", icon: "text.alignleft") {
            let description = issue.fields.description?.plainText
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            Text(description.isEmpty ? "No description provided." : description)
                .font(.system(size: 11))
                .foregroundStyle(
                    description.isEmpty
                        ? Color(NSColor.tertiaryLabelColor)
                        : Color(NSColor.labelColor)
                )
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var standupUpdateSection: some View {
        inspectorSection(title: "Today’s update", icon: "person.wave.2.fill") {
            if updates.isEmpty {
                Label("Waiting for this member’s update", systemImage: "clock")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.orange)
            } else {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(updates.sorted { $0.createdAt > $1.createdAt }) { update in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: update.state.systemImage)
                                .foregroundStyle(standupStateColor(update.state))
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(update.state.rawValue)
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(standupStateColor(update.state))
                                    Text("· \(update.authorName)")
                                        .font(.system(size: 9))
                                        .foregroundStyle(Color(NSColor.secondaryLabelColor))
                                }
                                Text(update.note)
                                    .font(.system(size: 11))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }

    private var recentConversationSection: some View {
        inspectorSection(title: "Recent conversation", icon: "bubble.left.and.bubble.right") {
            if jiraService.loadingCommentIssueIDs.contains(issue.id) && recentComments.isEmpty {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text("Loading comments…")
                }
                .font(.system(size: 10))
                .foregroundStyle(Color(NSColor.secondaryLabelColor))
            } else if recentComments.isEmpty {
                Text("No comments on this ticket.")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(NSColor.tertiaryLabelColor))
            } else {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(recentComments) { comment in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(comment.author.displayName)
                                    .font(.system(size: 9, weight: .bold))
                                Spacer()
                                if let createdDate = comment.createdDate {
                                    Text(createdDate, style: .relative)
                                        .font(.system(size: 8))
                                        .foregroundStyle(Color(NSColor.tertiaryLabelColor))
                                }
                            }
                            Text(comment.text)
                                .font(.system(size: 10))
                                .lineLimit(4)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(9)
                        .background(
                            Color(NSColor.controlBackgroundColor),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                    }
                }
            }
        }
    }

    private var commentSection: some View {
        inspectorSection(title: "Add comment", icon: "bubble.left") {
            VStack(alignment: .leading, spacing: 9) {
                JiraStandupRichComposer(
                    issue: issue,
                    text: $commentText,
                    mentions: $commentMentions,
                    dates: $commentDates,
                    placeholder: "Share context, a decision, or a follow-up…",
                    leadingIcon: "bubble.left",
                    leadingTint: .accentColor,
                    compact: false
                )

                HStack {
                    if let commentFeedback {
                        Label(
                            commentFeedback.message,
                            systemImage: commentFeedback.isError
                                ? "exclamationmark.circle.fill"
                                : "checkmark.circle.fill"
                        )
                        .font(.system(size: 9))
                        .foregroundStyle(commentFeedback.isError ? Color.red : Color.green)
                        .lineLimit(2)
                    }
                    Spacer()
                    Button(action: postComment) {
                        if isPostingComment {
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
                    .disabled(
                        commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || isPostingComment
                    )
                }
            }
        }
    }

    private var inspectorActions: some View {
        HStack {
            Button {
                if let url = jiraService.issueURL(for: issue) {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Label("Open in Jira", systemImage: "arrow.up.right.square")
            }
            .buttonStyle(.bordered)

            Spacer()

            Button(action: onOpenInWorkbench) {
                Label("Open Workbench", systemImage: "hammer")
            }
            .buttonStyle(.borderedProminent)
        }
        .controlSize(.small)
        .padding(12)
        .background(.bar)
    }

    private var recentComments: [JiraComment] {
        Array(jiraService.comments(for: issue).suffix(4).reversed())
    }

    private func postComment() {
        let text = commentText
        let mentions = commentMentions
        let dates = commentDates
        isPostingComment = true
        commentFeedback = nil

        Task {
            defer { isPostingComment = false }
            do {
                try await jiraService.addComment(
                    text,
                    to: issue,
                    mentions: mentions,
                    dates: dates
                )
                commentText = ""
                commentMentions = []
                commentDates = []
                commentFeedback = StandupFeedback(message: "Comment posted", isError: false)
            } catch {
                commentFeedback = StandupFeedback(
                    message: error.localizedDescription,
                    isError: true
                )
            }
        }
    }

    private func inspectorSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .bold))
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(11)
                .background(
                    Color(NSColor.controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                )
        }
    }
}

private struct JiraStandupMetricCard: View {
    let title: String
    let value: String
    let detail: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
                Spacer()
                Image(systemName: icon)
                    .foregroundStyle(tint)
            }
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text(detail)
                .font(.system(size: 8))
                .foregroundStyle(Color(NSColor.tertiaryLabelColor))
        }
        .padding(13)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(NSColor.separatorColor).opacity(0.45), lineWidth: 0.5)
        )
    }
}

private struct JiraStandupStatusPill: View {
    let status: String
    let group: JiraStatusGroup

    var body: some View {
        Text(status)
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(statusColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(statusColor.opacity(0.12), in: Capsule())
    }

    private var statusColor: Color {
        switch group {
        case .all: .secondary
        case .toDo: .orange
        case .inProgress: .blue
        case .done: .green
        }
    }
}

private func standupStateColor(_ state: JiraStandupState) -> Color {
    switch state {
    case .ongoing: .blue
    case .blocked: .red
    case .done: .green
    }
}
