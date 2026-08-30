import Foundation
import SwiftData

@Model
final class ExerciseGroup {
    var id: UUID
    var name: String
    /// User-defined position in the group list. Lower values appear first.
    var sortOrder: Int
    /// Ordered list of exercise IDs belonging to this group.
    var exerciseIDs: [UUID]

    init(id: UUID = UUID(), name: String, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
        self.exerciseIDs = []
    }
}
