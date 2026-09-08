import Foundation
import UserNotifications

struct ProductivityReminder: Equatable {
    enum Schedule: Equatable {
        case once(Date)
        case daily(hour: Int, minute: Int)
        case weekly(weekday: Int, hour: Int, minute: Int)
    }
    static let prefix = "tidy.productivity."
    var id: String
    var itemID: UUID?
    var title: String
    var body: String
    var schedule: Schedule
}

enum ProductivityReminderPlanner {
    static func reminders(for snapshot: ProductivitySnapshot, now: Date, calendar: Calendar) throws -> [ProductivityReminder] {
        guard snapshot.preferences.notificationsEnabled else { return [] }
        var reminders: [ProductivityReminder] = []
        for item in snapshot.items where item.archivedAt == nil && item.reminderEnabled {
            guard let date = item.dueAt else { continue }
            let id = ProductivityReminder.prefix + item.id.uuidString
            let body = item.kind == .exercise ? "Time for your routine. Open Today to start or log it." : "Open Today to review this item."
            let base = ProductivityReminder(id: id, itemID: item.id, title: item.title, body: body, schedule: .once(date))
            if item.isRecurring {
                let hour = calendar.component(.hour, from: date)
                let minute = calendar.component(.minute, from: date)
                switch item.cadence {
                case .daily:
                    var reminder = base
                    reminder.schedule = .daily(hour: hour, minute: minute)
                    reminders.append(reminder)
                case .weekdays, .weekly:
                    let days = item.cadence == .weekdays ? Array(2...6) : [item.routineWeekday]
                    for weekday in days {
                        var reminder = base
                        reminder.id += ".\(weekday)"
                        reminder.schedule = .weekly(weekday: weekday, hour: hour, minute: minute)
                        reminders.append(reminder)
                    }
                case .once: break
                }
            } else if item.completedAt == nil && date > now {
                reminders.append(base)
            }
        }
        if snapshot.preferences.morningReviewEnabled {
            reminders.append(ProductivityReminder(
                id: ProductivityReminder.prefix + "morning", title: "Plan your day with Tidy",
                body: "Review pending items, choose today's focus, and make time for your routines.",
                schedule: .daily(hour: snapshot.preferences.morningHour, minute: snapshot.preferences.morningMinute)
            ))
        }
        if let session = snapshot.session, session.pausedSeconds == nil, session.endsAt > now {
            reminders.append(ProductivityReminder(
                id: ProductivityReminder.prefix + "session", itemID: session.itemID,
                title: "Your session is finished", body: "\(session.title). Open Tidy to log your progress.", schedule: .once(session.endsAt)
            ))
        }
        guard reminders.count <= 64 else { throw ProductivityError.notificationLimit }
        return reminders
    }
}

@MainActor
protocol ProductivityNotifying: AnyObject {
    var onOpenItem: ((UUID?) -> Void)? { get set }
    func requestAuthorization() async throws -> Bool
    func replaceReminders(with reminders: [ProductivityReminder]) async throws
}

@MainActor
final class LocalProductivityNotifications: NSObject, ProductivityNotifying, UNUserNotificationCenterDelegate {
    var onOpenItem: ((UUID?) -> Void)?
    private let center: UNUserNotificationCenter

    override init() {
        center = .current()
        super.init()
        center.delegate = self
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func replaceReminders(with reminders: [ProductivityReminder]) async throws {
        if !reminders.isEmpty {
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                throw ProductivityError.invalid("macOS notifications are disabled for Tidy. Enable them in System Settings → Notifications; your items and dates remain saved.")
            }
        }
        let desired = Set(reminders.map(\.id))
        let pending = await center.pendingNotificationRequests()
        let obsolete = pending.map(\.identifier).filter { $0.hasPrefix(ProductivityReminder.prefix) && !desired.contains($0) }
        center.removePendingNotificationRequests(withIdentifiers: obsolete)
        for reminder in reminders {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            if let id = reminder.itemID { content.userInfo = ["productivityItemID": id.uuidString] }
            var components = DateComponents()
            let repeats: Bool
            switch reminder.schedule {
            case .once(let date):
                components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
                repeats = false
            case .daily(let hour, let minute):
                components.hour = hour; components.minute = minute
                repeats = true
            case .weekly(let weekday, let hour, let minute):
                components.weekday = weekday; components.hour = hour; components.minute = minute
                repeats = true
            }
            let request = UNNotificationRequest(identifier: reminder.id, content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: repeats))
            try await center.add(request)
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let id = (response.notification.request.content.userInfo["productivityItemID"] as? String).flatMap(UUID.init(uuidString:))
        await MainActor.run { onOpenItem?(id) }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}

@MainActor
final class SilentProductivityNotifications: ProductivityNotifying {
    var onOpenItem: ((UUID?) -> Void)?
    func requestAuthorization() async throws -> Bool { false }
    func replaceReminders(with reminders: [ProductivityReminder]) async throws {}
}
