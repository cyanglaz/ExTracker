import SwiftUI
import SwiftData

struct SessionsHistoryView: View {
    let exercise: Exercise
    let records: [ExerciseSessionRecord]

    @Environment(\.modelContext) private var modelContext
    @State private var recordPendingDeletion: ExerciseSessionRecord? = nil
    @State private var showDeleteAlert = false

    init(exercise: Exercise, records: [ExerciseSessionRecord] = []) {
        self.exercise = exercise
        self.records = records
    }

    var body: some View {
        List {
            if records.isEmpty {
                Text("No previous sessions")
                    .foregroundStyle(.secondary)
            } else {
                let dayGroups = groupedByDay(records)
                ForEach(Array(dayGroups.enumerated()), id: \.offset) { _, group in
                    Section(header: HStack {
                        Image(systemName: "calendar")
                        Text(group.date, style: .date)
                        Spacer()
                        Text("\(daysAgo(from: group.date)) days ago")
                            .foregroundStyle(.secondary)
                    }) {
                        ForEach(group.items) { rec in
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
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    recordPendingDeletion = rec
                                    showDeleteAlert = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Sessions")
        .alert("Delete session?", isPresented: $showDeleteAlert, presenting: recordPendingDeletion) { record in
            Button("Delete", role: .destructive) {
                deleteSession(record)
            }
            Button("Cancel", role: .cancel) {
                recordPendingDeletion = nil
            }
        } message: { record in
            Text("This will permanently delete the session from \(record.date.formatted(date: .abbreviated, time: .shortened)). This action cannot be undone.")
        }
    }

    private func daysAgo(from date: Date) -> Int {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let startOfThatDay = Calendar.current.startOfDay(for: date)
        let comps = Calendar.current.dateComponents([.day], from: startOfThatDay, to: startOfToday)
        return max(0, comps.day ?? 0)
    }
    
    private func startOfDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    private func groupedByDay(_ records: [ExerciseSessionRecord]) -> [(date: Date, items: [ExerciseSessionRecord])] {
        let groups = Dictionary(grouping: records) { startOfDay($0.date) }
        return groups
            .map { (key: $0.key, value: $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.key > $1.key }
            .map { (date: $0.key, items: $0.value) }
    }
    
    private func deleteSession(_ record: ExerciseSessionRecord) {
        modelContext.delete(record)
        recordPendingDeletion = nil
        // If using a local array rather than @Query, also remove it from that array here.
        #if canImport(UIKit)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif
    }
}

#Preview {
    let container = try! ModelContainer(for: Exercise.self, ExerciseSessionRecord.self, configurations: .init(isStoredInMemoryOnly: true))
    let ex = Exercise(name: "Squat", frequency: 3, category: .leg)
    return NavigationStack { SessionsHistoryView(exercise: ex) }
        .modelContainer(container)
}
