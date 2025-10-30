import SwiftUI
import SwiftData
import UserNotifications

#if canImport(UIKit)
import UIKit
#endif


struct ExerciseSessionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @StateObject private var alarmManager = ExAlarmManager.shared

    let exercise: Exercise
    @Query private var records: [ExerciseSessionRecord]

    @State private var existingRecord: ExerciseSessionRecord? = nil
    @State private var isEditingExisting = false

    @State private var sessionSets: [SessionSet] = []
    @State private var showingStartSet = false

    @State private var isResting = false
    @State private var isPaused = false
    @State private var remainingSeconds: Int = 0
    @State private var totalSeconds: Int = 0
    @State private var restTimer: Timer? = nil
    @State private var restEndDate: Date? = nil

    struct SessionSet: Identifiable {
        let id = UUID()
        let weight: String
        let reps: String
        let timestamp: Date
        let restMinutes: Int
        let restSeconds: Int
    }

    init(exercise: Exercise, latestRecord: ExerciseSessionRecord? = nil) {
        self.exercise = exercise
        let exerciseID = exercise.id
        self._records = Query(
            filter: #Predicate<ExerciseSessionRecord> { $0.exerciseID == exerciseID },
            sort: [SortDescriptor(\.date, order: .reverse)]
        )
    }

    var body: some View {
        SwiftUI.Form {
            if alarmManager.isAlerting {
                SwiftUI.Section {
                    Button(role: .destructive) {
                        alarmManager.cancelActiveCountdown()
                        // Also make sure local rest state is cleared
                        cancelRest()
                    } label: {
                        Label("Stop Alarm", systemImage: "stop.circle.fill")
                            .font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .accessibilityLabel("Stop Alarm")
                }
            }

            if isResting {
                SwiftUI.Section("Rest timer") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            ProgressView(value: Double(max(0, remainingSeconds)), total: Double(max(1, totalSeconds)))
                            Text(timeString(from: remainingSeconds))
                                .monospacedDigit()
                                .frame(minWidth: 60, alignment: .trailing)
                        }
                        HStack(spacing: 16) {
                            Button(isPaused ? "Resume" : "Pause", systemImage: isPaused ? "play.fill" : "pause.fill", action:{})
                                .onTapGesture { togglePause() }
                            Button("Cancel", systemImage: "stop.fill", role: .destructive, action:{}).onTapGesture { cancelRest() }
                        }
                    }
                }
            }

            SwiftUI.Section(header: HStack {
                Image(systemName: exercise.category.systemImage)
                    .foregroundStyle(exercise.category.displayColor)
                Text("Sets this session")
                Spacer()
            }) {
                if sessionSets.isEmpty {
                    Text("No sets yet").foregroundStyle(.secondary)
                } else {
                    ForEach(sessionSets) { set in
                        HStack(spacing: 12) {
                            if !set.weight.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Label {
                                    Text("\(set.weight) lbs")
                                } icon: {
                                    Image(systemName: "scalemass")
                                }
                            }

                            Spacer()

                            Text("x \(set.reps)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityLabel("\(set.weight.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No weight" : "Weight \(set.weight) pounds"), x \(set.reps)")
                    }
                    .onDelete { indexSet in
                        sessionSets.remove(atOffsets: indexSet)
                        // Persist changes after deletion
                        if sessionSets.isEmpty {
                            // If no sets remain, delete today's record if it exists
                            if let rec = todayRecord() {
                                modelContext.delete(rec)
                                existingRecord = nil
                                isEditingExisting = false
                            }
                        } else {
                            saveSessionIfNeeded()
                        }
                    }
                }
            }

            if let displayRecord = latestNonTodayRecord() {
                SwiftUI.Section("Last session") {
                    HStack {
                        Image(systemName: "calendar")
                        Text("\(daysAgo(from: displayRecord.date)) days ago")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(displayRecord.date, style: .date)
                    }
                    let count = max(displayRecord.reps.count, displayRecord.weights.count)
                    ForEach(0..<count, id: \.self) { idx in
                        HStack(spacing: 12) {
                            let w = idx < displayRecord.weights.count ? displayRecord.weights[idx].trimmingCharacters(in: .whitespacesAndNewlines) : "0"
                            Label { Text("\(w) lbs") } icon: { Image(systemName: "scalemass") }
                            Spacer()
                            Text("x \(idx < displayRecord.reps.count ? displayRecord.reps[idx] : "-")")
                                .monospacedDigit()
                                .foregroundStyle( .secondary)
                        }
                    }
                    if let today = todayRecord() ?? records.first {
                        Button {
                            existingRecord = todayRecord() ?? today
                            self.sessionSets = zip(existingRecord?.weights ?? [], existingRecord?.reps ?? []).map { (w, r) in
                                SessionSet(weight: w, reps: r, timestamp: Date(), restMinutes: 0, restSeconds: 0)
                            }
                            self.isEditingExisting = true
                        } label: {
                            Label(todayRecord() != nil ? "Editing today's session" : "Continue last session", systemImage: todayRecord() != nil ? "pencil" : "play.circle")
                        }
                    }
                }
            }
        }
        .navigationTitle(exercise.name)
        .navigationBarBackButtonHidden(true)
        .toolbar(content: {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: {
                    saveSessionIfNeeded()
                    sessionSets.removeAll()
                    cancelRest()
                    dismiss()
                }) {
                    Label("Back", systemImage: "chevron.left")
                }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink {
                    SessionsHistoryView(exercise: exercise, records: records)
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .accessibilityLabel("Previous Session")

                EditButton()

                Button(action: {
                    showingStartSet = true
                }) {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Start Set")
            }
        })
        .safeAreaInset(edge: .bottom) {
            Button(action: completeSession) {
                Text("Complete")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding([.horizontal, .bottom])
        }
        .sheet(isPresented: $showingStartSet) {
            // Determine the last set in the current session, if any
            let currentLast: StartSetView.PreviousSet? = {
                guard let last = sessionSets.last else { return nil }
                return StartSetView.PreviousSet(
                    weight: last.weight,
                    reps: last.reps,
                    restMinutes: last.restMinutes, // default or last used; no per-set rest stored in sessionSets
                    restSeconds: last.restSeconds
                )
            }()

            // Determine the final set from the previous session, if any
            let previousFinal: StartSetView.PreviousSet? = {
                var latestSessionWeights:[String] = []
                var latestSessionReps:[String] = []
                if let latestRecord = getLatestRecord(){
                    latestSessionWeights = latestRecord.weights
                    latestSessionReps = latestRecord.reps
                }
                let weights = latestSessionWeights
                let reps = latestSessionReps
            
                let lastWeight = (weights.last != nil) ? weights.last! : "";
                let lastRep = (reps.last != nil) ? reps.last! : "";
                // If you later store rest per set, use it here. For now, fall back to a sensible default.
                return StartSetView.PreviousSet(
                    weight: lastWeight,
                    reps: lastRep,
                    restMinutes: 2,
                    restSeconds: 30
                )
            }()

            StartSetView(
                exerciseName: exercise.name,
                onFinish: { weight, reps, min, sec in
                    // Append the set to the session list
                    let set = SessionSet(weight: weight, reps: reps, timestamp: Date(), restMinutes: min, restSeconds: sec)
                    sessionSets.append(set)
                    // Persist immediately after adding a set
                    saveSessionIfNeeded()
                    // Dismiss the sheet back to Exercise page
                    showingStartSet = false
                    let total = max(0, min * 60 + sec)
                    Task { await startRestTimer(totalSeconds: total) }
                },
                currentSessionLastSet: currentLast,
                previousSessionFinalSet: previousFinal
            )
        }
        .onAppear { preloadTodaySessionIfAny() }
    }

    private func startOfDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    private func isSameDay(_ a: Date, _ b: Date) -> Bool {
        Calendar.current.isDate(a, inSameDayAs: b)
    }

    private func todayRecord() -> ExerciseSessionRecord? {
        let today = startOfDay(Date())
        return records.first { isSameDay($0.date, today) }
    }

    private func latestNonTodayRecord() -> ExerciseSessionRecord? {
        let today = startOfDay(Date())
        return records
            .filter { !isSameDay($0.date, today) }
            .sorted { $0.date > $1.date }
            .first
    }

    private func preloadTodaySessionIfAny() {
        guard sessionSets.isEmpty else { return }
        if let record = todayRecord() {
            existingRecord = record
            isEditingExisting = true
            self.sessionSets = zip(record.weights, record.reps).map { (w, r) in
                SessionSet(weight: w, reps: r, timestamp: Date(), restMinutes: 0, restSeconds: 0)
            }
        }
    }

    private func saveSessionIfNeeded() {
        // If there are no sets, remove today's record if it exists
        if sessionSets.isEmpty {
            if let rec = todayRecord() {
                modelContext.delete(rec)
            }
            existingRecord = nil
            isEditingExisting = false
            return
        }

        var record = todayRecord()
        if record == nil {
            record = ExerciseSessionRecord(
                exerciseID: exercise.id,
                date: Date(),
                weights: sessionSets.map { $0.weight },
                reps: sessionSets.map { $0.reps }
            )
            if let newRecord = record { modelContext.insert(newRecord) }
        } else {
            record?.weights = sessionSets.map { $0.weight }
            record?.reps = sessionSets.map { $0.reps }
        }
        existingRecord = record
        isEditingExisting = true

        exercise.frequency = max(exercise.frequency, 1)
    }
    
    private func completeSession() {
        // If there are no sets, do not save anything
        guard !sessionSets.isEmpty else {
            // Stop any running timer and dismiss
            cancelRest()
            dismiss()
            return
        }

        saveSessionIfNeeded()

        // Clear current session sets
        sessionSets.removeAll()
        // Stop any running timer
        cancelRest()
        // Dismiss back to main list
        dismiss()
    }
    
    private func daysAgo(from date: Date) -> Int {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let startOfThatDay = Calendar.current.startOfDay(for: date)
        let comps = Calendar.current.dateComponents([.day], from: startOfThatDay, to: startOfToday)
        return max(0, comps.day ?? 0)
    }

    private func startRestTimer(totalSeconds: Int) async {
        guard totalSeconds > 0 else { return }
        self.totalSeconds = totalSeconds
        self.restEndDate = Date().addingTimeInterval(TimeInterval(totalSeconds))
        self.remainingSeconds = totalSeconds
        self.isResting = true
        self.isPaused = false
        let authorizationStatus = await ExAlarmManager.shared.requestAuthorizationIfNeeded()

        startTimer(totalSeconds: totalSeconds)
        
        if (authorizationStatus == .denied) {
            scheduleNotification(totalSeconds: totalSeconds)
        } else {
           await scheduleAlarm(totalSeconds: totalSeconds)
        }
    }
    
    private func startTimer(totalSeconds: Int) {
        // Invalidate any existing timer and start a new UI timer
        restTimer?.invalidate()
        restTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            guard !isPaused else { return }
            let remaining = max(0, Int((restEndDate ?? Date()).timeIntervalSinceNow.rounded()))
            remainingSeconds = remaining
            if remaining <= 0 {
                timer.invalidate()
                isResting = false
                restEndDate = nil
                playCompletionFeedback()
            }
        }
    }
    
    private func scheduleNotification(totalSeconds: Int) {
        // Schedule local notification for when the timer ends
        scheduleRestCompletionNotification(at: self.restEndDate!)
    }
    
    private func scheduleAlarm(totalSeconds: Int) async {
        let alarmCooldownRequest = AppCountdownRequest(seconds: totalSeconds, title: "Rest Complete", message: "")
        do {
            try await ExAlarmManager.shared.scheduleCountdown(alarmCooldownRequest)
        } catch {
            scheduleNotification(totalSeconds: totalSeconds)
        }
    }

    private func togglePause() {
        guard isResting else { return }
        isPaused.toggle()
        // When pausing, capture remainingSeconds; when resuming, recompute end date
        if isPaused {
            ExAlarmManager.shared.togglePauseActiveAlarm(on: true)
            // Freeze remainingSeconds by stopping updates; timer closure respects isPaused
        } else {
            // Resuming: set a new end date from current remainingSeconds
            if remainingSeconds > 0 {
                restEndDate = Date().addingTimeInterval(TimeInterval(remainingSeconds))
                // Re-schedule the notification for the new end date
                scheduleRestCompletionNotification(at: restEndDate!)
            }
            ExAlarmManager.shared.togglePauseActiveAlarm(on: false)
        }
    }

    private func cancelRest() {
        restTimer?.invalidate()
        isResting = false
        isPaused = false
        remainingSeconds = 0
        totalSeconds = 0
        restEndDate = nil
        cancelRestCompletionNotification()
        ExAlarmManager.shared.cancelActiveCountdown()
    }

    private func playCompletionFeedback() {
        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif
    }

    private func scheduleRestCompletionNotification(at date: Date) {
        let center = UNUserNotificationCenter.current()
        // Remove any existing pending notification for rest completion
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

    private func timeString(from seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
    
    private func getLatestRecord() -> ExerciseSessionRecord? {
        if records.isEmpty { return nil }
        return records.max { a, b in
            a.date < b.date
        }
    }
}

#Preview {
    let container = try! ModelContainer(for: Exercise.self, configurations: .init(isStoredInMemoryOnly: true))
    let ex = Exercise(name: "Bench Press", frequency: 3, category: .chest)
    return ExerciseSessionView(exercise: ex)
        .modelContainer(container)
}
