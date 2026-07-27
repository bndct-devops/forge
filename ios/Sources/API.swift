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

// MARK: - programs

struct Program: Codable, Identifiable {
    let id: Int
    let name: String
    let scheme_name: String
    let current_week: Int
    let cycle_number: Int?
    let cycle_length: Int?
    let lifts: [ProgramLift]?
    let next: ProgramNext?
}

struct ProgramLift: Codable {
    let id: Int
    let routine_name: String?
}

struct ProgramNext: Codable {
    let lift_id: Int
    let exercise_id: Int
    let exercise_name: String
    let week: Int
    let sets: [PrescribedSet]
}

struct PrescribedSet: Codable {
    let weight: Double
    let reps: Int
    let amrap: Bool
}

// MARK: - server workout (program start / active flow)

struct ServerWorkout: Codable {
    let id: Int
    let name: String
    let program_id: Int?
    let program_lift_id: Int?
    let exercises: [ServerExercise]
    let program: ProgramStartInfo?
    let amrap_target: AmrapTarget?
}

struct AmrapTarget: Codable {
    let we_id: Int
    let weight: Double
    let beat_reps: Int
}

struct ProgramStartInfo: Codable {
    let week: Int
    let sets: [PrescribedSet]
}

struct ServerExercise: Codable {
    let id: Int
    let exercise_id: Int
    let name: String
    let muscle_group: String?
    let rest_seconds: Int?
    let superset_with_next: Bool?
    let rep_min: Int?
    let rep_max: Int?
    let suggested_weight: Double?
    let suggestion_kind: String?
    let note: String?
    let previous_sets: [RecentSet]?
    let sets: [ServerSet]
}

struct ServerSet: Codable {
    let weight: Double?
    let reps: Int?
    let is_warmup: Bool?
}

// MARK: - sync document (the PWA's offline finish path — advances programs)

struct SyncSet: Codable {
    var weight: Double?
    var reps: Int
    var is_completed: Bool
    var is_warmup: Bool
    var set_type: String?
    var rpe: Double?
}

struct SyncExercise: Codable {
    var exercise_id: Int
    var position: Int
    var rest_seconds: Int?
    var superset_with_next: Bool
    var rep_min: Int?
    var rep_max: Int?
    var sets: [SyncSet]
}

struct SyncWorkout: Codable {
    var id: Int?
    var client_id: String
    var name: String
    var notes: String?
    var started_at: String
    var finished_at: String?
    var program_id: Int?
    var program_lift_id: Int?
    var exercises: [SyncExercise]
}

// MARK: - program preview

struct PreviewSession: Codable, Identifiable {
    var id: Int { offset }
    let offset: Int
    let week: Int
    let cycle_number: Int
    let exercise_id: Int
    let exercise_name: String
    let training_max: Double
    let sets: [PrescribedSet]
    let beat_reps: Int?
    let routine_name: String?
    let accessories: [PreviewAccessory]?
}

struct PreviewAccessory: Codable {
    let name: String
    let set_count: Int
    let rep_min: Int?
    let rep_max: Int?
}

// MARK: - workout history

struct WorkoutListItem: Codable, Identifiable {
    let id: Int
    let name: String
    let started_at: String
    let finished_at: String?
    let duration_seconds: Int?
    let exercise_summaries: [String]?
    let total_volume: Double?
    let total_sets: Int?
    let pr_count: Int?
}

struct WorkoutFull: Codable {
    let id: Int
    let name: String
    let notes: String?
    let started_at: String
    let finished_at: String?
    let duration_seconds: Int?
    let total_volume: Double?
    let total_sets: Int?
    let pr_count: Int?
    let exercises: [WorkoutFullExercise]
}

struct WorkoutFullExercise: Codable {
    let name: String
    let muscle_group: String?
    let sets: [WorkoutFullSet]
}

struct WorkoutFullSet: Codable {
    let weight: Double?
    let reps: Int?
    let is_warmup: Bool?
    let is_pr: Bool?
    let set_type: String?
    let rpe: Double?
}

// MARK: - exercise detail stats

struct ExerciseStats: Codable {
    let exercise: LibraryExercise
    let note: String?
    let variations: [ExerciseVariation]
    let records: ExerciseRecords?
    let chart: [ExerciseChartPoint]
    let history: [ExerciseHistoryEntry]
}

struct ExerciseVariation: Codable, Identifiable {
    let id: Int
    let name: String
}

struct ExerciseRecords: Codable {
    let best_weight: RecordSetRef?
    let best_1rm: Record1RMRef?
    let best_volume_set: RecordVolumeRef?
    let total_reps: Int?
    let total_volume: Double?
    let times_performed: Int?
}

struct RecordSetRef: Codable {
    let weight: Double
    let reps: Int
}

struct Record1RMRef: Codable {
    let value: Double
    let weight: Double?
    let reps: Int?
}

struct RecordVolumeRef: Codable {
    let value: Double
    let weight: Double?
    let reps: Int?
}

struct ExerciseChartPoint: Codable {
    let date: String
    let best_1rm: Double?
    let best_weight: Double?
    let volume: Double?
    let avg_rpe: Double?
}

struct ExerciseHistoryEntry: Codable, Identifiable {
    var id: Int { workout_id }
    let workout_id: Int
    let workout_name: String
    let date: String
    let sets: [RecentSet]
}

// MARK: - stats

struct StatsTotals: Codable {
    let workouts: Int
    let volume: Double
    let sets: Int
    let prs: Int
    let since: String?
}

struct StatsWeek: Codable, Identifiable {
    var id: String { week_start }
    let week_start: String
    let volume: Double
    let workouts: Int
}

struct StatsResponse: Codable {
    let totals: StatsTotals
    let streak_weeks: Int
    let weeks: [StatsWeek]
}

struct RecordBestWeight: Codable {
    let weight: Double
    let reps: Int
}

struct RecordBest1RM: Codable {
    let value: Double
}

struct RecordEntry: Codable, Identifiable {
    var id: Int { exercise_id }
    let exercise_id: Int
    let name: String
    let muscle_group: String?
    let best_weight: RecordBestWeight?
    let best_1rm: RecordBest1RM?
    let sessions: Int
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

    static func programs() async throws -> [Program] {
        try JSONDecoder().decode([Program].self, from: await request("/api/programs"))
    }

    static func startProgramWorkout(programId: Int) async throws -> ServerWorkout {
        try JSONDecoder().decode(ServerWorkout.self,
                                 from: await request("/api/programs/\(programId)/start-workout", method: "POST"))
    }

    static func deleteWorkout(id: Int) async throws {
        _ = try await request("/api/workouts/\(id)", method: "DELETE")
    }

    static func sync(_ doc: SyncWorkout) async throws {
        let body = try JSONEncoder().encode(doc)
        _ = try await request("/api/workouts/sync", method: "PUT", body: body)
    }

    static func workouts(limit: Int = 20, offset: Int = 0) async throws -> [WorkoutListItem] {
        try JSONDecoder().decode([WorkoutListItem].self,
                                 from: await request("/api/workouts?limit=\(limit)&offset=\(offset)"))
    }

    static func workoutDetail(id: Int) async throws -> WorkoutFull {
        try JSONDecoder().decode(WorkoutFull.self, from: await request("/api/workouts/\(id)"))
    }

    static func patchWorkout(id: Int, name: String?, notes: String?) async throws {
        var payload: [String: String] = [:]
        if let name { payload["name"] = name }
        if let notes { payload["notes"] = notes }
        let body = try JSONSerialization.data(withJSONObject: payload)
        _ = try await request("/api/workouts/\(id)", method: "PATCH", body: body)
    }

    static func exerciseStats(id: Int) async throws -> ExerciseStats {
        try JSONDecoder().decode(ExerciseStats.self, from: await request("/api/exercises/\(id)/stats"))
    }

    static func programPreview(id: Int) async throws -> [PreviewSession] {
        try JSONDecoder().decode([PreviewSession].self, from: await request("/api/programs/\(id)/preview"))
    }

    static func stats() async throws -> StatsResponse {
        try JSONDecoder().decode(StatsResponse.self, from: await request("/api/stats"))
    }

    static func records() async throws -> [RecordEntry] {
        try JSONDecoder().decode([RecordEntry].self, from: await request("/api/stats/records"))
    }
}
