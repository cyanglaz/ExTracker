import Foundation
import SwiftUI

// Wrap AlarmKit usage so the app still compiles on older SDKs or platforms
#if canImport(AlarmKit)
import AlarmKit
#endif

@MainActor
final class AlarmKitService {
    static let shared = AlarmKitService()
    private init() {}

    // MARK: - Capability
    var isAvailable: Bool {
        #if canImport(AlarmKit)
        if #available(iOS 18.0, *) {
            return true
        }
        #endif
        return false
    }

    // MARK: - Authorization
    func requestAuthorizationIfNeeded() async -> Bool {
        #if canImport(AlarmKit)
        if #available(iOS 18.0, *) {
            do {
                let state = try await AlarmManager.shared.requestAuthorization()
                return state == .authorized
            } catch {
                return false
            }
        }
        #endif
        return false
    }

    // MARK: - Scheduling
    @discardableResult
    func scheduleRestAlarm(seconds: TimeInterval, title: String) async throws -> UUID {
        #if canImport(AlarmKit)
        if #available(iOS 18.0, *) {
            // Build the presentation
            let alert = AlarmPresentation.Alert(
                title: LocalizedStringResource(stringLiteral: title),
                stopButton: AlarmButton(text: LocalizedStringResource(stringLiteral: "Stop"), textColor: Color.white, systemImageName: "stop.fill"),
                secondaryButton: nil,
                secondaryButtonBehavior: nil
            )
            let countdown = AlarmPresentation.Countdown(
                title: "Resting",
                pauseButton: AlarmButton(text: LocalizedStringResource(stringLiteral: "Pause"), textColor: Color.white, systemImageName: "pause.fill"),
            )
            let paused = AlarmPresentation.Paused(
                title: "Paused",
                resumeButton: AlarmButton(text: LocalizedStringResource(stringLiteral: "Resume"), textColor: Color.white, systemImageName: "arrow.trianglehead.clockwise"),
            )
            let presentation = AlarmPresentation(alert: alert, countdown: countdown, paused: paused)

            struct EmptyMetadata: AlarmMetadata {}
            let attributes = AlarmAttributes(
                presentation: presentation,
                metadata: EmptyMetadata(),
                tintColor: .orange
            )

            let countdownDuration = Alarm.CountdownDuration(
                preAlert: max(0, seconds),
                postAlert: 9 * 60
            )

            let configuration = AlarmManager.AlarmConfiguration(
                countdownDuration: countdownDuration,
                schedule: nil,
                attributes: attributes,
            )

            let id = UUID()
            _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
            return id
        }
        #endif
        throw NSError(domain: "AlarmKitService", code: -1, userInfo: [NSLocalizedDescriptionKey: "AlarmKit not available"])
    }

    // MARK: - Control
    func pause(id: UUID) async throws {
        #if canImport(AlarmKit)
        if #available(iOS 18.0, *) {
            try await AlarmManager.shared.pause(id: id)
            return
        }
        #endif
        throw NSError(domain: "AlarmKitService", code: -2, userInfo: [NSLocalizedDescriptionKey: "AlarmKit not available"])
    }

    func resume(id: UUID) async throws {
        #if canImport(AlarmKit)
        if #available(iOS 18.0, *) {
            try await AlarmManager.shared.resume(id: id)
            return
        }
        #endif
        throw NSError(domain: "AlarmKitService", code: -3, userInfo: [NSLocalizedDescriptionKey: "AlarmKit not available"])
    }

    func cancel(id: UUID) async throws {
        #if canImport(AlarmKit)
        if #available(iOS 18.0, *) {
            try await AlarmManager.shared.cancel(id: id)
            return
        }
        #endif
        throw NSError(domain: "AlarmKitService", code: -4, userInfo: [NSLocalizedDescriptionKey: "AlarmKit not available"])
    }
}
