import Foundation

/// Data the home-screen widget renders — written by the app into the shared
/// App Group container whenever fresh program/stats data arrives.
struct WidgetSnapshot: Codable {
    var programName: String?
    var nextExercise: String?
    var prescription: String?
    var accessory: String?
    var week: Int?
    var streakWeeks: Int
    var weekWorkouts: Int
    var weeklyGoal: Int
    var updated: Date

    static var url: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.dev.bndct.forge")?
            .appendingPathComponent("widget-snapshot.json")
    }

    static func load() -> WidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save() {
        guard let url = Self.url, let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
