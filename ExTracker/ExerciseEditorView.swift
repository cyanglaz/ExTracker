import SwiftUI
import SwiftData

enum ExerciseEditorMode {
    case add, edit
}

struct ExerciseEditorView: View {
    let mode: ExerciseEditorMode
    let exercise: Exercise?
    let onCancel: () -> Void
    let onSave: (String, ExerciseCategory) -> Void

    @State private var name: String
    @State private var category: ExerciseCategory

    init(
        mode: ExerciseEditorMode,
        exercise: Exercise? = nil,
        onCancel: @escaping () -> Void,
        onSave: @escaping (String, ExerciseCategory) -> Void
    ) {
        self.mode = mode
        self.exercise = exercise
        self.onCancel = onCancel
        self.onSave = onSave

        if let exercise = exercise, mode == .edit {
            _name = State(initialValue: exercise.name)
            _category = State(initialValue: exercise.category)
        } else {
            _name = State(initialValue: "")
            _category = State(initialValue: .chest)
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Exercise name", text: $name)
                    Picker("Category", selection: $category) {
                        ForEach(ExerciseCategory.allCases, id: \.self) { cat in
                            Label(cat.displayName, systemImage: cat.systemImage)
                                .tag(cat)
                        }
                    }.ignoresSafeArea(.keyboard)
                }
            }
            .navigationTitle(mode == .add ? "New Exercise" : "Edit Exercise")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(trimmedName, category)
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

#Preview("Add & Edit") {
    VStack(spacing: 24) {
        ExerciseEditorView(
            mode: .add,
            onCancel: { },
            onSave: { _, _ in }
        )
        .frame(maxHeight: 400)

        ExerciseEditorView(
            mode: .edit,
            exercise: Exercise(
                name: "Push-up",
                category: .chest
            ),
            onCancel: { },
            onSave: { _, _ in }
        )
        .frame(maxHeight: 400)
    }
    .padding()
}
