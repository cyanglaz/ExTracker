import SwiftData
import Foundation

// V0: the schema that was originally shipped — Exercise had no sortOrder.
enum ExerciseSchemaV0: VersionedSchema {
    static var versionIdentifier = Schema.Version(0, 0, 0)
    static var models: [any PersistentModel.Type] {
        [ExerciseSchemaV0.Exercise.self, ExerciseSchemaV0.ExerciseSessionRecord.self]
    }

    @Model final class Exercise {
        var id: UUID
        var name: String
        var category: ExerciseCategory
        var createdAt: Date

        init(id: UUID = UUID(), name: String,
             category: ExerciseCategory = .chest, createdAt: Date = Date()) {
            self.id = id
            self.name = name
            self.category = category
            self.createdAt = createdAt
        }
    }

    @Model final class ExerciseSessionRecord {
        var id: UUID
        var exerciseID: UUID
        var date: Date
        var weights: [String]
        var reps: [String]

        init(id: UUID = UUID(), exerciseID: UUID, date: Date = Date(),
             weights: [String] = [], reps: [String] = []) {
            self.id = id
            self.exerciseID = exerciseID
            self.date = date
            self.weights = weights
            self.reps = reps
        }
    }
}

// V1: current schema — sortOrder added as Int? (nullable so migration succeeds),
// ExerciseGroup added as a new table.
enum ExerciseSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Exercise.self, ExerciseSessionRecord.self, ExerciseGroup.self]
    }
}

enum ExerciseMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [ExerciseSchemaV0.self, ExerciseSchemaV1.self]
    }
    static var stages: [MigrationStage] { [migrateV0toV1] }

    static let migrateV0toV1 = MigrationStage.custom(
        fromVersion: ExerciseSchemaV0.self,
        toVersion: ExerciseSchemaV1.self,
        willMigrate: nil,
        didMigrate: { context in
            // Assign sequential sortOrder to exercises that were migrated without one.
            let all = try context.fetch(FetchDescriptor<Exercise>())
            let needsOrder = all.filter { $0.sortOrder == nil }
                                .sorted { $0.createdAt < $1.createdAt }
            for (index, exercise) in needsOrder.enumerated() {
                exercise.sortOrder = index
            }
            try context.save()
        }
    )
}
