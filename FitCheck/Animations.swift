import Foundation
import SwiftUI

enum AnimationType: String, CaseIterable {
    case running = "Running"
    case walking = "Walking"
    case sitting = "Sitting"
    case waving = "Waving"
    case idle = "Idle"
}
extension Notification.Name {
    /// Fired when the user taps “🏃” to switch animations.
    static let animationSelected = Notification.Name("animationSelected")
}
