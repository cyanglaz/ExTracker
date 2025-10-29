import Foundation
import SwiftData

enum ExerciseCategory: String, Codable, CaseIterable, Identifiable {
    case chest, arm, shoulder, back, leg, core, cardio

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chest: return "Chest"
        case .arm: return "Arm"
        case .shoulder: return "Shoulder"
        case .back: return "Back"
        case .leg: return "Leg"
        case .core: return "Core"
        case .cardio: return "Cardio"
        }
    }

    var systemImage: String {
        switch self {
        case .chest: return "figure.archery"
        case .arm: return "figure.strengthtraining.traditional"
        case .shoulder: return "figure.mixed.cardio"
        case .back: return "figure.yoga"
        case .leg: return "figure.strengthtraining.functional"
        case .core: return "figure.core.training"
        case .cardio: return "heart.fill"
        }
    }
}

@Model
final class Exercise {
        
    var id: UUID
    var name: String
    var category: ExerciseCategory
    var frequency: Int
    var createdAt: Date

    @Transient
    var daysLeft: Int {
        get {
            guard let latestPerformedDate else { return 0 }
            let diff = Calendar.current.dateComponents([.day], from: latestPerformedDate, to: Date()).day ?? 0
            return frequency - diff
        }
    }

    @Transient
    var latestPerformedDate: Date? {
        // Fetch on demand from ExerciseSessionModel
        var records: [ExerciseSessionRecord] = Query(
            filter: #Predicate<ExerciseSessionRecord> { $0.exerciseID == exerciseID },
            sort: [SortDescriptor(\.date, order: .reverse)]
        )
    }

    @Transient
    var latestSessionWeights: [String] {
        // Fetch on demand from ExerciseSessionModel
        ExerciseSessionModel.latestSession(forExerciseID: id)?.weights ?? []
    }

    @Transient
    var latestSessionReps: [String] {
        // Fetch on demand from ExerciseSessionModel
        ExerciseSessionModel.latestSession(forExerciseID: id)?.reps ?? []
    }
    
    init(id: UUID = UUID(), name: String, frequency: Int, category: ExerciseCategory = .chest, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.frequency = frequency
        self.category = category
        self.createdAt = createdAt
    }
    
}

