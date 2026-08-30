import SwiftUI
import SwiftData

struct ExerciseDatabaseView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\Exercise.sortOrder, order: .forward)]) private var exercises: [Exercise]

    @State private var showingAddSheet = false
    @State private var showingEditSheet = false
    @State private var exerciseToEdit: Exercise?

    var body: some View {
        List {
            ForEach(exercises, id: \.id) { exercise in
                HStack(spacing: 12) {
                    Image(systemName: exercise.category.systemImage)
                        .frame(width: 28, alignment: .trailing)
                        .foregroundStyle(exercise.category.displayColor)
                    Text(exercise.name)
                        .font(.headline)
                    Spacer()
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(exercise.category.displayName), \(exercise.name)")
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        modelContext.delete(exercise)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button("Edit") {
                        exerciseToEdit = exercise
                        showingEditSheet = true
                    }.tint(.blue)
                }
            }
            .onMove(perform: moveExercises)
            .onDelete(perform: deleteExercises)
        }
        .navigationTitle("Exercises")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
            ToolbarItem {
                Button { showingAddSheet = true } label: {
                    Label("Add Exercise", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            ExerciseEditorView(mode: .add, exercise: nil, onCancel: {
                showingAddSheet = false
            }, onSave: { name, category in
                let nextOrder = (exercises.compactMap(\.sortOrder).max() ?? -1) + 1
                modelContext.insert(Exercise(name: name, sortOrder: nextOrder, category: category))
                showingAddSheet = false
            })
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
    }

    private func moveExercises(from source: IndexSet, to destination: Int) {
        var reordered = exercises
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, exercise) in reordered.enumerated() {
            exercise.sortOrder = index
        }
    }

    private func deleteExercises(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(exercises[index])
        }
    }
}

#Preview {
    NavigationStack {
        ExerciseDatabaseView()
    }
    .modelContainer(for: Exercise.self, inMemory: true)
}
