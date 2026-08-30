import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\ExerciseGroup.sortOrder, order: .forward)]) private var groups: [ExerciseGroup]
    @Query private var allExercises: [Exercise]

    @State private var showingAddGroup = false
    @State private var newGroupName = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(groups) { group in
                    NavigationLink {
                        ExerciseGroupView(group: group, allExercises: allExercises, onExerciseCompleted: {
                            pushGroupToEnd(group)
                        })
                    } label: {
                        let count = allExercises.filter { group.exerciseIDs.contains($0.id) }.count
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.name)
                                .font(.headline)
                            Text("\(count) exercise\(count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .onMove(perform: moveGroups)
                .onDelete(perform: deleteGroups)
            }
            .navigationTitle("Groups")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    NavigationLink {
                        ExerciseDatabaseView()
                    } label: {
                        Label("Exercises", systemImage: "list.bullet")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
                ToolbarItem {
                    Button { showingAddGroup = true } label: {
                        Label("Add Group", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddGroup) {
                NavigationStack {
                    Form {
                        Section {
                            TextField("Group name", text: $newGroupName)
                        }
                    }
                    .navigationTitle("New Group")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                showingAddGroup = false
                                newGroupName = ""
                            }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Add") {
                                let nextOrder = (groups.map(\.sortOrder).max() ?? -1) + 1
                                modelContext.insert(ExerciseGroup(
                                    name: newGroupName.trimmingCharacters(in: .whitespacesAndNewlines),
                                    sortOrder: nextOrder
                                ))
                                newGroupName = ""
                                showingAddGroup = false
                            }
                            .disabled(newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
                .presentationDetents([.medium])
            }
        }
    }

    private func moveGroups(from source: IndexSet, to destination: Int) {
        var reordered = groups
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, g) in reordered.enumerated() {
            g.sortOrder = index
        }
    }

    private func deleteGroups(offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(groups[index])
        }
    }

    private func pushGroupToEnd(_ group: ExerciseGroup) {
        var reordered = groups.filter { $0.id != group.id }
        reordered.append(group)
        for (index, g) in reordered.enumerated() {
            g.sortOrder = index
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Exercise.self, ExerciseGroup.self], inMemory: true)
}
