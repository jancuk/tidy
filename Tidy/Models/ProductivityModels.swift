import Foundation

enum ProductivityKind: String, CaseIterable, Codable, Identifiable {
    case task, note, exercise
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .task: "checklist"
        case .note: "note.text"
        case .exercise: "figure.mind.and.body"
        }
    }
}

enum ProductivityPriority: Int, CaseIterable, Codable, Identifiable {
    case low, normal, high
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .low: "Low"
        case .normal: "Normal"
        case .high: "High"
        }
    }
}

enum RoutineCadence: String, CaseIterable, Codable, Identifiable {
    case once = "Once"
    case daily = "Every day"
    case weekdays = "Weekdays"
    case weekly = "Every week"
    var id: String { rawValue }
}

struct ProductivityItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var kind: ProductivityKind = .task
    var title = ""
    var body = ""
    var tags: [String] = []
    var priority: ProductivityPriority = .normal
    var createdAt = Date()
    var updatedAt = Date()
    var plannedDay: Date?
    var dueAt: Date?
    var reminderEnabled = false
    var pinned = false
    var completedAt: Date?
    var archivedAt: Date?
    var cadence: RoutineCadence = .weekdays
    var routineStart = Date()
    var routineWeekday = 2
    var durationMinutes = 15
    var exerciseCompletions: [Date] = []
    var source: CaptureSource?

    var isRecurring: Bool { kind == .exercise && cadence != .once }

    func isComplete(at now: Date, calendar: Calendar) -> Bool {
        if isRecurring { return exerciseCompletions.contains { calendar.isDate($0, inSameDayAs: now) } }
        return completedAt != nil
    }

    func isScheduled(on date: Date, calendar: Calendar) -> Bool {
        guard kind == .exercise, calendar.startOfDay(for: date) >= calendar.startOfDay(for: routineStart) else { return false }
        switch cadence {
        case .once: return calendar.isDate(date, inSameDayAs: routineStart)
        case .daily: return true
        case .weekdays: return (2...6).contains(calendar.component(.weekday, from: date))
        case .weekly: return calendar.component(.weekday, from: date) == routineWeekday
        }
    }

    func isOverdue(at now: Date) -> Bool {
        kind == .task && completedAt == nil && archivedAt == nil && (dueAt.map { $0 < now } ?? false)
    }

    func isInToday(at now: Date, calendar: Calendar) -> Bool {
        guard archivedAt == nil else { return false }
        if kind == .exercise {
            return isScheduled(on: now, calendar: calendar)
                || (cadence == .once && completedAt == nil && routineStart < now)
        }
        if kind == .note {
            return pinned || (plannedDay.map { calendar.isDate($0, inSameDayAs: now) } ?? false)
        }
        guard completedAt == nil else { return false }
        return isOverdue(at: now)
            || (plannedDay.map { calendar.startOfDay(for: $0) <= calendar.startOfDay(for: now) } ?? false)
            || (dueAt.map { calendar.isDate($0, inSameDayAs: now) } ?? false)
    }
}

struct DailyFocusNote: Identifiable, Codable, Equatable {
    var id: String
    var date: Date
    var intention = ""
    var reflection = ""
}

struct ExerciseSession: Codable, Equatable {
    var itemID: UUID
    var title: String
    var endsAt: Date
    var pausedSeconds: TimeInterval?

    func remaining(at date: Date) -> TimeInterval { max(0, pausedSeconds ?? endsAt.timeIntervalSince(date)) }
}

struct ProductivityPreferences: Codable, Equatable {
    var notificationsEnabled = false
    var morningReviewEnabled = false
    var morningHour = 9
    var morningMinute = 0
}

struct ProductivitySnapshot: Codable, Equatable {
    var version = 1
    var items: [ProductivityItem] = []
    var dailyNotes: [DailyFocusNote] = []
    var preferences = ProductivityPreferences()
    var session: ExerciseSession?
    var syncJournal: [ProductivitySyncRevision]?
}

enum ProductivitySection: String, CaseIterable, Identifiable {
    case today = "Today"
    case pending = "Pending"
    case notes = "Notes"
    case exercises = "Exercises"
    case reminders = "Reminders"
    case completed = "Completed"
    case archive = "Archive"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .today: "sun.max"
        case .pending: "tray"
        case .notes: "note.text"
        case .exercises: "figure.mind.and.body"
        case .reminders: "bell"
        case .completed: "checkmark.circle"
        case .archive: "archivebox"
        }
    }
    var emptyTitle: String {
        switch self {
        case .today: "Make room for what matters"
        case .pending: "Nothing waiting on you"
        case .notes: "Keep the context you need"
        case .exercises: "Build a routine that fits your day"
        case .reminders: "Remember it at the right time"
        case .completed: "Your progress will appear here"
        case .archive: "Archived items stay recoverable"
        }
    }
    var emptyDetail: String {
        switch self {
        case .today: "Add a task to today, write your focus, or start a routine. Unfinished planned tasks carry forward."
        case .pending: "Capture follow-ups, small fixes, and anything you want to return to."
        case .notes: "Save meeting notes, code snippets, ideas, and links. Pin useful notes to Today."
        case .exercises: "Create coding practice, movement breaks, or your own exercise with an optional timer."
        case .reminders: "Give an item a due date or enable a local reminder. No external accounts are needed."
        case .completed: "Complete tasks and log exercises to see what you have done."
        case .archive: "Archive items you no longer need, then restore them here at any time."
        }
    }
}

enum ProductivityError: LocalizedError {
    case invalid(String)
    case unsupportedVersion
    case storageUnavailable
    case notificationLimit

    var errorDescription: String? {
        switch self {
        case .invalid(let message): message
        case .unsupportedVersion: "This workspace was saved by a newer version of Tidy. Update Tidy before editing it."
        case .storageUnavailable: "Your productivity file could not be loaded. Retry loading it before making changes; the original file has been preserved."
        case .notificationLimit: "There are more than 64 scheduled alerts. Reduce active reminders or weekday routines before enabling notifications. Dates remain visible in Tidy."
        }
    }
}
