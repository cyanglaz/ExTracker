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
public final class ExAlarmManager {
    public static let shared = ExAlarmManager()
    private var activeAlarm:Alarm?
    private init() {}

    @Published public private(set) var authorizationStatus: AppAlarmAuthorizationStatus = .notDetermined

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

    public func cancelActiveCountdown() async {
        guard let alarm = activeAlarm else { return }
        try? AlarmKit.AlarmManager.shared.cancel(id: alarm.id)
    }

    public func scheduleCountdown(_ request: AppCountdownRequest, onFire: @escaping () -> Void) async throws {
        // Cancel any existing countdown before scheduling a new one
        await cancelActiveCountdown()
        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: request.title),
            stopButton: AlarmButton(
                text: "Stop",
                textColor: .black,
                systemImageName: "stop.fill"
            )
        )
        
        let attributes = AlarmAttributes<EmptyAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            tintColor: .black
        )
        
        // Schedule the alarm with concrete metadata attributes
        let duration = TimeInterval(request.seconds)
        activeAlarm = try await AlarmManager.shared.schedule(id: UUID(), configuration: .timer(duration: duration, attributes: attributes))
        onFire()
    }
}
