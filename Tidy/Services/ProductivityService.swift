import Combine
import Foundation

@MainActor
final class ProductivityService: ObservableObject {
    @Published private(set) var snapshot = ProductivitySnapshot()
    @Published private(set) var now: Date
    @Published private(set) var errorMessage: String?
    @Published private(set) var reminderMessage: String?
    @Published private(set) var storageReady = false
    @Published var editorItem: ProductivityItem?
    @Published var editingDailyNote: DailyFocusNote?
    @Published var selectedSection: ProductivitySection = .today
    @Published var search = ""
    var onOpenWorkspace: (() -> Void)?
    var syncDeviceName = "Mac"

    private let store: ProductivityStore
    private let notifier: any ProductivityNotifying
    private let clock: () -> Date
    let calendar: Calendar
    private var timer: AnyCancellable?
    private var reminderTask: Task<Void, Never>?

    init(store: ProductivityStore, notifier: any ProductivityNotifying, calendar: Calendar = .autoupdatingCurrent, clock: @escaping () -> Date = Date.init) {
        self.store = store
        self.notifier = notifier
        self.calendar = calendar
        self.clock = clock
        now = clock()
        reload()
        notifier.onOpenItem = { [weak self] id in
            guard let self else { return }
            onOpenWorkspace?()
            selectedSection = .today
            if let id, let item = snapshot.items.first(where: { $0.id == id && $0.archivedAt == nil }) { editorItem = item }
        }
    }

    var activeItems: [ProductivityItem] { snapshot.items.filter { $0.archivedAt == nil } }
    var pendingTasks: [ProductivityItem] { activeItems.filter { $0.kind == .task && $0.completedAt == nil } }
    var overdueTasks: [ProductivityItem] { pendingTasks.filter { $0.isOverdue(at: now) } }
    var todayTasks: [ProductivityItem] { pendingTasks.filter { $0.isInToday(at: now, calendar: calendar) } }
    var todayExercises: [ProductivityItem] { activeItems.filter { $0.kind == .exercise && $0.isInToday(at: now, calendar: calendar) } }
    var dayID: String { Self.dayID(now, calendar: calendar) }
    var todayNote: DailyFocusNote { snapshot.dailyNotes.first { $0.id == dayID } ?? DailyFocusNote(id: dayID, date: now) }
    var visibleItems: [ProductivityItem] { items(in: selectedSection, search: search) }
    var completedTodayCount: Int {
        activeItems.filter {
            ($0.completedAt.map { calendar.isDate($0, inSameDayAs: now) } ?? false)
                || $0.exerciseCompletions.contains { calendar.isDate($0, inSameDayAs: now) }
        }.count
    }

    func start() {
        guard timer == nil else { return }
        tick()
        syncReminders()
        timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            guard let self else { return }
            if snapshot.session != nil || clock().timeIntervalSince(now) >= 30 { tick() }
        }
    }

    func tick() {
        let oldDay = dayID
        now = clock()
        if oldDay != dayID { syncReminders() }
    }

    func reload() {
        do {
            snapshot = try store.load()
            storageReady = true
            errorMessage = nil
        } catch {
            storageReady = false
            errorMessage = "\(ProductivityError.storageUnavailable.localizedDescription)\n\(error.localizedDescription)"
        }
    }

    func items(in section: ProductivitySection, search: String = "") -> [ProductivityItem] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return snapshot.items.filter { item in
            if !query.isEmpty {
                guard (section == .archive) == (item.archivedAt != nil) else { return false }
                return ([item.title, item.body] + item.tags).joined(separator: " ").localizedCaseInsensitiveContains(query)
            }
            if section == .archive { return item.archivedAt != nil }
            guard item.archivedAt == nil else { return false }
            switch section {
            case .today: return item.isInToday(at: now, calendar: calendar)
            case .pending: return item.kind == .task && item.completedAt == nil
            case .notes: return item.kind == .note
            case .exercises: return item.kind == .exercise
            case .reminders: return item.dueAt != nil && (item.completedAt == nil || item.isRecurring)
            case .completed: return item.completedAt != nil || (item.isRecurring && item.isComplete(at: now, calendar: calendar))
            case .archive: return false
            }
        }.sorted { left, right in
            if section == .completed { return lastCompletion(left) > lastCompletion(right) }
            if left.isComplete(at: now, calendar: calendar) != right.isComplete(at: now, calendar: calendar) {
                return !left.isComplete(at: now, calendar: calendar)
            }
            if left.pinned != right.pinned { return left.pinned }
            if left.priority != right.priority { return left.priority.rawValue > right.priority.rawValue }
            if left.dueAt != right.dueAt { return (left.dueAt ?? .distantFuture) < (right.dueAt ?? .distantFuture) }
            return left.createdAt > right.createdAt
        }
    }

    func beginCapture(_ kind: ProductivityKind, title: String = "", body: String = "", duration: Int = 15) {
        tick()
        var item = ProductivityItem(kind: kind, title: title, body: body, createdAt: now, updatedAt: now, routineStart: now)
        item.durationMinutes = duration
        if kind == .task && selectedSection == .today { item.plannedDay = calendar.startOfDay(for: now) }
        editorItem = item
    }

    @discardableResult
    func quickCapture(_ text: String, kind: ProductivityKind) -> Bool {
        tick()
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var item = ProductivityItem(kind: kind, title: lines.first.map(String.init) ?? "", body: lines.dropFirst().joined(separator: "\n"),
                                    createdAt: now, updatedAt: now, routineStart: now)
        if kind == .task && selectedSection == .today { item.plannedDay = calendar.startOfDay(for: now) }
        return save(item)
    }

    @discardableResult
    func captureText(_ text: String, kind: ProductivityKind, source: CaptureSource) -> Bool {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, text.count <= 100_000, kind != .exercise else {
            errorMessage = "Capture up to 100,000 characters as a task or note."; return false
        }
        tick()
        let title = String((content.components(separatedBy: .newlines).first ?? content).prefix(120))
        var item = ProductivityItem(kind: kind, title: title, body: text, createdAt: now, updatedAt: now, routineStart: now)
        item.source = source
        item.plannedDay = calendar.startOfDay(for: now)
        return save(item)
    }

    @discardableResult
    func save(_ rawItem: ProductivityItem) -> Bool {
        tick()
        var item = rawItem
        item.title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !item.title.isEmpty else { errorMessage = "Give this item a title."; return false }
        guard (1...180).contains(item.durationMinutes), (1...7).contains(item.routineWeekday) else {
            errorMessage = "Choose a valid duration and weekday."; return false
        }
        item.updatedAt = clock()
        item.tags = Array(Set(item.tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty })).sorted()
        if item.dueAt == nil { item.reminderEnabled = false }
        if item.kind == .note { item.completedAt = nil }
        if item.isRecurring { item.completedAt = nil }
        var next = snapshot
        let isNew = !next.items.contains { $0.id == item.id }
        if let index = next.items.firstIndex(where: { $0.id == item.id }) { next.items[index] = item }
        else { next.items.append(item) }
        guard commit(next) else { return false }
        if isNew {
            search = ""
            switch item.kind {
            case .note: selectedSection = .notes
            case .exercise: selectedSection = .exercises
            case .task: selectedSection = item.isInToday(at: now, calendar: calendar) ? .today : .pending
            }
        }
        return true
    }

    func toggleComplete(_ item: ProductivityItem) {
        tick()
        guard item.kind != .note, var current = snapshot.items.first(where: { $0.id == item.id }) else { return }
        if current.isRecurring {
            if current.isComplete(at: now, calendar: calendar) {
                current.exerciseCompletions.removeAll { calendar.isDate($0, inSameDayAs: now) }
            } else { current.exerciseCompletions.append(now) }
        } else { current.completedAt = current.completedAt == nil ? now : nil }
        var next = snapshot
        guard let index = next.items.firstIndex(where: { $0.id == current.id }) else { return }
        current.updatedAt = now
        next.items[index] = current
        if next.session?.itemID == current.id { next.session = nil }
        _ = commit(next)
    }

    func plan(_ item: ProductivityItem, for day: Date?) {
        var updated = item
        updated.plannedDay = day.map { calendar.startOfDay(for: $0) }
        _ = save(updated)
    }

    func togglePin(_ item: ProductivityItem) {
        var updated = item; updated.pinned.toggle(); _ = save(updated)
    }

    func archive(_ item: ProductivityItem) {
        tick()
        var next = snapshot
        guard let index = next.items.firstIndex(where: { $0.id == item.id }) else { return }
        next.items[index].archivedAt = item.archivedAt == nil ? now : nil
        next.items[index].updatedAt = now
        if next.session?.itemID == item.id { next.session = nil }
        _ = commit(next)
    }

    func snooze(_ item: ProductivityItem, minutes: Int = 15) {
        tick()
        guard !item.isRecurring else { return }
        var updated = item
        updated.dueAt = now.addingTimeInterval(TimeInterval(minutes * 60))
        updated.reminderEnabled = true
        _ = save(updated)
    }

    @discardableResult
    func saveDailyNote(_ note: DailyFocusNote) -> Bool {
        var next = snapshot
        if let index = next.dailyNotes.firstIndex(where: { $0.id == note.id }) { next.dailyNotes[index] = note }
        else { next.dailyNotes.append(note) }
        return commit(next)
    }

    func setNotificationsEnabled(_ enabled: Bool) async {
        errorMessage = nil
        if enabled {
            do {
                guard try await notifier.requestAuthorization() else {
                    reminderMessage = "Notifications were not enabled. Your dates and pending items are still available in Tidy."
                    return
                }
            } catch { reminderMessage = error.localizedDescription; return }
        }
        var next = snapshot
        next.preferences.notificationsEnabled = enabled
        if commit(next) { await waitForReminders() }
    }

    func saveReminderPreferences(morningEnabled: Bool, time: Date) {
        var next = snapshot
        next.preferences.morningReviewEnabled = morningEnabled
        next.preferences.morningHour = calendar.component(.hour, from: time)
        next.preferences.morningMinute = calendar.component(.minute, from: time)
        _ = commit(next)
    }

    func startSession(_ item: ProductivityItem) {
        tick()
        guard snapshot.session == nil else { errorMessage = "Finish or stop your current session before starting another."; return }
        guard item.kind == .exercise, item.archivedAt == nil else { return }
        var next = snapshot
        next.session = ExerciseSession(itemID: item.id, title: item.title,
                                       endsAt: now.addingTimeInterval(TimeInterval(item.durationMinutes * 60)))
        _ = commit(next)
    }

    func toggleSessionPause() {
        tick()
        guard var session = snapshot.session, session.remaining(at: now) > 0 else { return }
        if let paused = session.pausedSeconds { session.endsAt = now.addingTimeInterval(paused); session.pausedSeconds = nil }
        else { session.pausedSeconds = session.remaining(at: now) }
        var next = snapshot; next.session = session; _ = commit(next)
    }

    func stopSession() { var next = snapshot; next.session = nil; _ = commit(next) }

    func finishSession() {
        guard let session = snapshot.session, let item = snapshot.items.first(where: { $0.id == session.itemID }) else { return }
        if item.isComplete(at: now, calendar: calendar) { stopSession() }
        else { toggleComplete(item) }
    }

    func exportMarkdown(to url: URL) {
        var lines = ["# Tidy workspace", "", "Exported \(now.formatted(date: .abbreviated, time: .shortened))", ""]
        for item in snapshot.items {
            let check = item.kind == .note ? "" : (item.isComplete(at: now, calendar: calendar) ? "[x] " : "[ ] ")
            lines += ["## \(check)\(item.title)", "", "Type: \(item.kind.title)\(item.archivedAt == nil ? "" : " · Archived")"]
            if let source = item.source {
                if let name = source.appName { lines.append("Captured from: " + name) }
                if let url = CaptureSource.safeURL(source.url?.absoluteString) { lines.append("Source: " + url.absoluteString) }
            }
            if !item.tags.isEmpty { lines.append("Tags: " + item.tags.joined(separator: ", ")) }
            if let due = item.dueAt { lines.append("Due / reminder: \(due.formatted())") }
            if item.kind == .exercise {
                lines.append("Routine: \(item.cadence.rawValue) · \(item.durationMinutes) minutes")
                lines.append("Completed: " + item.exerciseCompletions.map { $0.formatted(date: .abbreviated, time: .omitted) }.joined(separator: ", "))
            }
            lines += ["", item.body, ""]
        }
        lines += ["# Daily focus notes", ""]
        for note in snapshot.dailyNotes.sorted(by: { $0.date > $1.date }) {
            lines += ["## \(note.date.formatted(date: .complete, time: .omitted))", "", note.intention, "", note.reflection, ""]
        }
        do { try Data(lines.joined(separator: "\n").utf8).write(to: url, options: .atomic) }
        catch { errorMessage = "Export failed: \(error.localizedDescription)" }
    }

    func waitForReminders() async { await reminderTask?.value }

    @discardableResult
    func prepareSync() -> Bool {
        let next = ProductivitySyncMerge.recording(snapshot, after: snapshot, device: syncDeviceName)
        return next == snapshot || commit(next, recordChanges: false)
    }

    @discardableResult
    func receiveSync(_ revisions: [ProductivitySyncRevision]) -> Bool {
        do {
            let next = try ProductivitySyncMerge.applying(revisions, to: snapshot)
            return next == snapshot || commit(next, recordChanges: false)
        } catch { errorMessage = error.localizedDescription; return false }
    }

    @discardableResult
    func restoreContents(_ restored: ProductivitySnapshot) -> Bool {
        do { try ProductivitySyncValidation.snapshot(restored) }
        catch { errorMessage = error.localizedDescription; return false }
        var next = snapshot
        let heads = ProductivitySyncMerge.heads(snapshot.syncJournal ?? [])
        var journal = snapshot.syncJournal ?? []
        for item in restored.items {
            if let index = next.items.firstIndex(where: { $0.id == item.id }) { next.items[index] = item }
            else { next.items.append(item) }
            journal.append(ProductivitySyncRevision(parents: (heads["item/\(item.id)"] ?? []).map(\.id), device: syncDeviceName, item: item))
        }
        for note in restored.dailyNotes {
            if let index = next.dailyNotes.firstIndex(where: { $0.id == note.id }) { next.dailyNotes[index] = note }
            else { next.dailyNotes.append(note) }
            journal.append(ProductivitySyncRevision(parents: (heads["day/\(note.id)"] ?? []).map(\.id), device: syncDeviceName, dailyNote: note))
        }
        next.syncJournal = journal
        return commit(next, recordChanges: false)
    }

    @discardableResult
    func resolveSyncConflict(_ conflict: ProductivitySyncConflict, keeping revision: ProductivitySyncRevision, keepBoth: Bool) -> Bool {
        guard let current = ProductivitySyncMerge.conflicts(snapshot.syncJournal ?? []).first(where: { $0.id == conflict.id }),
              Set(current.versions.map(\.id)) == Set(conflict.versions.map(\.id)),
              current.versions.contains(revision) else {
            errorMessage = "This conflict changed. Review the latest versions before choosing one."
            return false
        }
        var next = snapshot
        var resolution = revision
        resolution.id = UUID(); resolution.parents = current.versions.map(\.id)
        resolution.device = syncDeviceName; resolution.createdAt = clock()
        next.syncJournal = (snapshot.syncJournal ?? []) + [resolution]
        if let item = revision.item, let index = next.items.firstIndex(where: { $0.id == item.id }) { next.items[index] = item }
        if let note = revision.dailyNote, let index = next.dailyNotes.firstIndex(where: { $0.id == note.id }) { next.dailyNotes[index] = note }
        if keepBoth {
            for alternative in current.versions where alternative.id != revision.id {
                var copy = alternative.item ?? ProductivityItem(kind: .note, title: alternative.title, body: alternative.detail)
                copy.id = UUID(); copy.title += " (from \(alternative.device))"
                copy.reminderEnabled = false
                next.items.append(copy)
                next.syncJournal?.append(ProductivitySyncRevision(device: syncDeviceName, item: copy))
            }
        }
        return commit(next, recordChanges: false)
    }

    private func commit(_ value: ProductivitySnapshot, recordChanges: Bool = true) -> Bool {
        let next = recordChanges && snapshot.syncJournal != nil
            ? ProductivitySyncMerge.recording(value, after: snapshot, device: syncDeviceName) : value
        guard storageReady else { errorMessage = ProductivityError.storageUnavailable.localizedDescription; return false }
        do {
            _ = try ProductivityReminderPlanner.reminders(for: next, now: clock(), calendar: calendar)
            try store.save(next)
            snapshot = next
            errorMessage = nil
            syncReminders()
            return true
        } catch { errorMessage = "Could not save: \(error.localizedDescription)"; return false }
    }

    private func syncReminders() {
        guard storageReady else { return }
        let previous = reminderTask
        reminderTask = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            do {
                let requests = try ProductivityReminderPlanner.reminders(for: snapshot, now: clock(), calendar: calendar)
                try await notifier.replaceReminders(with: requests)
                reminderMessage = nil
            } catch { reminderMessage = error.localizedDescription }
        }
    }

    private func lastCompletion(_ item: ProductivityItem) -> Date {
        max(item.completedAt ?? .distantPast, item.exerciseCompletions.max() ?? .distantPast)
    }

    static func dayID(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.era, .year, .month, .day], from: date)
        return "\(parts.era ?? 1)-\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }
}
