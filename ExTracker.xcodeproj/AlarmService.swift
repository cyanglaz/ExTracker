import Foundation

/// A thin wrapper around AlarmKit to schedule and cancel one-shot alarms.
/// This helper isolates framework usage and gracefully no-ops when AlarmKit
/// is not available, so the app still builds on platforms/targets without it.
final class AlarmService {
    static let shared = AlarmService()
    private init() {}

    /// Schedule a one-time alarm at the given date.
    /// - Parameter date: The time when the alarm should fire.
    /// - Returns: The alarm identifier if scheduled, otherwise nil.
    func scheduleRestAlarm(at date: Date) async -> String? {
        #if canImport(AlarmKit)
        import AlarmKit
        do {
            try await AlarmCenter.shared.requestAuthorization()

            let calendar = Calendar.current
            let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)

            let configuration = AlarmConfiguration(
                label: "Rest complete",
                sound: .default,
                allowsSnooze: false
            )

            let alarm = try await AlarmCenter.shared.scheduleAlarm(
                dateComponents: comps,
                configuration: configuration
            )
            return alarm.identifier
        } catch {
            print("[AlarmService] Schedule failed: \(error)")
            return nil
        }
        #else
        // AlarmKit not available; act as a no-op and return nil
        return nil
        #endif
    }

    /// Cancel a previously scheduled alarm by identifier.
    /// - Parameter id: The identifier of the alarm to cancel.
    func cancelRestAlarm(id: String?) async {
        guard let id else { return }
        #if canImport(AlarmKit)
        import AlarmKit
        do {
            try await AlarmCenter.shared.cancelAlarms(withIdentifiers: [id])
        } catch {
            print("[AlarmService] Cancel failed: \(error)")
        }
        #else
        // AlarmKit not available; nothing to cancel
        #endif
    }
}
