import Foundation
import Combine
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

final class RestTimerManager: ObservableObject {
    static let shared = RestTimerManager()

    @Published private(set) var isResting: Bool = false
    @Published private(set) var isPaused: Bool = false
    @Published private(set) var remainingSeconds: Int = 0
    @Published private(set) var totalSeconds: Int = 0
    @Published private(set) var restEndDate: Date? = nil

    private var timer: Timer?
    private let alarmManager = ExAlarmManager.shared

    private init() {
    }

    func startRest(totalSeconds: Int) {
        guard totalSeconds > 0 else { return }
        self.totalSeconds = totalSeconds
        self.restEndDate = Date().addingTimeInterval(TimeInterval(totalSeconds))
        self.remainingSeconds = totalSeconds
        self.isResting = true
        self.isPaused = false
        startUITimer()
        Task { await scheduleAlarmOrNotification(totalSeconds: totalSeconds) }
    }

    func pause() {
        guard isResting, !isPaused else { return }
        isPaused = true
        alarmManager.togglePauseActiveAlarm(on: true)
    }

    func resume() {
        guard isResting, isPaused else { return }
        isPaused = false
        if let remaining = remainingSeconds as Int?, remaining > 0 {
            restEndDate = Date().addingTimeInterval(TimeInterval(remaining))
        }
        alarmManager.togglePauseActiveAlarm(on: false)
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        isResting = false
        isPaused = false
        remainingSeconds = 0
        totalSeconds = 0
        restEndDate = nil
        alarmManager.cancelActiveCountdown()
    }

    // MARK: - Private

    private func startUITimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] t in
            guard let self = self else { return }
            guard self.isResting else { t.invalidate(); return }
            if self.isPaused {
                return
            }
            let remaining = max(0, Int((self.restEndDate ?? Date()).timeIntervalSinceNow.rounded()))
            self.remainingSeconds = remaining
            if remaining <= 0 {
                t.invalidate()
                self.isResting = false
                self.restEndDate = nil
                self.playCompletionFeedback()
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func scheduleAlarmOrNotification(totalSeconds: Int) async {
        let status = await alarmManager.requestAuthorizationIfNeeded()
        if status == .denied {
            scheduleNotification()
        } else {
            let req = AppCountdownRequest(seconds: totalSeconds, title: "Rest Complete", message: "")
            do {
                try await alarmManager.scheduleCountdown(req)
            } catch {
                scheduleNotification()
            }
        }
    }

    private func scheduleNotification() {
        guard let end = restEndDate else { return }
        let center = UNUserNotificationCenter.current()
        // remove existing
        center.removePendingNotificationRequests(withIdentifiers: ["exercise.rest.complete"])
        let content = UNMutableNotificationContent()
        content.title = "Rest complete"
        content.body = "Time to start your next set."
        content.sound = .default
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }
        let comps = Calendar.current.dateComponents([.year,.month,.day,.hour,.minute,.second], from: end)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: "exercise.rest.complete", content: content, trigger: trigger)
        center.add(request, withCompletionHandler: nil)
    }

    private func playCompletionFeedback() {
        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif
    }
}
