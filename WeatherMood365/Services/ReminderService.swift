import Foundation
import UserNotifications

@MainActor
final class ReminderService {
    static let shared = ReminderService()

    static let enabledKey = "dailyReminderEnabled"
    static let hourKey = "dailyReminderHour"
    static let minuteKey = "dailyReminderMinute"

    private let notificationIdentifier = "daily-record-reminder"
    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard
    private let calendar = Calendar.current

    private init() {}

    var isEnabled: Bool {
        defaults.bool(forKey: Self.enabledKey)
    }

    var reminderHour: Int {
        defaults.object(forKey: Self.hourKey) as? Int ?? 10
    }

    var reminderMinute: Int {
        defaults.object(forKey: Self.minuteKey) as? Int ?? 30
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func enableReminder(with store: EntryStore) async throws -> Bool {
        let granted = try await requestAuthorization()
        defaults.set(granted, forKey: Self.enabledKey)

        if granted {
            await syncReminder(with: store)
        } else {
            cancelReminder()
        }

        return granted
    }

    func disableReminder() {
        defaults.set(false, forKey: Self.enabledKey)
        cancelReminder()
    }

    func syncReminder(with store: EntryStore) async {
        guard isEnabled else {
            cancelReminder()
            return
        }

        let status = await authorizationStatus()
        guard status == .authorized || status == .provisional || status == .ephemeral else {
            cancelReminder()
            return
        }

        scheduleNextReminder(with: store)
    }

    func nextPendingReminderDate() async -> Date? {
        let requests = await center.pendingNotificationRequests()
        return requests
            .filter { $0.identifier == notificationIdentifier }
            .compactMap { ($0.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() }
            .min()
    }

    private func scheduleNextReminder(with store: EntryStore) {
        cancelReminder()

        let nextDate = nextReminderDate(with: store)
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: nextDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let content = UNMutableNotificationContent()
        content.title = "今天还没有记录"
        content.body = "拍一张照片，留下今天的天气、心情和一句话。"
        content.sound = .default

        let request = UNNotificationRequest(identifier: notificationIdentifier, content: content, trigger: trigger)
        center.add(request)
    }

    private func cancelReminder() {
        center.removePendingNotificationRequests(withIdentifiers: [notificationIdentifier])
    }

    private func nextReminderDate(with store: EntryStore) -> Date {
        let now = Date()
        let todayReminder = reminderDate(on: now)
        let todayHasEntry = store.entry(for: now) != nil

        if !todayHasEntry, now < todayReminder {
            return todayReminder
        }

        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        return reminderDate(on: tomorrow)
    }

    private func reminderDate(on date: Date) -> Date {
        let day = calendar.startOfDay(for: date)
        return calendar.date(
            bySettingHour: reminderHour,
            minute: reminderMinute,
            second: 0,
            of: day
        ) ?? date
    }
}
