import Foundation
import SwiftData

@Model
final class ExerciseSessionRecord {
    var id: UUID
    var exerciseID: UUID
    var date: Date
    var weights: [String]
    var reps: [String]

    init(id: UUID = UUID(), exerciseID: UUID, date: Date = Date(), weights: [String] = [], reps: [String] = []) {
        self.id = id
        self.exerciseID = exerciseID
        self.date = date
        self.weights = weights
        self.reps = reps
    }
}
