import Foundation
import AlarmKit
import Combine
import SwiftUI

private struct EmptyAlarmMetadata: AlarmMetadata {}

public enum AppAlarmAuthorizationStatus {
    case notDetermined
    case authorized
    case denied
}

public struct AppCountdownRequest {
    public let seconds: Int
    public let title: String
    public let message: String

    public init(seconds: Int, title: String, message: String) {
        self.seconds = seconds
        self.title = title
        self.message = message
    }
}

@MainActor
public final class ExAlarmManager: ObservableObject {
    public static let shared = ExAlarmManager()
    public var activeAlarm:Alarm?

    @Published public private(set) var authorizationStatus: AppAlarmAuthorizationStatus = .notDetermined
    @Published public private(set) var isAlerting: Bool = false
    
    // A task to hold our observation loop
    private var alarmObservationTask: Task<Void, Never>?
    
    private init() {
        // Start observing alarm updates when the ViewModel is initialized
        self.alarmObservationTask = Task {
            await observeAlarms()
        }
    }

    public func requestAuthorizationIfNeeded() async -> AppAlarmAuthorizationStatus {
        do {
            let status = try await AlarmKit.AlarmManager.shared.requestAuthorization()
            let mapped: AppAlarmAuthorizationStatus
            switch status {
            case .authorized: mapped = .authorized
            case .denied: mapped = .denied
            case .notDetermined: mapped = .notDetermined
            @unknown default: mapped = .denied
            }
            self.authorizationStatus = mapped
            return mapped
        } catch {
            self.authorizationStatus = .denied
            return .denied
        }
    }

    public func currentAuthorizationStatus() -> AppAlarmAuthorizationStatus {
        return authorizationStatus
    }

    public func cancelActiveCountdown() {
        isAlerting = false
        guard let alarm = activeAlarm else { return }
        try? AlarmKit.AlarmManager.shared.cancel(id: alarm.id)
        activeAlarm = nil
    }
    
    public func togglePauseActiveAlarm(on:Bool) {
        guard let alarm = activeAlarm else { return }
        if on {
            try? AlarmKit.AlarmManager.shared.pause(id: alarm.id)
        } else {
            try? AlarmKit.AlarmManager.shared.resume(id: alarm.id)
        }
    }

    public func scheduleCountdown(_ request: AppCountdownRequest) async throws {
        // Cancel any existing countdown before scheduling a new one
        cancelActiveCountdown()
        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: request.title),
            stopButton: AlarmButton(
                text: "Stop",
                textColor: .white,
                systemImageName: "stop.fill"
            )
        )
        
        let attributes = AlarmAttributes<EmptyAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            tintColor: .white
        )
        
        // Schedule the alarm with concrete metadata attributes
        let duration = TimeInterval(request.seconds)
        activeAlarm = try await AlarmManager.shared.schedule(id: UUID(), configuration: .timer(duration: duration, attributes: attributes))
    
    }
    
    private func observeAlarms() async {
        for await updatedAlarms in AlarmManager.shared.alarmUpdates {
            await MainActor.run {
                isAlerting = false
                updatedAlarms.forEach { alarm in
                    if alarm.state == Alarm.State.alerting {
                        isAlerting = true
                    }
                }
           }
        }
    }
    
    deinit {
        alarmObservationTask?.cancel()
    }
}

