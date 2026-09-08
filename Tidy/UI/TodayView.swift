import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TodayView: View {
    @EnvironmentObject private var productivity: ProductivityService
    @EnvironmentObject private var sync: ProductivitySyncService
    @State private var showSyncSettings = false
    @State private var captureText = ""
    @State private var captureKind: ProductivityKind = .task
    @State private var showReminderSettings = false
    @State private var showJournal = false
    @State private var captureDraftID: UUID?
    @State private var savedMessage: String?
    @FocusState private var composerFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            sections
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let error = productivity.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout).foregroundStyle(.red).textSelection(.enabled)
                        if !productivity.storageReady {
                            Button("Retry loading workspace") { productivity.reload() }
                        }
                    }
                    if let message = productivity.reminderMessage {
                        Label(message, systemImage: "bell.slash").font(.callout).foregroundStyle(.orange)
                    }
                    if productivity.search.isEmpty { workspaceIntroduction }
                    if let session = productivity.snapshot.session { sessionCard(session) }
                    captureBar
                    if productivity.selectedSection == .exercises && productivity.search.isEmpty { routineStarters }
                    if productivity.selectedSection == .reminders && productivity.search.isEmpty { reminderOverview }
                    if !productivity.search.isEmpty {
                        Text("Search results across \(productivity.selectedSection == .archive ? "archived items" : "your workspace")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if !productivity.visibleItems.isEmpty {
                        HStack {
                            Text(productivity.search.isEmpty ? "\(productivity.selectedSection.rawValue) · \(productivity.visibleItems.count)" : "\(productivity.visibleItems.count) results")
                                .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                            Spacer()
                            if productivity.selectedSection == .today {
                                Button("View all pending") { productivity.selectedSection = .pending }
                                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary)
                            }
                        }
                        LazyVStack(spacing: 10) {
                            ForEach(productivity.visibleItems) { item in itemRow(item) }
                        }
                    } else if !productivity.search.isEmpty {
                        ContentUnavailableView("No matching items", systemImage: "magnifyingglass",
                                               description: Text("Try a title, tag, or phrase from your notes."))
                    } else if productivity.selectedSection != .today {
                        Text(productivity.selectedSection.emptyDetail)
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.top, 8)
                    }

                }
                .padding(.horizontal, 32).padding(.top, 36).padding(.bottom, 40)
                .frame(maxWidth: 860)
                .frame(maxWidth: .infinity)
            }
        }
        .background(WorkspaceDesign.canvas)
        .onAppear { productivity.start(); updateCaptureKind() }
        .onChange(of: productivity.selectedSection) { _, _ in
            if captureText.isEmpty { updateCaptureKind() }
        }
        .onChange(of: productivity.editorItem) { _, item in
            if item == nil, let id = captureDraftID {
                if productivity.snapshot.items.contains(where: { $0.id == id }) {
                    captureText = ""
                    savedMessage = "Saved to your workspace"
                }
                captureDraftID = nil
            }
        }
        .onChange(of: captureText) { _, text in if !text.isEmpty { savedMessage = nil } }
        .sheet(item: $productivity.editorItem) { item in
            ProductivityItemEditor(item: item).environmentObject(productivity)
        }
        .sheet(item: $productivity.editingDailyNote) { note in
            DailyFocusEditor(note: note).environmentObject(productivity)
        }
        .sheet(isPresented: $showReminderSettings) {
            ProductivityReminderSettings().environmentObject(productivity)
        }
        .sheet(isPresented: $showJournal) { journal }
        .sheet(isPresented: $showSyncSettings) {
            ProductivitySyncView().environmentObject(productivity).environmentObject(sync)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Today").font(.system(size: 15, weight: .semibold))
            Text("/  Your personal workspace").font(.system(size: 12)).foregroundStyle(.tertiary)
            Spacer()
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search anything", text: $productivity.search)
                    .textFieldStyle(.plain).accessibilityLabel("Search productivity workspace")
                if !productivity.search.isEmpty {
                    Button { productivity.search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).accessibilityLabel("Clear search")
                }
            }
            .font(.system(size: 12)).padding(9).frame(width: 205)
            .background(WorkspaceDesign.inset, in: RoundedRectangle(cornerRadius: 9))
            Button { showSyncSettings = true } label: {
                Image(systemName: sync.message != nil || !sync.conflicts.isEmpty ? "icloud.slash" : sync.isEnabled ? "icloud.fill" : "icloud")
                    .foregroundStyle(sync.message != nil || !sync.conflicts.isEmpty ? Color.orange : Color.secondary)
            }.buttonStyle(.plain).help(sync.status).accessibilityLabel("Google Drive sync: " + sync.status)
            Menu {
                Button("Google Drive backup & sync…") { showSyncSettings = true }
                Button("Daily focus history") { showJournal = true }
                Button("Reminder settings") { showReminderSettings = true }
                Button("Export workspace as Markdown…", action: exportWorkspace)
            } label: { Image(systemName: "ellipsis").frame(width: 24, height: 24) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Workspace options")
        }.padding(.horizontal, 28).padding(.vertical, 18)
    }

    private var sections: some View {
        HStack(spacing: 20) {
            ForEach(ProductivitySection.allCases) { section in
                Button { productivity.selectedSection = section; productivity.search = "" } label: {
                    VStack(spacing: 12) {
                        Label(section.rawValue, systemImage: section.icon)
                            .font(.system(size: 12, weight: productivity.selectedSection == section ? .semibold : .regular))
                            .foregroundStyle(productivity.selectedSection == section ? Color.primary : Color.secondary)
                        Capsule().fill(productivity.selectedSection == section ? Color.primary : .clear).frame(height: 2)
                    }.fixedSize(horizontal: true, vertical: false)
                }.buttonStyle(.plain)
                    .accessibilityAddTraits(productivity.selectedSection == section ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }.padding(.horizontal, 28).padding(.top, 8)
            .overlay(alignment: .bottom) { WorkspaceDesign.border.frame(height: 1).offset(y: 1) }
    }

    private var workspaceIntroduction: some View {
        VStack(spacing: 14) {
            HStack(spacing: 9) {
                Image("TidyLogo").resizable().frame(width: 28, height: 28).accessibilityLabel("Tidy logo")
                Text(productivity.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            }
            Text(productivity.selectedSection == .today ? greeting : sectionHeading)
                .font(.system(size: 33, weight: .regular, design: .serif))
                .multilineTextAlignment(.center)
            Text(sectionSubtitle).font(.system(size: 14)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if productivity.selectedSection == .today {
                HStack(spacing: 8) {
                    summaryChip(productivity.todayTasks.count, "for today", section: .today)
                    summaryChip(productivity.pendingTasks.count, "pending", section: .pending)
                    if !productivity.overdueTasks.isEmpty {
                        summaryChip(productivity.overdueTasks.count, "overdue", section: .reminders)
                    }
                    summaryChip(productivity.completedTodayCount, "done", section: .completed)
                }.padding(.top, 3)
                if !productivity.todayNote.intention.isEmpty {
                    Button { productivity.editingDailyNote = productivity.todayNote } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "scope").foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("TODAY'S FOCUS").font(.system(size: 9, weight: .semibold)).tracking(1.4).foregroundStyle(.secondary)
                                Text(productivity.todayNote.intention).font(.system(size: 14)).lineLimit(3)
                            }
                            Spacer()
                            Image(systemName: "pencil").font(.system(size: 12)).foregroundStyle(.secondary)
                        }.padding(16).background(WorkspaceDesign.inset, in: RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain).help("Edit daily focus").padding(.top, 6)
                }
            }
        }.frame(maxWidth: .infinity).padding(.top, 8).padding(.bottom, 4)
    }

    private var greeting: String {
        let hour = productivity.calendar.component(.hour, from: productivity.now)
        return hour < 12 ? "A little space to think." : hour < 18 ? "What's on your mind?" : "Let the day settle."
    }

    private var sectionHeading: String {
        switch productivity.selectedSection {
        case .today: greeting
        case .pending: "One thing at a time."
        case .notes: "Keep a thought for later."
        case .exercises: "Make time for yourself."
        case .reminders: "A little less to remember."
        case .completed: "Look how far you've come."
        case .archive: "Out of the way. Still here."
        }
    }

    private var sectionSubtitle: String {
        switch productivity.selectedSection {
        case .today: "A thought, a task, a fresh start. It all belongs here."
        case .pending: "Your next steps, ready when you are."
        case .notes: "Ideas, code snippets, and the context you don't want to lose."
        case .exercises: "Coding practice, a movement break, or a routine that's yours."
        case .reminders: "Keep the important things close, without keeping them in your head."
        case .completed: "Finished tasks and today's routine completions."
        case .archive: "Restore anything whenever you need it again."
        }
    }

    private func summaryChip(_ count: Int, _ title: String, section: ProductivitySection) -> some View {
        Button { productivity.selectedSection = section } label: {
            HStack(spacing: 5) {
                Text(count.formatted()).fontWeight(.semibold)
                Text(title).foregroundStyle(.secondary)
            }.font(.system(size: 11)).padding(.horizontal, 11).padding(.vertical, 6)
                .background(WorkspaceDesign.inset, in: Capsule())
        }.buttonStyle(.plain)
    }

    private var captureBar: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 14) {
                ZStack(alignment: .topLeading) {
                    if captureText.isEmpty {
                        Text(captureKind == .note ? "Let your thoughts land here…" : captureKind == .exercise ? "What would you like to make time for?" : "What would you like to get done?")
                            .foregroundStyle(.tertiary).padding(.leading, 5).padding(.top, 8)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $captureText)
                        .scrollContentBackground(.hidden).focused($composerFocused)
                        .accessibilityLabel("Quick capture")
                }
                .font(.system(size: 16)).lineSpacing(7)
                .frame(height: 116)
                HStack(spacing: 5) {
                    ForEach(ProductivityKind.allCases) { kind in
                        Button { captureKind = kind; composerFocused = true } label: {
                            Label(kind.title, systemImage: kind.icon)
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 11).padding(.vertical, 7)
                                .background(captureKind == kind ? WorkspaceDesign.inset : .clear, in: Capsule())
                                .foregroundStyle(captureKind == kind ? Color.primary : Color.secondary)
                        }.buttonStyle(.plain)
                            .accessibilityAddTraits(captureKind == kind ? .isSelected : [])
                    }
                    Spacer(minLength: 6)
                    Button(action: composeDetails) {
                        Image(systemName: "slider.horizontal.3").frame(width: 30, height: 30)
                    }.buttonStyle(.plain).foregroundStyle(.secondary)
                        .help("Add details, tags, and a reminder").accessibilityLabel("Add details")
                    Button(action: quickCapture) {
                        Image(systemName: "arrow.up").font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(canCapture ? WorkspaceDesign.canvas : Color.secondary)
                            .frame(width: 34, height: 34)
                            .background(canCapture ? Color.primary : WorkspaceDesign.inset, in: Circle())
                    }.buttonStyle(.plain).keyboardShortcut(.return, modifiers: .command)
                        .disabled(!canCapture).accessibilityLabel("Save \(captureKind.title.lowercased())")
                        .help("Save \(captureKind.title.lowercased()) (⌘Return)")
                }
            }
            .padding(20)
            .background(WorkspaceDesign.surface, in: RoundedRectangle(cornerRadius: 23))
            .overlay(RoundedRectangle(cornerRadius: 23).strokeBorder(composerFocused ? Color.accentColor.opacity(0.5) : WorkspaceDesign.border))
            .shadow(color: .black.opacity(composerFocused ? 0.07 : 0.035), radius: 18, y: 5)
            HStack(spacing: 5) {
                Image(systemName: savedMessage == nil ? "lock" : "checkmark.circle")
                Text(savedMessage ?? (sync.isEnabled ? "Saved locally · Drive folder connected" : "Saved on this Mac"))
                Spacer()
                Text("Return for a new line · ⌘Return to save")
            }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 6)
            if productivity.selectedSection == .today && productivity.search.isEmpty {
                HStack(spacing: 8) {
                    Button { productivity.editingDailyNote = productivity.todayNote } label: {
                        Label(productivity.todayNote.intention.isEmpty ? "Plan my day" : "Edit my focus", systemImage: "scope")
                    }
                    Button { productivity.selectedSection = .notes } label: { Label("My notes", systemImage: "note.text") }
                    Button { productivity.selectedSection = .exercises } label: { Label("Take a break", systemImage: "cup.and.saucer") }
                }.buttonStyle(WorkspaceButtonStyle()).padding(.top, 9)
            }
        }.disabled(!productivity.storageReady)
    }

    private var canCapture: Bool { !captureText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && productivity.storageReady }

    private func composeDetails() {
        let lines = captureText.split(separator: "\n", omittingEmptySubsequences: false)
        productivity.beginCapture(captureKind, title: lines.first.map(String.init) ?? "", body: lines.dropFirst().joined(separator: "\n"))
        captureDraftID = productivity.editorItem?.id
    }

    private var routineStarters: some View {
        HStack(spacing: 10) {
            Text("TRY A ROUTINE").font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
            Button { productivity.beginCapture(.exercise, title: "Coding practice", duration: 25) } label: {
                Label("Coding practice", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            Button { productivity.beginCapture(.exercise, title: "Movement break", duration: 5) } label: {
                Label("Movement break", systemImage: "figure.walk")
            }
            Button("Custom routine") { productivity.beginCapture(.exercise) }
        }.buttonStyle(WorkspaceButtonStyle()).frame(maxWidth: .infinity)
    }

    private var reminderOverview: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Label(productivity.snapshot.preferences.notificationsEnabled ? "Local notifications enabled" : "Reminders stay visible here",
                      systemImage: productivity.snapshot.preferences.notificationsEnabled ? "bell.badge" : "bell.slash")
                    .font(.system(size: 14, weight: .semibold))
                Text("Enable macOS alerts and an optional daily planning reminder. Nothing is posted to other apps.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Reminder settings") { showReminderSettings = true }
        }.padding(16).background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private func itemRow(_ item: ProductivityItem) -> some View {
        let complete = item.isComplete(at: productivity.now, calendar: productivity.calendar)
        return HStack(alignment: .top, spacing: 12) {
            if item.kind == .note {
                Image(systemName: "note.text").font(.system(size: 18)).foregroundStyle(.orange).padding(.top, 2)
            } else {
                Button { productivity.toggleComplete(item) } label: {
                    Image(systemName: complete ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20)).foregroundStyle(complete ? Color.green : Color.secondary)
                }
                .buttonStyle(.plain).disabled(item.archivedAt != nil)
                .help(complete ? "Mark incomplete" : item.isRecurring ? "Log exercise for today" : "Mark complete")
                .accessibilityLabel("\(complete ? "Reopen" : "Complete") \(item.title)")
            }
            Button { productivity.editorItem = item } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(item.title).font(.system(size: 14, weight: .semibold))
                            .strikethrough(complete && item.kind != .note).foregroundStyle(complete ? .secondary : .primary)
                        if item.pinned { Image(systemName: "pin.fill").font(.caption).foregroundStyle(Color.accentColor) }
                        if item.priority == .high { Text("High priority").font(.system(size: 10, weight: .medium)).foregroundStyle(.orange) }
                    }
                    if let source = item.source {
                        HStack(spacing: 6) {
                            Label(source.appName ?? "Captured text", systemImage: "link")

                        }.font(.caption).foregroundStyle(.secondary)
                    }
                    if !item.body.isEmpty {
                        Text(item.body).font(.system(size: 13)).lineSpacing(4).foregroundStyle(.secondary).lineLimit(2)
                    }
                    HStack(spacing: 10) {
                        Text(item.kind.title).font(.system(size: 10, weight: .medium))
                        if item.kind == .exercise {
                            Text("\(item.cadence.rawValue) · \(item.durationMinutes) min")
                            Text("\(item.exerciseCompletions.count + (item.completedAt == nil ? 0 : 1)) completions")
                        }
                        if let due = item.dueAt {
                            Label(item.isRecurring ? due.formatted(date: .omitted, time: .shortened) : due.formatted(date: .abbreviated, time: .shortened),
                                  systemImage: item.reminderEnabled ? "bell" : "calendar")
                                .foregroundStyle(item.isOverdue(at: productivity.now) ? Color.red : Color.secondary)
                        }
                        if let planned = item.plannedDay, item.kind == .task {
                            Text("Planned \(planned.formatted(date: .abbreviated, time: .omitted))")
                        }
                        if !item.tags.isEmpty { Text(item.tags.map { "#" + $0 }.joined(separator: " ")).lineLimit(1) }
                    }.font(.system(size: 10)).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if let url = CaptureSource.safeURL(item.source?.url?.absoluteString) {
                Link(destination: url) { Image(systemName: "arrow.up.right.square") }.help("Open source")
            }
            if item.archivedAt == nil {
                if item.kind == .exercise && !complete {
                    Button("Start \(item.durationMinutes)m") { productivity.startSession(item) }
                        .controlSize(.small).disabled(productivity.snapshot.session != nil)
                } else if item.kind == .task && !complete && !item.isInToday(at: productivity.now, calendar: productivity.calendar) {
                    Button("Today") { productivity.plan(item, for: productivity.now) }.controlSize(.small)
                }
            }
            Menu {
                Button("Edit") { productivity.editorItem = item }
                if item.archivedAt != nil {
                    Button("Restore") { productivity.archive(item) }
                } else {
                    if item.kind != .exercise {
                        Button("Plan for today") { productivity.plan(item, for: productivity.now) }
                        Button("Plan for tomorrow") { productivity.plan(item, for: productivity.calendar.date(byAdding: .day, value: 1, to: productivity.now)) }
                        Button("Remove from plan") { productivity.plan(item, for: nil) }
                    }
                    Button(item.pinned ? "Unpin" : "Pin") { productivity.togglePin(item) }
                    if item.dueAt != nil && !item.isRecurring && !complete {
                        Button("Snooze reminder 15 minutes") { productivity.snooze(item) }
                    }
                    Divider()
                    Button("Archive") { productivity.archive(item) }
                }
            } label: { Image(systemName: "ellipsis") }.fixedSize().menuStyle(.borderlessButton)
        }
        .padding(18)
        .background(WorkspaceDesign.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(WorkspaceDesign.border))
    }

    private func sessionCard(_ session: ExerciseSession) -> some View {
        let remaining = Int(ceil(session.remaining(at: productivity.now)))
        return HStack(spacing: 14) {
            Image(systemName: remaining == 0 ? "checkmark.seal" : "timer").font(.title2).foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(session.title).font(.headline)
                Text(remaining == 0 ? "Time is up. Log it when you are ready." : session.pausedSeconds == nil ? "One thing at a time." : "Session paused.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(String(format: "%02d:%02d", remaining / 60, remaining % 60))
                .font(.system(size: 26, weight: .semibold, design: .monospaced)).monospacedDigit()
            if remaining > 0 {
                Button(session.pausedSeconds == nil ? "Pause" : "Resume") { productivity.toggleSessionPause() }
            }
            Button("Log done") { productivity.finishSession() }.buttonStyle(WorkspaceButtonStyle(prominent: true))
            Button("Stop") { productivity.stopSession() }
        }.padding(16).background(Color.accentColor.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
    }

    private var journal: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Text("Daily focus history").font(.title2.bold())
                Spacer()
                Button("Done") { showJournal = false }
            }
            ScrollView {
                if productivity.snapshot.dailyNotes.isEmpty { Text("Your daily focus notes will appear here.").foregroundStyle(.secondary) }
                ForEach(productivity.snapshot.dailyNotes.sorted { $0.date > $1.date }) { note in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(note.date.formatted(date: .complete, time: .omitted)).font(.headline)
                        Text(note.intention).textSelection(.enabled)
                        if !note.reflection.isEmpty { Text(note.reflection).foregroundStyle(.secondary).textSelection(.enabled) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }.padding(24).frame(width: 600, height: 450)
    }

    private func updateCaptureKind() {
        switch productivity.selectedSection {
        case .notes: captureKind = .note
        case .exercises: captureKind = .exercise
        default: captureKind = .task
        }
    }

    private func quickCapture() {
        if productivity.quickCapture(captureText, kind: captureKind) {
            captureText = ""
            if captureKind == .note { productivity.selectedSection = .notes }
            if captureKind == .exercise { productivity.selectedSection = .exercises }
            savedMessage = "Saved to \(productivity.selectedSection.rawValue.lowercased())"
            composerFocused = true
        }
    }

    private func exportWorkspace() {
        let panel = NSSavePanel()
        panel.title = "Export your notes and plans"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "tidy-workspace.md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        productivity.exportMarkdown(to: url)
    }
}

private struct DailyFocusEditor: View {
    @EnvironmentObject private var productivity: ProductivityService
    @EnvironmentObject private var sync: ProductivitySyncService
    @State private var showSyncSettings = false
    @Environment(\.dismiss) private var dismiss
    @State var note: DailyFocusNote

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image("TidyLogo").resizable().frame(width: 28, height: 28)
                Text(note.date.formatted(date: .complete, time: .omitted)).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Text("Make room for what matters.").font(.system(size: 28, design: .serif))
            Text("What would make today a good day?").font(.system(size: 13)).foregroundStyle(.secondary)
            TodayWritingField(text: $note.intention, placeholder: "A focus, a few next steps, or just a place to begin…", label: "Today's focus", height: 155)
            Text("A note for your future self").font(.system(size: 13)).foregroundStyle(.secondary)
            TodayWritingField(text: $note.reflection, placeholder: "What went well? What can wait until tomorrow?", label: "Daily reflection", height: 135)
            if let error = productivity.errorMessage { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save daily focus") { if productivity.saveDailyNote(note) { dismiss() } }
                    .buttonStyle(WorkspaceButtonStyle(prominent: true)).keyboardShortcut(.return, modifiers: .command)
            }
        }.padding(30).frame(width: 620).background(WorkspaceDesign.canvas)
    }
}
