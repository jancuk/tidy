import SwiftUI

struct ProductivityItemEditor: View {
    @EnvironmentObject private var productivity: ProductivityService
    @Environment(\.dismiss) private var dismiss
    @State private var item: ProductivityItem
    @State private var tags: String
    @State private var enablingNotifications = false
    @State private var showOptions: Bool
    @State private var codeFont = false

    init(item: ProductivityItem) {
        _item = State(initialValue: item)
        _tags = State(initialValue: item.tags.joined(separator: ", "))
        _showOptions = State(initialValue: item.kind == .exercise || item.dueAt != nil || !item.tags.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image("TidyLogo").resizable().frame(width: 26, height: 26)
                Label(item.kind.title, systemImage: item.kind.icon).font(.system(size: 13, weight: .medium))
                Spacer()
                Label("Saved to your workspace", systemImage: "checkmark.shield").font(.caption).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TextField("Give it a title…", text: $item.title)
                        .font(.system(size: 28, weight: .regular, design: .serif)).textFieldStyle(.plain)
                        .padding(.vertical, 10).accessibilityLabel("Item title")
                    HStack {
                        Text(item.kind == .note ? "A little space for your thoughts" : "Details and next steps")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                        Spacer()
                        Toggle("Code font", isOn: $codeFont).toggleStyle(.button)
                            .font(.system(size: 11)).buttonStyle(WorkspaceButtonStyle())
                    }
                    TodayWritingField(text: $item.body,
                                      placeholder: item.kind == .note ? "Write freely. Ideas, snippets, links — anything you want to keep." : "Add context, a checklist, or the first small step…",
                                      label: "Item details", height: 245, monospaced: codeFont)
                    if let source = item.source {
                        HStack {
                            Label(source.appName ?? "Captured text", systemImage: "link").font(.caption).foregroundStyle(.secondary)
                            if let url = CaptureSource.safeURL(source.url?.absoluteString) { Link("Open source", destination: url).font(.caption) }
                        }
                    }
                    DisclosureGroup(isExpanded: $showOptions) {
                        VStack(alignment: .leading, spacing: 16) {
                            TextField("Tags, separated by commas", text: $tags).textFieldStyle(.roundedBorder)
                            HStack {
                                Picker("Priority", selection: $item.priority) {
                                    ForEach(ProductivityPriority.allCases) { Text($0.title).tag($0) }
                                }.frame(width: 220)
                                Spacer()
                                Toggle(item.kind == .note ? "Pin to Today" : "Pin item", isOn: $item.pinned)
                            }
                            Divider()
                            if item.kind == .exercise { routineFields }
                            else { planningFields }
                            reminderFields
                        }.padding(16)
                    } label: {
                        Label(item.kind == .exercise ? "Routine, tags & reminders" : "Organize, plan & remind me", systemImage: "slider.horizontal.3")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(12).background(WorkspaceDesign.inset, in: RoundedRectangle(cornerRadius: 12))
                    if item.kind == .exercise, !item.exerciseCompletions.isEmpty {
                        DisclosureGroup("Completion history · \(item.exerciseCompletions.count) sessions") {
                            ForEach(Array(item.exerciseCompletions.sorted(by: >).enumerated()), id: \.offset) { _, date in
                                Text(date.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    if let error = productivity.errorMessage {
                        Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(.trailing, 5)
            }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction).buttonStyle(WorkspaceButtonStyle())
                Spacer()
                Text("⌘S to save").font(.system(size: 11)).foregroundStyle(.tertiary)
                Button("Save \(item.kind.title.lowercased())") {
                    item.tags = tags.components(separatedBy: ",")
                    if productivity.save(item) { dismiss() }
                }
                .buttonStyle(WorkspaceButtonStyle(prominent: true)).keyboardShortcut("s", modifiers: .command)
                .disabled(item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !productivity.storageReady)
            }
        }.padding(30).frame(width: 670, height: 690).background(WorkspaceDesign.canvas)
    }

    private var planningFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Add to a daily plan", isOn: Binding(
                get: { item.plannedDay != nil },
                set: { item.plannedDay = $0 ? productivity.calendar.startOfDay(for: productivity.now) : nil }
            ))
            if item.plannedDay != nil {
                DatePicker("Plan for", selection: Binding(get: { item.plannedDay ?? productivity.now }, set: { item.plannedDay = $0 }), displayedComponents: .date)
            }
        }
    }

    private var routineFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Repeat", selection: $item.cadence) {
                    ForEach(RoutineCadence.allCases) { Text($0.rawValue).tag($0) }
                }.frame(width: 240)
                Spacer()
                Stepper("\(item.durationMinutes) minutes", value: $item.durationMinutes, in: 1...180)
            }
            if item.cadence == .weekly {
                Picker("Day of week", selection: $item.routineWeekday) {
                    ForEach(1...7, id: \.self) { weekday in
                        Text(productivity.calendar.weekdaySymbols[weekday - 1]).tag(weekday)
                    }
                }
            }
            if item.cadence == .once {
                DatePicker("Exercise day", selection: $item.routineStart, displayedComponents: .date)
            }
            Text("Use this for coding practice, movement breaks, or any custom routine. Starting a timer does not mark the exercise complete.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .onChange(of: item.cadence) { _, _ in
            if item.isRecurring { item.routineStart = productivity.calendar.startOfDay(for: productivity.now) }
            alignExerciseReminder()
        }
        .onChange(of: item.routineStart) { _, _ in alignExerciseReminder() }
    }

    private var reminderFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(item.kind == .exercise ? "Set a reminder time" : "Set a due date / reminder", isOn: Binding(
                get: { item.dueAt != nil },
                set: {
                    item.dueAt = $0 ? productivity.now.addingTimeInterval(3600) : nil
                    if !$0 { item.reminderEnabled = false }
                    alignExerciseReminder()
                }
            ))
            if item.dueAt != nil {
                DatePicker(item.kind == .exercise ? "At" : "When", selection: Binding(
                    get: { item.dueAt ?? productivity.now },
                    set: { item.dueAt = $0; alignExerciseReminder() }
                ), displayedComponents: item.kind == .exercise ? [.hourAndMinute] : [.date, .hourAndMinute])
                Toggle("Notify me on this Mac", isOn: $item.reminderEnabled)
                if item.reminderEnabled && !productivity.snapshot.preferences.notificationsEnabled {
                    HStack {
                        Text("macOS alerts are currently off.").font(.caption).foregroundStyle(.secondary)
                        Button("Enable alerts") {
                            enablingNotifications = true
                            Task {
                                await productivity.setNotificationsEnabled(true)
                                enablingNotifications = false
                            }
                        }.disabled(enablingNotifications)
                    }
                }
                if item.isRecurring {
                    Text("Routine reminders repeat on their schedule, including days you log a completion. Archive the routine or turn off its reminder to stop them.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if let due = item.dueAt, due < productivity.now {
                    Text("This time has passed. The item stays visible here; choose a future time for a notification.")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            if let message = productivity.reminderMessage { Text(message).font(.caption).foregroundStyle(.orange) }
        }
    }

    private func alignExerciseReminder() {
        guard item.kind == .exercise, item.cadence == .once, let due = item.dueAt else { return }
        item.dueAt = productivity.calendar.date(bySettingHour: productivity.calendar.component(.hour, from: due),
                                               minute: productivity.calendar.component(.minute, from: due), second: 0, of: item.routineStart)
    }
}

struct ProductivityReminderSettings: View {
    @EnvironmentObject private var productivity: ProductivityService
    @Environment(\.dismiss) private var dismiss
    @State private var morningEnabled = false
    @State private var morningTime = Date()
    @State private var isUpdating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Reminders on this Mac").font(.title2.bold())
            Text("Tidy uses macOS notifications for scheduled items and exercise timers, even when its window is closed. No Slack, email, or calendar events are created.")
                .font(.callout).foregroundStyle(.secondary)
            Toggle("Enable local notifications", isOn: Binding(
                get: { productivity.snapshot.preferences.notificationsEnabled },
                set: { enabled in
                    isUpdating = true
                    Task { await productivity.setNotificationsEnabled(enabled); isUpdating = false }
                }
            )).disabled(isUpdating)
            Divider()
            Toggle("Remind me to plan my day", isOn: $morningEnabled)
            DatePicker("Daily at", selection: $morningTime, displayedComponents: .hourAndMinute).disabled(!morningEnabled)
            Text("The morning reminder opens Today. Your pending items, focus notes, and routines are summarized locally.")
                .font(.caption).foregroundStyle(.secondary)
            if !productivity.snapshot.preferences.notificationsEnabled {
                Text("Dates and reminders remain visible in Tidy while notifications are off.").font(.caption).foregroundStyle(.secondary)
            }
            if let message = productivity.reminderMessage { Text(message).font(.caption).foregroundStyle(.orange) }
            if let error = productivity.errorMessage { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                if isUpdating { ProgressView().controlSize(.small) }
                Spacer()
                Button("Save settings") {
                    productivity.saveReminderPreferences(morningEnabled: morningEnabled, time: morningTime)
                    if productivity.errorMessage == nil { dismiss() }
                }.buttonStyle(WorkspaceButtonStyle(prominent: true)).disabled(isUpdating)
            }
        }
        .padding(24).frame(width: 480)
        .onAppear {
            morningEnabled = productivity.snapshot.preferences.morningReviewEnabled
            morningTime = productivity.calendar.date(bySettingHour: productivity.snapshot.preferences.morningHour,
                                                     minute: productivity.snapshot.preferences.morningMinute, second: 0, of: productivity.now) ?? productivity.now
        }
    }
}
