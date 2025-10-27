import Foundation
import SwiftData

enum ExerciseCategory: String, Codable, CaseIterable, Identifiable {
    case chest, arm, shoulder, back, leg, core

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chest: return "Chest"
        case .arm: return "Arm"
        case .shoulder: return "Shoulder"
        case .back: return "Back"
        case .leg: return "Leg"
        case .core: return "Core"
        }
    }

    var systemImage: String {
        switch self {
        case .chest: return "heart.fill"
        case .arm: return "figure.strengthtraining.traditional"
        case .shoulder: return "figure.cooldown"
        case .back: return "rectangle.stack.fill"
        case .leg: return "figure.walk"
        case .core: return "circle.hexagonpath.fill"
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
    var lastPerformed: Date?
    var lastSessionWeights: [String] = []
    var lastSessionReps: [String] = []
    
    @Transient
    var daysLeft: Int {
        get {
            if lastPerformed  == nil {
                return 0
            }
            let diffTodayFromLastPerformed = Calendar.current.dateComponents([.day], from: lastPerformed ?? createdAt, to: Date()).day ?? 0
            return frequency - diffTodayFromLastPerformed
        }
    }
    
    init(id: UUID = UUID(), name: String, frequency:Int, category: ExerciseCategory = .chest, createdAt: Date = Date(), lastPerformed: Date? = nil, lastSessionWeights: [String] = [], lastSessionReps: [String] = []) {
        self.id = id
        self.name = name
        self.frequency = frequency
        self.category = category
        self.createdAt = createdAt
        self.lastPerformed = lastPerformed
        self.lastSessionWeights = lastSessionWeights
        self.lastSessionReps = lastSessionReps
    }
    
}
