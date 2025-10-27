import SwiftUI
import SwiftData

struct SessionsHistoryView: View {
    let exercise: Exercise
    @Query private var records: [ExerciseSessionRecord]

    init(exercise: Exercise) {
        self.exercise = exercise
        let exerciseID = exercise.id
        self._records = Query(filter: #Predicate<ExerciseSessionRecord> { $0.exerciseID == exerciseID }, sort: [SortDescriptor(\.date, order: .reverse)])
    }

    var body: some View {
        List {
            if records.isEmpty {
                Text("No previous sessions")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(records) { rec in
                    Section(header: HStack {
                        Image(systemName: "calendar")
                        Text(rec.date, style: .date)
                        Spacer()
                        Text("\(daysAgo(from: rec.date)) days ago")
                            .foregroundStyle(.secondary)
                    }) {
                        let count = max(rec.reps.count, rec.weights.count)
                        ForEach(0..<count, id: \.self) { idx in
                            HStack(spacing: 12) {
                                let w = idx < rec.weights.count ? rec.weights[idx].trimmingCharacters(in: .whitespacesAndNewlines) : ""
                                if !w.isEmpty {
                                    Label { Text("\(w) lbs") } icon: { Image(systemName: "scalemass") }
                                }
                                Spacer()
                                Text("x \(idx < rec.reps.count ? rec.reps[idx] : "-")")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Sessions")
    }

    private func daysAgo(from date: Date) -> Int {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let startOfThatDay = Calendar.current.startOfDay(for: date)
        let comps = Calendar.current.dateComponents([.day], from: startOfThatDay, to: startOfToday)
        return max(0, comps.day ?? 0)
    }
}

#Preview {
    let container = try! ModelContainer(for: Exercise.self, ExerciseSessionRecord.self, configurations: .init(isStoredInMemoryOnly: true))
    let ex = Exercise(name: "Squat", frequency: 3, category: .leg)
    return NavigationStack { SessionsHistoryView(exercise: ex) }
        .modelContainer(container)
}
