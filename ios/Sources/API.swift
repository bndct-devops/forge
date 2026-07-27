import Foundation
import SwiftUI

// MARK: - wire models

struct Routine: Codable, Identifiable {
    let id: Int
    let name: String
    let last_performed: String?
    let exercises: [RoutineExercise]
}

struct RoutineExercise: Codable, Identifiable {
    var id: Int { exercise_id }
    let exercise_id: Int
    let name: String
    let muscle_group: String?
    let position: Int
    let set_count: Int
    let rest_seconds: Int?
    let superset_with_next: Bool
    let rep_min: Int?
    let rep_max: Int?
    let increment: Double?
}

struct LibraryExercise: Codable, Identifiable {
    let id: Int
    let name: String
    let muscle_group: String?
    let equipment: String?
    let is_custom: Bool
}

struct RecentWorkout: Codable {
    let workout_id: Int
    let name: String
    let date: String
    let sets: [RecentSet]
}

struct RecentSet: Codable {
    let weight: Double?
    let reps: Int
    let is_pr: Bool
    let rpe: Double?
}

// MARK: - log payload

struct LogSet: Codable {
    var weight: Double?
    var reps: Int
    var is_warmup: Bool?
    var rpe: Double?
}

struct LogExercise: Codable {
    var exercise_id: Int?
    var name: String
    var sets: [LogSet]
}

struct LogWorkout: Codable {
    var name: String
    var started_at: String
    var duration_seconds: Int
    var exercises: [LogExercise]
}

// MARK: - client

enum APIError: LocalizedError {
    case badURL
    case http(Int)
    var errorDescription: String? {
        switch self {
        case .badURL: return "invalid base URL"
        case .http(let code): return code == 401 ? "unauthorized — check the token" : "server returned \(code)"
        }
    }
}

struct ForgeAPI {
    static var baseURL: String { UserDefaults.standard.string(forKey: "forge_base_url") ?? "" }
    static var token: String { UserDefaults.standard.string(forKey: "forge_token") ?? "" }

    private static func request(_ path: String, method: String = "GET", body: Data? = nil) async throws -> Data {
        guard let url = URL(string: baseURL.trimmingCharacters(in: .init(charactersIn: "/")) + path) else {
            throw APIError.badURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if body != nil {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw APIError.http(code) }
        return data
    }

    static func ping() async throws {
        _ = try await request("/api/workouts?limit=1")
    }

    static func routines() async throws -> [Routine] {
        try JSONDecoder().decode([Routine].self, from: await request("/api/routines"))
    }

    static func exercises() async throws -> [LibraryExercise] {
        try JSONDecoder().decode([LibraryExercise].self, from: await request("/api/exercises"))
    }

    static func recent(exerciseId: Int) async throws -> [RecentWorkout] {
        try JSONDecoder().decode([RecentWorkout].self, from: await request("/api/exercises/\(exerciseId)/recent"))
    }

    static func log(_ workout: LogWorkout) async throws {
        let body = try JSONEncoder().encode(workout)
        _ = try await request("/api/workouts/log", method: "POST", body: body)
    }
}
