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
    @StateObject private var restManager = RestTimerManager.shared

    var onPopped: ((Exercise) -> Void)? = nil

    let exercise: Exercise
    @Query private var records: [ExerciseSessionRecord]

    @State private var existingRecord: ExerciseSessionRecord? = nil
    @State private var isEditingExisting = false

    @State private var sessionSets: [SessionSet] = []
    @State private var showingStartSet = false
    @State private var hasCalledPopCallback = false

    struct SessionSet: Identifiable {
        let id = UUID()
        let weight: String
        let reps: String
        let timestamp: Date
        let restMinutes: Int
        let restSeconds: Int
    }

    init(exercise: Exercise, latestRecord: ExerciseSessionRecord? = nil, onPopped: ((Exercise) -> Void)? = nil) {
        self.exercise = exercise
        self.onPopped = onPopped
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
                        restManager.cancel()
                    } label: {
                        Label("Stop Alarm", systemImage: "stop.circle.fill")
                            .font(.headline)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .accessibilityLabel("Stop Alarm")
                }
            }

            if restManager.isResting {
                SwiftUI.Section("Rest timer") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            ProgressView(value: Double(max(0, restManager.remainingSeconds)), total: Double(max(1, restManager.totalSeconds)))
                            Text(timeString(from: restManager.remainingSeconds))
                                .monospacedDigit()
                                .frame(minWidth: 60, alignment: .trailing)
                        }
                        HStack(spacing: 16) {
                            Button(restManager.isPaused ? "Resume" : "Pause", systemImage: restManager.isPaused ? "play.fill" : "pause.fill", action:{})
                                .onTapGesture { restManager.isPaused ? restManager.resume() : restManager.pause() }
                            Button("Cancel", systemImage: "stop.fill", role: .destructive) {
                                restManager.cancel()
                            }
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
                            let w = set.weight
                            Label { Text("\(w) lbs") } icon: { Image(systemName: "scalemass") }
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
        .toolbar(content: {
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
                    restMinutes: DefaultRestMinutes,
                    restSeconds: DefaultRestSeconds,
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
                    restManager.startRest(totalSeconds: total)
                },
                currentSessionLastSet: currentLast,
                previousSessionFinalSet: previousFinal
            )
        }
        .onAppear {
            preloadTodaySessionIfAny()
        }
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
        dismiss()
        if !hasCalledPopCallback { hasCalledPopCallback = true; onPopped?(exercise) }
    }

    private func daysAgo(from date: Date) -> Int {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let startOfThatDay = Calendar.current.startOfDay(for: date)
        let comps = Calendar.current.dateComponents([.day], from: startOfThatDay, to: startOfToday)
        return max(0, comps.day ?? 0)
    }
    
    private func getLatestRecord() -> ExerciseSessionRecord? {
        if records.isEmpty { return nil }
        return records.max { a, b in
            a.date < b.date
        }
    }
    
    private func timeString(from remainingSeconds: Int) -> String {
        let minutes = remainingSeconds / 60
        let seconds = remainingSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
#Preview {
    let container = try! ModelContainer(for: Exercise.self, configurations: .init(isStoredInMemoryOnly: true))
    let ex = Exercise(name: "Bench Press", frequency: 3, category: .chest)
    return ExerciseSessionView(exercise: ex, onPopped: nil)
}
