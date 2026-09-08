import Foundation
import Testing
@testable import Tidy

@MainActor
struct ProductivityTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private func date(_ day: Int, hour: Int = 9, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }
    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TidyProductivityTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
    private func service(at now: Date, store: ProductivityStore? = nil, notifier: FakeProductivityNotifications? = nil) -> ProductivityService {
        ProductivityService(store: store ?? ProductivityStore(fileURL: nil), notifier: notifier ?? FakeProductivityNotifications(), calendar: calendar, clock: { now })
    }

    @Test func capturesNotesAndTasksAndSearchesBodiesAndTags() async {
        let workspace = service(at: date(7))
        #expect(workspace.quickCapture("Follow up on parser\nCheck empty input", kind: .task))
        #expect(workspace.quickCapture("Useful command\nswift test --filter Parser", kind: .note))
        let task = workspace.snapshot.items[0]
        #expect(task.plannedDay == calendar.startOfDay(for: date(7)))
        var note = workspace.snapshot.items[1]
        note.tags = [" Swift ", "swift", "reference"]
        #expect(workspace.save(note))
        #expect(workspace.items(in: .notes, search: "--filter").count == 1)
        #expect(workspace.items(in: .pending, search: "REFERENCE").count == 1)
        #expect(workspace.snapshot.items[1].tags == ["reference", "swift"])
        workspace.toggleComplete(note)
        #expect(workspace.snapshot.items[1].completedAt == nil)
        await workspace.waitForReminders()
    }

    @Test func incompletePlansCarryForwardButFutureTasksStayOutOfToday() {
        let workspace = service(at: date(8))
        var old = ProductivityItem(kind: .task, title: "Carry over", plannedDay: date(7))
        #expect(workspace.save(old))
        #expect(workspace.save(ProductivityItem(kind: .task, title: "Tomorrow", plannedDay: date(9))))
        #expect(workspace.save(ProductivityItem(kind: .task, title: "Deadline", dueAt: date(7))))
        #expect(workspace.todayTasks.map(\.title).sorted() == ["Carry over", "Deadline"])
        #expect(workspace.overdueTasks.count == 1)
        old = workspace.snapshot.items[0]
        workspace.toggleComplete(old)
        #expect(workspace.todayTasks.map(\.title) == ["Deadline"])
        #expect(workspace.items(in: .completed).count == 1)
        workspace.toggleComplete(workspace.snapshot.items[0])
        #expect(workspace.todayTasks.count == 2)
    }

    @Test func savesAndReloadsNotesDailyFocusAndRoutineHistory() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ProductivityStore(fileURL: folder.appendingPathComponent("productivity.json"))
        let workspace = service(at: date(7), store: store)
        #expect(workspace.quickCapture("Design notes\nLine 1\n  code indent\nLine 3", kind: .note))
        #expect(workspace.saveDailyNote(DailyFocusNote(id: workspace.dayID, date: date(7), intention: "Finish the parser", reflection: "Handle empty strings next")))
        let exercise = ProductivityItem(kind: .exercise, title: "Practice", createdAt: date(7), routineStart: date(7))
        #expect(workspace.save(exercise))
        workspace.toggleComplete(exercise)
        let restored = service(at: date(7), store: store)
        #expect(restored.snapshot == workspace.snapshot)
        #expect(restored.todayNote.intention == "Finish the parser")
        #expect(restored.snapshot.items[0].body.contains("  code indent") == true)
        #expect(restored.snapshot.items[1].exerciseCompletions == [date(7)])
        let attributes = try FileManager.default.attributesOfItem(atPath: store.fileURL!.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test func corruptStorageIsPreservedAndBlocksWrites() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("productivity.json")
        let original = Data("not-json-but-important".utf8)
        try original.write(to: url)
        let workspace = service(at: date(7), store: ProductivityStore(fileURL: url))
        #expect(!workspace.storageReady)
        #expect(!workspace.quickCapture("Cannot overwrite", kind: .note))
        #expect(try Data(contentsOf: url) == original)
        try JSONEncoder().encode(ProductivitySnapshot()).write(to: url)
        workspace.reload()
        #expect(workspace.storageReady)
        #expect(workspace.quickCapture("Recovered", kind: .note))
    }

    @Test func failedSaveDoesNotPublishUnsavedItems() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let blocked = folder.appendingPathComponent("not-a-directory")
        try Data("file".utf8).write(to: blocked)
        let workspace = service(at: date(7), store: ProductivityStore(fileURL: blocked.appendingPathComponent("productivity.json")))
        #expect(!workspace.quickCapture("Unsaved", kind: .task))
        #expect(workspace.snapshot.items.isEmpty)
        #expect(workspace.errorMessage?.contains("Could not save") == true)
    }

    @Test func routineCompletionsResetByDayAndRespectWeekdays() {
        let clock = TestClock(now: date(11))
        let workspace = ProductivityService(store: ProductivityStore(fileURL: nil), notifier: FakeProductivityNotifications(), calendar: calendar, clock: { clock.now })
        var routine = ProductivityItem(kind: .exercise, title: "Move", createdAt: date(7), routineStart: date(7))
        #expect(workspace.save(routine))
        workspace.toggleComplete(routine)
        #expect(workspace.items(in: .completed).count == 1)
        clock.now = date(12); workspace.tick()
        #expect(workspace.todayExercises.isEmpty)
        #expect(workspace.items(in: .completed).isEmpty)
        clock.now = date(14); workspace.tick()
        #expect(workspace.todayExercises.count == 1)
        #expect(!workspace.todayExercises[0].isComplete(at: clock.now, calendar: calendar))
        routine = workspace.snapshot.items[0]
        routine.cadence = .weekly; routine.routineWeekday = 2
        #expect(workspace.save(routine))
        #expect(workspace.todayExercises.count == 1)
        clock.now = date(15); workspace.tick()
        #expect(workspace.todayExercises.isEmpty)
    }

    @Test func archiveRestoresItemsAndPreservesCompletionHistory() {
        let workspace = service(at: date(7))
        let routine = ProductivityItem(kind: .exercise, title: "Read code", createdAt: date(7), routineStart: date(7))
        #expect(workspace.save(routine))
        workspace.toggleComplete(routine)
        workspace.archive(workspace.snapshot.items[0])
        #expect(workspace.activeItems.isEmpty)
        #expect(workspace.items(in: .archive).count == 1)
        workspace.archive(workspace.snapshot.items[0])
        #expect(workspace.activeItems.count == 1)
        #expect(workspace.activeItems[0].exerciseCompletions == [date(7)])
    }

    @Test func notificationsRequireOptInAndCancelCompletedOrArchivedItems() async {
        let notifier = FakeProductivityNotifications()
        let workspace = service(at: date(7), notifier: notifier)
        var task = ProductivityItem(kind: .task, title: "Review patch", dueAt: date(7, hour: 10), reminderEnabled: true)
        #expect(workspace.save(task))
        await workspace.waitForReminders()
        #expect(notifier.requests.isEmpty)
        #expect(notifier.permissionRequests == 0)
        await workspace.setNotificationsEnabled(true)
        #expect(notifier.permissionRequests == 1)
        #expect(notifier.requests.count == 1)
        #expect(notifier.requests[0].schedule == .once(date(7, hour: 10)))
        workspace.toggleComplete(task)
        await workspace.waitForReminders()
        #expect(notifier.requests.isEmpty)
        workspace.toggleComplete(workspace.snapshot.items[0])
        await workspace.waitForReminders()
        #expect(notifier.requests.count == 1)
        task = workspace.snapshot.items[0]
        workspace.archive(task)
        await workspace.waitForReminders()
        #expect(notifier.requests.isEmpty)
    }

    @Test func reminderPlannerHandlesMorningWeeklyAndWeekdaySchedules() throws {
        var snapshot = ProductivitySnapshot()
        snapshot.preferences.notificationsEnabled = true
        snapshot.preferences.morningReviewEnabled = true
        snapshot.preferences.morningHour = 8
        snapshot.preferences.morningMinute = 30
        var routine = ProductivityItem(kind: .exercise, title: "Practice", dueAt: date(7, hour: 14, minute: 15), reminderEnabled: true, routineStart: date(7))
        snapshot.items = [routine]
        let weekdays = try ProductivityReminderPlanner.reminders(for: snapshot, now: date(7), calendar: calendar)
        #expect(weekdays.count == 6)
        #expect(Set(weekdays.map(\.id)).count == 6)
        #expect(weekdays.contains { $0.schedule == .weekly(weekday: 6, hour: 14, minute: 15) })
        #expect(weekdays.contains { $0.schedule == .daily(hour: 8, minute: 30) })
        routine.cadence = .weekly; routine.routineWeekday = 4
        snapshot.items = [routine]
        let weekly = try ProductivityReminderPlanner.reminders(for: snapshot, now: date(7), calendar: calendar)
        #expect(weekly.count == 2)
        #expect(weekly[0].schedule == .weekly(weekday: 4, hour: 14, minute: 15))
    }

    @Test func deniedPermissionDoesNotEnableNotificationsAndPastItemsCanBeSnoozed() async {
        let notifier = FakeProductivityNotifications()
        notifier.allowPermission = false
        let workspace = service(at: date(7), notifier: notifier)
        await workspace.setNotificationsEnabled(true)
        #expect(!workspace.snapshot.preferences.notificationsEnabled)
        #expect(notifier.requests.isEmpty)
        notifier.allowPermission = true
        await workspace.setNotificationsEnabled(true)
        let item = ProductivityItem(kind: .task, title: "Old reminder", dueAt: date(6), reminderEnabled: true)
        #expect(workspace.save(item))
        await workspace.waitForReminders()
        #expect(notifier.requests.isEmpty)
        workspace.snooze(item)
        await workspace.waitForReminders()
        #expect(notifier.requests[0].schedule == .once(date(7, minute: 15)))
    }

    @Test func routineTimerSurvivesRestartPausesAndLogsOnlyWhenAsked() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ProductivityStore(fileURL: folder.appendingPathComponent("productivity.json"))
        let clock = TestClock(now: date(7))
        let workspace = ProductivityService(store: store, notifier: FakeProductivityNotifications(), calendar: calendar, clock: { clock.now })
        let routine = ProductivityItem(kind: .exercise, title: "Coding practice", createdAt: date(7), routineStart: date(7), durationMinutes: 5)
        #expect(workspace.save(routine))
        workspace.startSession(routine)
        clock.now = date(7, minute: 1); workspace.tick()
        workspace.toggleSessionPause()
        #expect(workspace.snapshot.session?.pausedSeconds == 240)
        clock.now = date(7, minute: 10); workspace.tick()
        #expect(workspace.snapshot.session?.remaining(at: clock.now) == 240)
        workspace.toggleSessionPause()
        let restored = service(at: clock.now, store: store)
        #expect(restored.snapshot.session?.endsAt == date(7, minute: 14))
        clock.now = date(7, minute: 15); workspace.tick()
        #expect(workspace.snapshot.session?.remaining(at: clock.now) == 0)
        #expect(workspace.snapshot.items[0].exerciseCompletions.isEmpty)
        workspace.finishSession()
        #expect(workspace.snapshot.session == nil)
        #expect(workspace.snapshot.items[0].exerciseCompletions == [clock.now])
    }

    @Test func timerActionsUseCurrentClockInsteadOfLastDisplayTick() {
        let clock = TestClock(now: date(7))
        let workspace = ProductivityService(store: ProductivityStore(fileURL: nil), notifier: FakeProductivityNotifications(), calendar: calendar, clock: { clock.now })
        let routine = ProductivityItem(kind: .exercise, title: "Break", createdAt: date(7), routineStart: date(7), durationMinutes: 5)
        #expect(workspace.save(routine))
        clock.now = date(7).addingTimeInterval(24)
        workspace.startSession(routine)
        #expect(workspace.snapshot.session?.remaining(at: clock.now) == 300)
        clock.now = date(7).addingTimeInterval(34)
        workspace.toggleSessionPause()
        #expect(workspace.snapshot.session?.pausedSeconds == 290)
    }

    @Test func newCapturesNavigateToWhereTheyCanBeFound() {
        let workspace = service(at: date(7))
        #expect(workspace.quickCapture("An idea", kind: .note))
        #expect(workspace.selectedSection == .notes)
        #expect(workspace.visibleItems.count == 1)
        #expect(workspace.quickCapture("Practice", kind: .exercise))
        #expect(workspace.selectedSection == .exercises)
        #expect(workspace.visibleItems.count == 1)
        workspace.selectedSection = .completed
        #expect(workspace.quickCapture("Follow up", kind: .task))
        #expect(workspace.selectedSection == .pending)
        #expect(workspace.visibleItems.count == 1)
    }

    @Test func reminderUpdatesAreSerializedAndDisabledRemindersAreRemoved() async {
        let notifier = FakeProductivityNotifications()
        let workspace = service(at: date(7), notifier: notifier)
        await workspace.setNotificationsEnabled(true)
        var item = ProductivityItem(kind: .task, title: "First", dueAt: date(7, hour: 10), reminderEnabled: true)
        #expect(workspace.save(item))
        item.title = "Final"
        #expect(workspace.save(item))
        await workspace.waitForReminders()
        #expect(notifier.requests.map(\.title) == ["Final"])
        await workspace.setNotificationsEnabled(false)
        #expect(notifier.requests.isEmpty)
    }

    @Test func reminderLimitIsExplicitAndDoesNotLoseSavedData() throws {
        var snapshot = ProductivitySnapshot()
        snapshot.preferences.notificationsEnabled = true
        snapshot.items = (0..<13).map { ProductivityItem(kind: .exercise, title: "Routine \($0)", dueAt: date(7), reminderEnabled: true) }
        #expect(throws: ProductivityError.self) {
            try ProductivityReminderPlanner.reminders(for: snapshot, now: date(7), calendar: calendar)
        }
    }

    @Test func exportedWorkspaceContainsNotesAndDailyReflections() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let workspace = service(at: date(7))
        #expect(workspace.quickCapture("Decision\nKeep the parser local", kind: .note))
        #expect(workspace.saveDailyNote(DailyFocusNote(id: workspace.dayID, date: date(7), intention: "Ship a small improvement", reflection: "Continue tomorrow")))
        let url = folder.appendingPathComponent("notes.md")
        workspace.exportMarkdown(to: url)
        let exported = try String(contentsOf: url, encoding: .utf8)
        #expect(exported.contains("Keep the parser local"))
        #expect(exported.contains("Ship a small improvement"))
        #expect(exported.contains("Continue tomorrow"))
    }

    @Test func productivityNavigationIsAvailableWithoutConnectedAccounts() {
        #expect(DashboardSection.today.shortcutLabel == "⌘⇧T")
        #expect(TidyGoal.dailyWork.dashboardSections.contains(.today))
        #expect(DeveloperWorkflowRegistry.all.first { $0.id == .startDay }?.requiredSections == [.today])
        #expect(DeveloperWorkflowRegistry.all.first { $0.id == .wrapUp }?.requiredSections == [.today])
    }
}

@MainActor
private final class TestClock {
    var now: Date
    init(now: Date) { self.now = now }
}

@MainActor
private final class FakeProductivityNotifications: ProductivityNotifying {
    var onOpenItem: ((UUID?) -> Void)?
    var allowPermission = true
    var permissionRequests = 0
    var requests: [ProductivityReminder] = []
    func requestAuthorization() async throws -> Bool { permissionRequests += 1; return allowPermission }
    func replaceReminders(with reminders: [ProductivityReminder]) async throws {
        await Task.yield()
        requests = reminders
    }
}
