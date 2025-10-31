//
//  ContentView.swift
//  ExTracker
//
//  Created by Chris Yang on 10/26/25.
//

import SwiftUI
import SwiftData
import Combine

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Exercise.createdAt, order: .forward)]) private var exerciseData: [Exercise]
    @Query(sort: [SortDescriptor(\ExerciseSessionRecord.date, order: .reverse)]) private var sessionRecords: [ExerciseSessionRecord]
    
    @StateObject private var alarmManager = ExAlarmManager.shared
    @State private var countdownTick: Int = 0

    private var hasPersistedRest: Bool {
        guard let ts = RestTimerManager.shared.restEndDate?.timeIntervalSince1970 else {
            return false
        }
        return ts > Date().timeIntervalSince1970
    }
    
    private var startOfToday: Date { Calendar.current.startOfDay(for: Date()) }

    var exercises: [Exercise] {
        exerciseData.sorted { getDaysLeft(for: $0) < getDaysLeft(for: $1) }
    }
    
    @State private var showingAddSheet = false

    @State private var showingEditSheet = false
    @State private var exerciseToEdit: Exercise?
    @State private var editName: String = ""
    @State private var editFrequency: Int = 7
    @State private var editCategory: ExerciseCategory = .chest
    
    @State private var lastExercise: Exercise?

    private func dismissAddSheet() {
        showingAddSheet = false
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(exercises, id: \.id) { exercise in
                    NavigationLink {
                        ExerciseSessionView(exercise: exercise, onPopped: { ex in
                            lastExercise = ex
                        })
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: exercise.category.systemImage)
                                .frame(width: 28, alignment: .trailing)
                                .foregroundStyle(exercise.category.displayColor)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(exercise.name)
                                    .font(.headline)
                                HStack(spacing: 8) {
                                    if let last = latestRecord(for: exercise)?.date {
                                        Text(last, style: .date)
                                    } else {
                                        Text("N/A")
                                    }
                                    Text("•")
                                    Text("Every \(exercise.frequency) day\(exercise.frequency == 1 ? "" : "s")")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(getDaysLeft(for: exercise))")
                                .monospacedDigit()
                                .foregroundStyle(
                                    getDaysLeft(for: exercise) <= 0 ? .red :
                                    (getDaysLeft(for: exercise) == 1 ? .orange : .green)
                                )
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(exercise.category.displayName), \(exercise.name), days left \(getDaysLeft(for: exercise))")
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Edit") {
                            beginEdit(exercise)
                        }.tint(.blue)
                    }
                }
                .onDelete(perform: deleteExercises)
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if let ex = lastExercise {
                        NavigationLink {
                            ExerciseSessionView(exercise: ex, onPopped: { ex in
                                lastExercise = ex
                            })
                        } label: {
                            Label("Today", systemImage: "bolt.fill")
                        }
                        .accessibilityLabel("Resume today's session")
                    }
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    if alarmManager.isAlerting {
                        // Alarm is ringing: show stop button
                        Button(role: .destructive) {
                            RestTimerManager.shared.cancel()
                        } label: {
                            Image(systemName: "stop.circle.fill")
                        }
                        .tint(.red)
                        .accessibilityLabel("Stop alarm")
                    } else if hasPersistedRest {
                        // Show a countdown label (no action) while timer is running
                        if let ts = RestTimerManager.shared.restEndDate?.timeIntervalSince1970 {
                            let remainingSeconds = max(0, Int(Date(timeIntervalSince1970: ts).timeIntervalSinceNow.rounded()))
                            let color: Color = {
                                switch remainingSeconds {
                                case 0...30:
                                    return .red
                                case 31...60:
                                    return .orange
                                default:
                                    return .green
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
                    Button(action: { showingAddSheet = true }) {
                        Label("Add Exercise", systemImage: "plus")
                    }
                }
            }
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
                countdownTick &+= 1
            }
            .sheet(isPresented: $showingAddSheet) {
                NavigationStack {
                    ExerciseEditorView(mode: .add, exercise: nil, onCancel: {
                        dismissAddSheet()
                    }, onSave: { name, freq, category in
                        withAnimation {
                            let new = Exercise(name: name, frequency: freq, category: category)
                            modelContext.insert(new)
                        }
                        dismissAddSheet()
                    })
                }
            }
            .sheet(isPresented: $showingEditSheet) {
                NavigationStack {
                    ExerciseEditorView(mode: .edit, exercise: exerciseToEdit, onCancel: {
                        cancelEdit()
                    }, onSave: { name, freq, category in
                        guard let ex = exerciseToEdit else { return }
                        withAnimation {
                            ex.name = name
                            ex.frequency = freq
                            ex.category = category
                        }
                        cancelEdit()
                    })
                }
            }
            .navigationTitle("Exercises")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private func deleteExercises(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(self.exercises[index])
            }
        }
    }

    private func beginEdit(_ exercise: Exercise) {
        exerciseToEdit = exercise
        editName = exercise.name
        editFrequency = exercise.frequency
        editCategory = exercise.category
        showingEditSheet = true
    }

    private func cancelEdit() {
        showingEditSheet = false
        exerciseToEdit = nil
        editName = ""
        editFrequency = 7
        editCategory = .chest
    }

    private func saveEdit() {
        guard let ex = exerciseToEdit else { return }
        let trimmed = editName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        withAnimation {
            ex.name = trimmed
            ex.frequency = editFrequency
            ex.category = editCategory
        }
        cancelEdit()
    }
    
    private func deleteEditedExercise() {
        guard let ex = exerciseToEdit else { return }
        withAnimation {
            modelContext.delete(ex)
        }
        cancelEdit()
    }
    
    /// Returns all session records for the given exercise, sorted by date descending
    private func sessionRecords(for exercise: Exercise) -> [ExerciseSessionRecord] {
        sessionRecords.filter { $0.exerciseID == exercise.id }
    }

    /// Returns the most recent session record for the given exercise, if any
    private func latestRecord(for exercise: Exercise) -> ExerciseSessionRecord? {
        return sessionRecords(for: exercise).max { a, b in
            a.date < b.date
        }
    }
    
    private func getDaysLeft(for exercise: Exercise) -> Int {
        guard let last = latestRecord(for: exercise) else {
            return 0
        }
        let diff = Calendar.current.component(.day, from: Date()) - Calendar.current.component(.day, from: last.date)
        return exercise.frequency - diff
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Exercise.self, inMemory: true)
}

