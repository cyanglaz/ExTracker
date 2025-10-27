import SwiftUI
import SwiftData

#if canImport(UIKit)
import UIKit
#endif

struct ExerciseSessionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let exercise: Exercise

    @State private var sessionSets: [SessionSet] = []
    @State private var showingStartSet = false

    @State private var isResting = false
    @State private var isPaused = false
    @State private var remainingSeconds: Int = 0
    @State private var totalSeconds: Int = 0
    @State private var restTimer: Timer? = nil

    struct SessionSet: Identifiable {
        let id = UUID()
        let weight: String
        let reps: String
        let timestamp: Date
    }

    var body: some View {
        Form {
            if isResting {
                Section("Rest timer") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            ProgressView(value: Double(max(0, remainingSeconds)), total: Double(max(1, totalSeconds)))
                            Text(timeString(from: remainingSeconds))
                                .monospacedDigit()
                                .frame(minWidth: 60, alignment: .trailing)
                        }
                        HStack(spacing: 16) {
                            Button(isPaused ? "Resume" : "Pause") { togglePause() }
                            Button("Cancel", role: .destructive) { cancelRest() }
                        }
                    }
                }
            }

            Section(header: HStack { Text("Sets this session"); Spacer() }) {
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
                }
            }

            if let last = exercise.lastPerformed, !exercise.lastSessionReps.isEmpty || !exercise.lastSessionWeights.isEmpty {
                Section("Last session") {
                    HStack {
                        Image(systemName: "calendar")
                        Text("\(daysAgo(from: last)) days ago")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(last, style: .date)
                    }
                    let count = max(exercise.lastSessionReps.count, exercise.lastSessionWeights.count)
                    ForEach(0..<count, id: \.self) { idx in
                        HStack(spacing: 12) {
                            let w = idx < exercise.lastSessionWeights.count ? exercise.lastSessionWeights[idx].trimmingCharacters(in: .whitespacesAndNewlines) : ""
                            if !w.isEmpty {
                                Label { Text("\(w) lbs") } icon: { Image(systemName: "scalemass") }
                            }
                            Spacer()
                            Text("x \(idx < exercise.lastSessionReps.count ? exercise.lastSessionReps[idx] : "-")")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Exercise")
        .onAppear { print("[ExerciseSessionView] appeared for: \(exercise.name)") }
        .onDisappear {
            print("[ExerciseSessionView] disappeared for: \(exercise.name)")
            restTimer?.invalidate()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink {
                    SessionsHistoryView(exercise: exercise)
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .accessibilityLabel("Previous Session")
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingStartSet = true }) {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Start Set")
            }
        }
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
                    restMinutes: 2, // default or last used; no per-set rest stored in sessionSets
                    restSeconds: 0
                )
            }()

            // Determine the final set from the previous session, if any
            let previousFinal: StartSetView.PreviousSet? = {
                let weights = exercise.lastSessionWeights
                let reps = exercise.lastSessionReps
                let count = max(weights.count, reps.count)
                guard count > 0 else { return nil }
                let lastWeight = (count - 1) < weights.count ? weights[count - 1] : ""
                // If you later store rest per set, use it here. For now, fall back to a sensible default.
                return StartSetView.PreviousSet(
                    weight: lastWeight,
                    restMinutes: 2,
                    restSeconds: 0
                )
            }()

            StartSetView(
                exerciseName: exercise.name,
                onFinish: { weight, reps, min, sec in
                    // Append the set to the session list
                    let set = SessionSet(weight: weight, reps: reps, timestamp: Date())
                    sessionSets.append(set)
                    // Dismiss the sheet back to Exercise page
                    showingStartSet = false
                    startRestTimer(totalSeconds: max(0, min * 60 + sec))
                },
                currentSessionLastSet: currentLast,
                previousSessionFinalSet: previousFinal
            )
        }
    }

    private func startRestTimer(totalSeconds: Int) {
        guard totalSeconds > 0 else { return }
        self.totalSeconds = totalSeconds
        self.remainingSeconds = totalSeconds
        isResting = true
        isPaused = false
        restTimer?.invalidate()
        restTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            guard !isPaused else { return }
            if remainingSeconds > 0 {
                remainingSeconds -= 1
            } else {
                timer.invalidate()
                isResting = false
                playCompletionFeedback()
            }
        }
    }

    private func togglePause() {
        guard isResting else { return }
        isPaused.toggle()
    }

    private func cancelRest() {
        restTimer?.invalidate()
        isResting = false
        isPaused = false
        remainingSeconds = 0
        totalSeconds = 0
    }

    private func playCompletionFeedback() {
        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif
    }

    private func timeString(from seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
    
    private func completeSession() {
        // Save last performed date
        exercise.lastPerformed = Date()
        let record = ExerciseSessionRecord(exerciseID: exercise.id, date: exercise.lastPerformed ?? Date(), weights: sessionSets.map { $0.weight }, reps: sessionSets.map { $0.reps })
        modelContext.insert(record)
        // Copy current session sets into exercise's last session storage
        exercise.lastSessionWeights = sessionSets.map { $0.weight }
        exercise.lastSessionReps = sessionSets.map { $0.reps }
        // Reset daysLeft to at least 1 (acts as max frequency placeholder)
        exercise.frequency = max(exercise.frequency, 1)
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
}

#Preview {
    let container = try! ModelContainer(for: Exercise.self, configurations: .init(isStoredInMemoryOnly: true))
    let ex = Exercise(name: "Bench Press", frequency: 3, category: .chest)
    return ExerciseSessionView(exercise: ex)
        .modelContainer(container)
}
