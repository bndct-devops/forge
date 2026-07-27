import Foundation
import ActivityKit

/// Rest-timer Live Activity payload — lock screen + Dynamic Island countdown.
struct RestActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var endDate: Date
        var exercise: String
        var nextSet: Int
    }
    var workoutName: String
}
