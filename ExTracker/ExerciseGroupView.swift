import SwiftUI
import SwiftData
import Combine

struct ExerciseGroupView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let group: ExerciseGroup
    let allExercises: [Exercise]
    let onExerciseCompleted: () -> Void

    @Query(sort: [SortDescriptor(\ExerciseSessionRecord.date, order: .reverse)]) private var allSessionRecords: [ExerciseSessionRecord]
    @StateObject private var alarmManager = ExAlarmManager.shared
    @State private var countdownTick: Int = 0
    @State private var showingExercisePicker = false
    @State private var showingEditSheet = false
    @State private var exerciseToEdit: Exercise?
    @State private var lastExercise: Exercise?

    private var hasPersistedRest: Bool {
        guard let ts = RestTimerManager.shared.restEndDate?.timeIntervalSince1970 else { return false }
        return ts > Date().timeIntervalSince1970
    }

    /// Exercises in this group, in the group-defined order.
    private var groupExercises: [Exercise] {
        group.exerciseIDs.compactMap { id in allExercises.first { $0.id == id } }
    }

    var body: some View {
        List {
            ForEach(groupExercises, id: \.id) { exercise in
                NavigationLink {
                    ExerciseSessionView(
                        exercise: exercise,
                        onPopped: { ex in lastExercise = ex },
                        onCompleted: onExerciseCompleted
                    )
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: exercise.category.systemImage)
                            .frame(width: 28, alignment: .trailing)
                            .foregroundStyle(exercise.category.displayColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exercise.name)
                                .font(.headline)
                            if let last = latestRecord(for: exercise)?.date {
                                Text(last, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("N/A")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(exercise.category.displayName), \(exercise.name)")
                }
                .swipeActions(edge: .trailing) {
                    Button("Remove", role: .destructive) {
                        group.exerciseIDs.removeAll { $0 == exercise.id }
                    }
                    Button("Edit") {
                        exerciseToEdit = exercise
                        showingEditSheet = true
                    }.tint(.blue)
                }
            }
            .onMove(perform: moveExercises)
            .onDelete(perform: removeExercises)
        }
        .navigationTitle(group.name)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if let ex = lastExercise {
                    NavigationLink {
                        ExerciseSessionView(
                            exercise: ex,
                            onPopped: { ex in lastExercise = ex },
                            onCompleted: onExerciseCompleted
                        )
                    } label: {
                        Label("Today", systemImage: "bolt.fill")
                    }
                    .accessibilityLabel("Resume today's session")
                }
            }
            ToolbarItem(placement: .navigationBarLeading) {
                if alarmManager.isAlerting {
                    Button(role: .destructive) {
                        RestTimerManager.shared.cancel()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                    }
                    .tint(.red)
                    .accessibilityLabel("Stop alarm")
                } else if hasPersistedRest {
                    if let ts = RestTimerManager.shared.restEndDate?.timeIntervalSince1970 {
                        let remainingSeconds = max(0, Int(Date(timeIntervalSince1970: ts).timeIntervalSinceNow.rounded()))
                        let color: Color = {
                            switch remainingSeconds {
                            case 0...30: return .red
                            case 31...60: return .orange
                            default: return .green
                            }
                        }()
                        Text("\(remainingSeconds)")
                            .monospacedDigit()
                            .id(countdownTick)
                            .foregroundStyle(color)
                            .accessibilityLabel("Rest remaining \(remainingSeconds) seconds")
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
            ToolbarItem {
                Button { showingExercisePicker = true } label: {
                    Label("Add Exercise", systemImage: "plus")
                }
            }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            countdownTick &+= 1
        }
        .sheet(isPresented: $showingExercisePicker) {
            ExercisePickerSheet(group: group, allExercises: allExercises)
        }
        .sheet(isPresented: $showingEditSheet) {
            if let ex = exerciseToEdit {
                ExerciseEditorView(mode: .edit, exercise: ex, onCancel: {
                    showingEditSheet = false
                    exerciseToEdit = nil
                }, onSave: { name, category in
                    ex.name = name
                    ex.category = category
                    showingEditSheet = false
                    exerciseToEdit = nil
                })
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: completeGroup) {
                Text("Complete")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding([.horizontal, .bottom])
        }
    }

    private func completeGroup() {
        onExerciseCompleted()
        dismiss()
    }

    private func moveExercises(from source: IndexSet, to destination: Int) {
        group.exerciseIDs.move(fromOffsets: source, toOffset: destination)
    }

    private func removeExercises(offsets: IndexSet) {
        let ids = offsets.map { groupExercises[$0].id }
        group.exerciseIDs.removeAll { ids.contains($0) }
    }

    private func latestRecord(for exercise: Exercise) -> ExerciseSessionRecord? {
        allSessionRecords.filter { $0.exerciseID == exercise.id }.max { $0.date < $1.date }
    }
}

// MARK: - Exercise Picker Sheet

private struct ExercisePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let group: ExerciseGroup
    let allExercises: [Exercise]

    private var available: [Exercise] {
        allExercises
            .filter { !group.exerciseIDs.contains($0.id) }
            .sorted { ($0.sortOrder ?? Int.max) < ($1.sortOrder ?? Int.max) }
    }

    var body: some View {
        NavigationStack {
            List {
                if available.isEmpty {
                    Text("All exercises are already in this group.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(available, id: \.id) { exercise in
                        Button {
                            group.exerciseIDs.append(exercise.id)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: exercise.category.systemImage)
                                    .frame(width: 28, alignment: .trailing)
                                    .foregroundStyle(exercise.category.displayColor)
                                Text(exercise.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if group.exerciseIDs.contains(exercise.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Exercises")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
