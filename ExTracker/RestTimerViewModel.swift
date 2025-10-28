import Foundation
import UserNotifications
import Combine

#if canImport(UIKit)
import UIKit
#endif

final class RestTimerViewModel: ObservableObject {
    @Published var isResting: Bool = false
    @Published var isPaused: Bool = false
    @Published var remainingSeconds: Int = 0
    @Published var totalSeconds: Int = 0

    private var restTimer: Timer? = nil
    private var restEndDate: Date? = nil

    func start(totalSeconds: Int) {
        guard totalSeconds > 0 else { return }
        self.totalSeconds = totalSeconds
        self.restEndDate = Date().addingTimeInterval(TimeInterval(totalSeconds))
        self.remainingSeconds = totalSeconds
        self.isResting = true
        self.isPaused = false

        scheduleRestCompletionNotification(at: self.restEndDate!)

        restTimer?.invalidate()
        restTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            guard !self.isPaused else { return }
            let remaining = max(0, Int((self.restEndDate ?? Date()).timeIntervalSinceNow.rounded()))
            if self.remainingSeconds != remaining { self.remainingSeconds = remaining }
            if remaining <= 0 {
                timer.invalidate()
                self.isResting = false
                self.restEndDate = nil
                self.playCompletionFeedback()
            }
        }
    }

    func togglePause() {
        guard isResting else { return }
        isPaused.toggle()
        if !isPaused, remainingSeconds > 0 {
            restEndDate = Date().addingTimeInterval(TimeInterval(remainingSeconds))
            if let end = restEndDate { scheduleRestCompletionNotification(at: end) }
        }
    }

    func cancel() {
        restTimer?.invalidate()
        isResting = false
        isPaused = false
        remainingSeconds = 0
        totalSeconds = 0
        restEndDate = nil
        cancelRestCompletionNotification()
    }

    func stopTimerOnDisappear() {
        restTimer?.invalidate()
    }

    private func playCompletionFeedback() {
        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif
    }

    private func scheduleRestCompletionNotification(at date: Date) {
        let center = UNUserNotificationCenter.current()
        cancelRestCompletionNotification()

        let content = UNMutableNotificationContent()
        content.title = "Rest complete"
        content.body = "Time to start your next set."
        content.sound = .default
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }

        let triggerDate = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerDate, repeats: false)

        let request = UNNotificationRequest(identifier: "exercise.rest.complete", content: content, trigger: trigger)
        center.add(request) { error in
            if let error = error {
                print("Failed to schedule rest notification: \(error)")
            }
        }
    }

    private func cancelRestCompletionNotification() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["exercise.rest.complete"])
    }
}
