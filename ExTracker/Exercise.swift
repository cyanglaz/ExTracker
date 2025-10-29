import Foundation
import _SwiftData_SwiftUI
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
    
    init(id: UUID = UUID(), name: String, frequency: Int, category: ExerciseCategory = .chest, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.frequency = frequency
        self.category = category
        self.createdAt = createdAt
    }
    
}

