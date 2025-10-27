import SwiftUI

extension ExerciseCategory {
    var displayColor: Color {
        switch self {
        case .chest:
            return .pink
        case .back:
            return .blue
        case .leg:
            return .green
        case .shoulder:
            return .orange
        case .arm:
            return .purple
        case .core:
            return .yellow
        case .cardio:
            return .red
        default:
            return .gray
        }
    }
}
