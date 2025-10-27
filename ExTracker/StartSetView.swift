import SwiftUI

struct StartSetView: View {
    let exerciseName: String
    var onFinish: (_ weight: String, _ reps: String, _ restMinutes: Int, _ restSeconds: Int) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var weight: String = ""
    @State private var reps: String = ""
    @State private var restMinutes: Int = 2
    @State private var restSeconds: Int = 0

    @State private var isResting = false
    @State private var remainingSeconds: Int = 0
    @State private var restTimer: Timer? = nil

    @State private var showRepsEmptyAlert = false
    @State private var showRestDoneAlert = false

    var body: some View {
        Form {
            Section("Current set") {
                TextField("Weight (e.g. 100 lb)", text: $weight)
                    .keyboardType(.decimalPad)
                TextField("Reps (e.g. 8)", text: $reps)
                    .keyboardType(.numberPad)
            }
            Section("Rest") {
                Stepper(value: $restMinutes, in: 0...30) {
                    HStack {
                        Text("Rest minutes")
                        Spacer()
                        Text("\(restMinutes)")
                            .monospacedDigit()
                    }
                }
                Stepper(value: $restSeconds, in: 0...55, step: 5) {
                    HStack {
                        Text("Rest seconds")
                        Spacer()
                        Text("\(restSeconds)")
                            .monospacedDigit()
                    }
                }
                if isResting {
                    HStack {
                        ProgressView(value: Double(max(0, remainingSeconds)), total: Double(max(1, restTotalSeconds())))
                        Text(timeString(from: remainingSeconds))
                            .monospacedDigit()
                            .frame(minWidth: 60, alignment: .trailing)
                    }
                }
            }
            Section {
                Button(action: finishAndRest) {
                    Label(isResting ? "Resting..." : "Finish and Rest", systemImage: isResting ? "timer" : "checkmark.circle.fill")
                }
                .disabled(isResting)
            }
        }
        .navigationTitle("Exercise")
        .alert("Reps required", isPresented: $showRepsEmptyAlert) {
            Button("OK", role: .cancel) { showRepsEmptyAlert = false }
        } message: {
            Text("Please enter the number of reps before finishing the set.")
        }
        .alert("Rest complete", isPresented: $showRestDoneAlert) {
            Button("OK") { showRestDoneAlert = false }
        } message: {
            Text("Time to start your next set of \(exerciseName).")
        }
        .onDisappear { restTimer?.invalidate() }
    }

    private func finishAndRest() {
        let trimmedReps = reps.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReps.isEmpty else {
            showRepsEmptyAlert = true
            return
        }
        // Pass the set back to the caller (Exercise page) and start the timer locally.
        onFinish(weight.trimmingCharacters(in: .whitespacesAndNewlines), trimmedReps, restMinutes, restSeconds)

        isResting = true
        remainingSeconds = max(0, restTotalSeconds())
        restTimer?.invalidate()
        restTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if remainingSeconds > 0 {
                remainingSeconds -= 1
            } else {
                timer.invalidate()
                isResting = false
                showRestDoneAlert = true
            }
        }
    }

    private func restTotalSeconds() -> Int {
        max(0, restMinutes * 60 + restSeconds)
    }

    private func timeString(from seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }
}

#Preview {
    StartSetView(exerciseName: "Bench Press") { _,_,_,_ in }
}
