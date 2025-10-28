import Foundation
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

final class AlarmService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = AlarmService()
    /// Call once (e.g., at app launch or first use) to ensure foreground notifications present with banner/sound.
    func configureForegroundPresentation() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
    }

    /// Requests notification authorization if not already granted.
    private func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return
        case .denied:
            return
        case .notDetermined:
            do {
                _ = try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                // Ignore errors; scheduling will simply fail silently without permission.
            }
        @unknown default:
            return
        }
    }

    /// Schedule a local notification to fire at the specified date.
    /// - Parameter date: The date when the alarm should fire.
    /// - Returns: A string identifier for the scheduled alarm (or nil if scheduling failed).
    @discardableResult
    func scheduleRestAlarm(at date: Date) async -> String? {
        await requestAuthorizationIfNeeded()
        let center = UNUserNotificationCenter.current()

        let content = UNMutableNotificationContent()
        content.title = "Rest complete"
        content.body = "Your rest timer has finished."
        content.sound = .default

        // Use a unique identifier so we can cancel later.
        let identifier = "rest.alarm." + UUID().uuidString

        // Build a time-based trigger for the exact date.
        let timeInterval = max(0.1, date.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: false)

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        do {
            try await center.add(request)
            return identifier
        } catch {
            return nil
        }
    }

    /// Cancel a previously scheduled rest alarm by identifier.
    func cancelRestAlarm(id: String?) async {
        guard let id else { return }
        let center = UNUserNotificationCenter.current()
        await center.removePendingNotificationRequests(withIdentifiers: [id])
    }

    // MARK: - UNUserNotificationCenterDelegate
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Present banner and play sound even when app is in the foreground
        completionHandler([.banner, .list, .sound])
    }
}
