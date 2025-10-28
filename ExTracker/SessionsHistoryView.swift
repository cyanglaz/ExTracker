import SwiftUI
import SwiftData

struct SessionsHistoryView: View {
    let exercise: Exercise
    @State private var records: [ExerciseSessionRecord] = []
    @State private var isLoading = true

    @Environment(\.modelContext) private var modelContext
    @State private var recordPendingDeletion: ExerciseSessionRecord? = nil
    @State private var showDeleteAlert = false

    init(exercise: Exercise) {
        self.exercise = exercise
    }

    var body: some View {
        Group {
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView("Loading…")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
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
        .task {
            await loadRecords()
        }
    }

    private func daysAgo(from date: Date) -> Int {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let startOfThatDay = Calendar.current.startOfDay(for: date)
        let comps = Calendar.current.dateComponents([.day], from: startOfThatDay, to: startOfToday)
        return max(0, comps.day ?? 0)
    }
    
    private func loadRecords() async {
        isLoading = true
        let exerciseID = exercise.id
        do {
            let descriptor = FetchDescriptor<ExerciseSessionRecord>(
                predicate: #Predicate { $0.exerciseID == exerciseID },
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            // Perform fetch off the main actor
            let fetched: [ExerciseSessionRecord] = try await Task.detached(priority: .userInitiated) {
                return try modelContext.fetch(descriptor)
            }.value
            await MainActor.run {
                self.records = fetched
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.records = []
                self.isLoading = false
            }
        }
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
