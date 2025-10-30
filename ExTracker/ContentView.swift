//
//  ContentView.swift
//  ExTracker
//
//  Created by Chris Yang on 10/26/25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Exercise.createdAt, order: .forward)]) private var exerciseData: [Exercise]
    @Query(sort: [SortDescriptor(\ExerciseSessionRecord.date, order: .reverse)]) private var sessionRecords: [ExerciseSessionRecord]
    
    var exercises: [Exercise] {
        exerciseData.sorted { getDaysLeft(for: $0) < getDaysLeft(for: $1) }
    }
    
    @State private var showingAddSheet = false
    @State private var draftName: String = ""
    @State private var frequency: Int = 7
    @State private var draftCategory: ExerciseCategory = .chest

    @State private var showingEditSheet = false
    @State private var exerciseToEdit: Exercise?
    @State private var editName: String = ""
    @State private var editFrequency: Int = 7
    @State private var editCategory: ExerciseCategory = .chest

    var body: some View {
        NavigationStack {
            List {
                ForEach(exercises, id: \.id) { exercise in
                    NavigationLink {
                        ExerciseSessionView(exercise: exercise)
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
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
                ToolbarItem {
                    Button(action: { showingAddSheet = true }) {
                        Label("Add Exercise", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                NavigationStack {
                    Form {
                        Section("Details") {
                            TextField("Exercise name", text: $draftName)
                            Picker("Category", selection: $draftCategory) {
                                ForEach(ExerciseCategory.allCases) { cat in
                                    Label(cat.displayName, systemImage: cat.systemImage)
                                        .tag(cat)
                                }
                            }
                            Stepper(value: $frequency, in: 1...365) {
                                HStack {
                                    Text("Frequency (days)")
                                    Spacer()
                                    Text("\(frequency)").monospacedDigit()
                                }
                            }
                        }
                    }
                    .navigationTitle("New Exercise")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                showingAddSheet = false
                                draftName = ""
                                frequency = 7
                                draftCategory = .chest
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !trimmed.isEmpty else { return }
                                withAnimation {
                                    let new = Exercise(name: trimmed, frequency: frequency, category: draftCategory)
                                    modelContext.insert(new)
                                }
                                showingAddSheet = false
                                draftName = ""
                                frequency = 7
                                draftCategory = .chest
                            }
                            .disabled(draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }
            .sheet(isPresented: $showingEditSheet) {
                NavigationStack {
                    Form {
                        Section("Details") {
                            TextField("Exercise name", text: $editName)
                            Picker("Category", selection: $editCategory) {
                                ForEach(ExerciseCategory.allCases) { cat in
                                    Label(cat.displayName, systemImage: cat.systemImage)
                                        .tag(cat)
                                }
                            }
                            Stepper(value: $editFrequency, in: 1...365) {
                                HStack {
                                    Text("Frequency (days)")
                                    Spacer()
                                    Text("\(editFrequency)").monospacedDigit()
                                }
                            }
                        }
                        
                        Section {
                            Button(role: .destructive) {
                                deleteEditedExercise()
                            } label: {
                                Text("Delete Exercise")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        
                    }
                    .navigationTitle("Edit Exercise")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { cancelEdit() }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") { saveEdit() }
                                .disabled(editName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
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

