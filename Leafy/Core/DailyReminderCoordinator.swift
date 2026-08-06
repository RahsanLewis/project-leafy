import Foundation
import Observation
import UIKit
@preconcurrency import UserNotifications

extension Notification.Name {
    static let leafyOpenMorningCheckIn = Notification.Name("leafy.openMorningCheckIn")
}

struct DailyReminderPreferences: Equatable, Sendable {
    static let defaultHour = 8
    static let defaultMinute = 0

    var isEnabled: Bool
    var hour: Int
    var minute: Int

    var dateComponents: DateComponents {
        DateComponents(hour: hour, minute: minute)
    }

    var displayDate: Date {
        Calendar.current.date(from: dateComponents) ?? .now
    }
}

enum ReminderAuthorizationState: Equatable, Sendable {
    case unknown
    case authorized
    case denied

    var description: String {
        switch self {
        case .unknown: "Permission not requested"
        case .authorized: "Notifications allowed"
        case .denied: "Notifications disabled in iOS Settings"
        }
    }
}

@MainActor @Observable
final class DailyReminderCoordinator {
    nonisolated static let requestIdentifier = "leafy.dailyMorningCheckIn"

    private enum Key {
        static let enabled = "leafy.reminder.enabled"
        static let hour = "leafy.reminder.hour"
        static let minute = "leafy.reminder.minute"
        static let pendingOpen = "leafy.reminder.pendingOpen"
    }

    private let center: UNUserNotificationCenter
    private let defaults: UserDefaults

    var preferences: DailyReminderPreferences
    var authorizationState: ReminderAuthorizationState = .unknown
    var errorMessage: String?

    init(center: UNUserNotificationCenter = .current(), defaults: UserDefaults = .standard) {
        self.center = center
        self.defaults = defaults
        let storedHour = defaults.object(forKey: Key.hour) as? Int
        let storedMinute = defaults.object(forKey: Key.minute) as? Int
        preferences = DailyReminderPreferences(
            isEnabled: defaults.bool(forKey: Key.enabled),
            hour: storedHour ?? DailyReminderPreferences.defaultHour,
            minute: storedMinute ?? DailyReminderPreferences.defaultMinute
        )
    }

    func refresh() async {
        let settings = await center.notificationSettings()
        authorizationState = Self.authorizationState(for: settings.authorizationStatus)

        if authorizationState == .denied, preferences.isEnabled {
            preferences.isEnabled = false
            persist()
            center.removePendingNotificationRequests(withIdentifiers: [Self.requestIdentifier])
        } else if authorizationState == .authorized, preferences.isEnabled {
            await schedule()
        }
    }

    func setEnabled(_ enabled: Bool) async {
        errorMessage = nil
        if !enabled {
            preferences.isEnabled = false
            persist()
            center.removePendingNotificationRequests(withIdentifiers: [Self.requestIdentifier])
            return
        }

        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            authorizationState = granted ? .authorized : .denied
            preferences.isEnabled = granted
            persist()
            if granted { await schedule() }
        } catch {
            preferences.isEnabled = false
            persist()
            errorMessage = "Leafy couldn’t enable the reminder. Try again from iOS Settings."
        }
    }

    func setTime(_ date: Date) async {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        preferences.hour = components.hour ?? DailyReminderPreferences.defaultHour
        preferences.minute = components.minute ?? DailyReminderPreferences.defaultMinute
        persist()
        if preferences.isEnabled { await schedule() }
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func consumePendingMorningCheckIn() -> Bool {
        guard defaults.bool(forKey: Key.pendingOpen) else { return false }
        defaults.set(false, forKey: Key.pendingOpen)
        return true
    }

    private func schedule() async {
        let content = UNMutableNotificationContent()
        content.title = "Your Leafy check-in"
        content.body = "Open Leafy to review yesterday and start today."
        content.sound = .default
        content.userInfo = ["destination": "morning-check-in"]

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: preferences.dateComponents,
            repeats: true
        )
        let request = UNNotificationRequest(
            identifier: Self.requestIdentifier,
            content: content,
            trigger: trigger
        )

        do {
            center.removePendingNotificationRequests(withIdentifiers: [Self.requestIdentifier])
            try await center.add(request)
        } catch {
            errorMessage = "Leafy couldn’t schedule the reminder. Try again in a moment."
        }
    }

    private func persist() {
        defaults.set(preferences.isEnabled, forKey: Key.enabled)
        defaults.set(preferences.hour, forKey: Key.hour)
        defaults.set(preferences.minute, forKey: Key.minute)
    }

    private static func authorizationState(for status: UNAuthorizationStatus) -> ReminderAuthorizationState {
        switch status {
        case .authorized, .provisional, .ephemeral: .authorized
        case .denied: .denied
        case .notDetermined: .unknown
        @unknown default: .unknown
        }
    }
}

final class LeafyAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.notification.request.identifier == DailyReminderCoordinator.requestIdentifier else { return }
        UserDefaults.standard.set(true, forKey: "leafy.reminder.pendingOpen")
        NotificationCenter.default.post(name: .leafyOpenMorningCheckIn, object: nil)
    }
}
