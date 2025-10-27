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
    
    var exercises: [Exercise] {
        exerciseData.sorted { $0.daysLeft < $1.daysLeft }
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
        NavigationSplitView {
            List {
                ForEach(exercises) { exercise in
                    NavigationLink {
                        ExerciseSessionView(exercise: exercise)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: exercise.category.systemImage)
                                .foregroundStyle(.tint)
                            VStack(alignment: .leading) {
                                Text(exercise.name)
                            }
                            Spacer()
                            Text("\(exercise.daysLeft)")
                                .monospacedDigit()
                                .foregroundStyle(exercise.daysLeft <= 3 ? .red : .secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(exercise.category.displayName), \(exercise.name), days left \(exercise.daysLeft)")
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
        } detail: {
            Text("Select an exercise")
        }
    }

    private func deleteExercises(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(exercises[index])
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
}

#Preview {
    ContentView()
        .modelContainer(for: Exercise.self, inMemory: true)
}
