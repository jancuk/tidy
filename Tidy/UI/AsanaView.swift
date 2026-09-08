import SwiftUI

struct AsanaView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var asanaService: AsanaService
    @State private var searchText = ""
    @State private var filter = AsanaTaskFilter.all

    var body: some View {
        VStack(spacing: 0) {
            workspaceHeader
            Divider().opacity(0.55)
            filterBar
            Divider().opacity(0.4)
            content
        }
        .background(WorkspaceDesign.canvas)
        .task {
            guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
            await asanaService.load()
        }
    }

    private var workspaceHeader: some View {
        WorkspaceHeader(title: "Asana", subtitle: asanaService.currentUser.map { "\($0.name) · My tasks" } ?? "Your tasks, with room to focus.") {
            if !asanaService.workspaces.isEmpty {
                Picker("Workspace", selection: workspaceBinding) {
                    ForEach(asanaService.workspaces) { workspace in
                        Text(workspace.name).tag(workspace.gid)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 210)
            }

            if let lastUpdated = asanaService.lastUpdated {
                Text(lastUpdated, style: .relative)
                    .font(.system(size: 10))
                    .foregroundStyle(Color(NSColor.tertiaryLabelColor))
            }

            Button {
                Task { await asanaService.load() }
            } label: {
                if asanaService.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(WorkspaceButtonStyle())
            .controlSize(.small)
            .help("Refresh Asana tasks")
            .disabled(asanaService.isLoading)
        }

    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            ForEach(AsanaTaskFilter.allCases) { item in
                Button {
                    filter = item
                } label: {
                    Label(item.rawValue, systemImage: item.systemImage)
                        .font(.system(size: 11, weight: filter == item ? .semibold : .regular))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .foregroundStyle(
                            filter == item ? Color.primary : Color(NSColor.secondaryLabelColor)
                        )
                        .background(
                            filter == item ? WorkspaceDesign.inset : Color.clear,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color(NSColor.tertiaryLabelColor))
            TextField("Search tasks", text: $searchText)
                .textFieldStyle(.plain)
                .frame(width: 190)
        }
        .padding(.horizontal, 18)
        .frame(height: 48)
        .background(WorkspaceDesign.surface.opacity(0.65))
    }

    @ViewBuilder
    private var content: some View {
        if !asanaService.isConfigured {
            ContentUnavailableView {
                Label("Connect Asana", systemImage: "checklist")
            } description: {
                Text("Add your App credentials and connect your Asana account in Settings.")
            } actions: {
                Button("Open Settings") {
                    appState.selectedDashboardSection = .settings
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if asanaService.isLoading && asanaService.tasks.isEmpty {
            ProgressView("Loading your Asana tasks…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = asanaService.errorMessage, asanaService.tasks.isEmpty {
            ContentUnavailableView {
                Label("Couldn’t Load Asana", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            } actions: {
                Button("Try Again") {
                    Task { await asanaService.load() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredTasks.isEmpty {
            ContentUnavailableView {
                Label("No Tasks", systemImage: "checkmark.circle")
            } description: {
                Text(searchText.isEmpty ? "Nothing matches this view." : "No tasks match “\(searchText)”.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                summaryStrip
                Divider().opacity(0.45)
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredTasks) { task in
                            taskRow(task)
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    private var summaryStrip: some View {
        HStack(spacing: 18) {
            metric("\(asanaService.tasks.count)", "Open", "tray.full")
            metric("\(overdueCount)", "Overdue", "exclamationmark.circle", tint: overdueCount > 0 ? .red : .secondary)
            metric("\(todayCount)", "Due today", "calendar", tint: todayCount > 0 ? .orange : .secondary)
            Spacer()
            if let error = asanaService.errorMessage {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.red)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 52)
    }

    private func metric(_ value: String, _ label: String, _ icon: String, tint: Color = .secondary) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color(NSColor.secondaryLabelColor))
        }
    }

    private func taskRow(_ task: AsanaTask) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                Task { await asanaService.setCompleted(true, task: task) }
            } label: {
                if asanaService.updatingTaskIDs.contains(task.id) {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 18, height: 18)
                } else {
                    Image(systemName: "circle")
                        .font(.system(size: 18))
                        .foregroundStyle(Color(NSColor.tertiaryLabelColor))
                }
            }
            .buttonStyle(.plain)
            .help("Mark complete")

            VStack(alignment: .leading, spacing: 7) {
                Text(task.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(NSColor.labelColor))
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 6) {
                    ForEach(task.projectNames.prefix(2), id: \.self) { project in
                        chip(project, color: .accentColor)
                    }
                    ForEach(task.sectionNames.prefix(1), id: \.self) { section in
                        chip(section, color: .secondary)
                    }
                    if task.projectNames.isEmpty && task.sectionNames.isEmpty {
                        Text("My Tasks")
                            .font(.system(size: 10))
                            .foregroundStyle(Color(NSColor.tertiaryLabelColor))
                    }
                }
            }

            if let dueDate = task.dueDate {
                dueDateBadge(dueDate)
            }

            Button {
                asanaService.openInAsana(task)
            } label: {
                Image(systemName: "arrow.up.right.square")
            }
            .buttonStyle(.plain)
            .help("Open in Asana")
            .disabled(task.permalinkURL == nil)
        }
        .padding(13)
        .background(
            WorkspaceDesign.surface,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(NSColor.separatorColor).opacity(0.45), lineWidth: 0.5)
        )
    }

    private func chip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.10), in: Capsule())
    }

    private func dueDateBadge(_ date: Date) -> some View {
        let overdue = date < Calendar.current.startOfDay(for: Date())
        let today = Calendar.current.isDateInToday(date)
        let color: Color = overdue ? .red : (today ? .orange : .secondary)
        return Label {
            Text(date, format: .dateTime.month(.abbreviated).day())
        } icon: {
            Image(systemName: overdue ? "exclamationmark.circle.fill" : "calendar")
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.10), in: Capsule())
    }

    private var workspaceBinding: Binding<String> {
        Binding(
            get: { asanaService.selectedWorkspaceGID },
            set: { gid in
                Task { await asanaService.selectWorkspace(gid) }
            }
        )
    }

    private var filteredTasks: [AsanaTask] {
        asanaService.tasks.filter { task in
            let matchesFilter = filter.includes(task)
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return matchesFilter }
            let haystack = ([task.name] + task.projectNames + task.sectionNames)
                .joined(separator: " ")
            return matchesFilter && haystack.localizedCaseInsensitiveContains(query)
        }
    }

    private var overdueCount: Int {
        asanaService.tasks.filter { AsanaTaskFilter.overdue.includes($0) }.count
    }

    private var todayCount: Int {
        asanaService.tasks.filter { AsanaTaskFilter.today.includes($0) }.count
    }
}
