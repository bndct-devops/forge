import Foundation
import SwiftUI
import ActivityKit

// MARK: - draft models (local until Finish posts them)

struct DraftSet: Identifiable {
    let id = UUID()
    var weight: Double
    var reps: Int
    var warmup = false
    var rpe: Double?
    var done = false
}

struct DraftExercise: Identifiable {
    let id = UUID()
    var exerciseId: Int?
    var name: String
    var muscleGroup: String?
    var restSeconds: Int
    var increment: Double
    var repMin: Int?
    var repMax: Int?
    var previous: String?          // "25×12 · 25×12 · 25×11 — 25 Jul"
    var supersetWithNext = false
    var sets: [DraftSet]
}

@MainActor
final class WorkoutStore: ObservableObject {
    @Published var name: String
    @Published var exercises: [DraftExercise] = []
    @Published var loading = true
    let startedAt = Date()

    init(routine: Routine?) {
        self.name = routine?.name ?? "Workout"
        Task { await load(routine: routine) }
    }

    private func load(routine: Routine?) async {
        guard let routine else {
            loading = false
            return
        }
        var out: [DraftExercise] = []
        for re in routine.exercises.sorted(by: { $0.position < $1.position }) {
            var weight = 20.0
            var reps = re.rep_min ?? 8
            var prev: String?
            var prevSets: [RecentSet] = []
            if let recent = try? await ForgeAPI.recent(exerciseId: re.exercise_id), let last = recent.first {
                prevSets = last.sets
                if let s = last.sets.first {
                    weight = s.weight ?? 0
                    reps = s.reps
                }
                let setsTxt = last.sets.map { "\(trim($0.weight ?? 0))×\($0.reps)" }.joined(separator: " · ")
                prev = "last: \(setsTxt)"
            }
            var sets: [DraftSet] = []
            for i in 0..<max(1, re.set_count) {
                let ps = i < prevSets.count ? prevSets[i] : prevSets.last
                sets.append(DraftSet(weight: ps?.weight ?? weight, reps: ps?.reps ?? reps))
            }
            out.append(DraftExercise(
                exerciseId: re.exercise_id,
                name: re.name,
                muscleGroup: re.muscle_group,
                restSeconds: re.rest_seconds ?? 120,
                increment: re.increment ?? 2.5,
                repMin: re.rep_min,
                repMax: re.rep_max,
                previous: prev,
                supersetWithNext: re.superset_with_next,
                sets: sets
            ))
        }
        exercises = out
        loading = false
    }

    func addExercise(_ ex: LibraryExercise) {
        exercises.append(DraftExercise(
            exerciseId: ex.id, name: ex.name, muscleGroup: ex.muscle_group,
            restSeconds: 120, increment: 2.5, repMin: nil, repMax: nil,
            previous: nil, sets: [DraftSet(weight: 20, reps: 8)]
        ))
        let idx = exercises.count - 1
        Task {
            if let recent = try? await ForgeAPI.recent(exerciseId: ex.id), let last = recent.first, let s = last.sets.first {
                exercises[idx].sets = [DraftSet(weight: s.weight ?? 20, reps: s.reps)]
                let setsTxt = last.sets.map { "\(trim($0.weight ?? 0))×\($0.reps)" }.joined(separator: " · ")
                exercises[idx].previous = "last: \(setsTxt)"
            }
        }
    }

    func addSet(to exIdx: Int) {
        let template = exercises[exIdx].sets.last ?? DraftSet(weight: 20, reps: 8)
        exercises[exIdx].sets.append(DraftSet(weight: template.weight, reps: template.reps))
    }

    var doneSets: Int { exercises.flatMap(\.sets).filter(\.done).count }
    var volume: Double {
        exercises.flatMap(\.sets).filter { $0.done && !$0.warmup }
            .reduce(0) { $0 + $1.weight * Double($1.reps) }
    }

    func buildLog() -> LogWorkout {
        let iso = ISO8601DateFormatter()
        var exs: [LogExercise] = []
        for ex in exercises {
            let sets = ex.sets.filter(\.done).map {
                LogSet(weight: $0.weight > 0 ? $0.weight : nil, reps: $0.reps,
                       is_warmup: $0.warmup ? true : nil, rpe: $0.rpe)
            }
            if !sets.isEmpty {
                exs.append(LogExercise(exercise_id: ex.exerciseId, name: ex.name, sets: sets))
            }
        }
        return LogWorkout(
            name: name,
            started_at: iso.string(from: startedAt),
            duration_seconds: Int(Date().timeIntervalSince(startedAt)),
            exercises: exs
        )
    }
}

func trim(_ v: Double) -> String {
    v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
}

// MARK: - rest timer + Live Activity

@MainActor
final class RestTimer: ObservableObject {
    @Published var endDate: Date?
    @Published var exercise = ""
    private var activity: Activity<RestActivityAttributes>?

    var active: Bool { endDate.map { $0 > Date() } ?? false }

    func start(seconds: Int, exercise: String, nextSet: Int, workoutName: String) {
        self.exercise = exercise
        endDate = Date().addingTimeInterval(TimeInterval(seconds))
        let state = RestActivityAttributes.ContentState(endDate: endDate!, exercise: exercise, nextSet: nextSet)
        if let activity {
            Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            activity = try? Activity.request(
                attributes: RestActivityAttributes(workoutName: workoutName),
                content: .init(state: state, staleDate: nil)
            )
        }
    }

    func extend(by seconds: Int) {
        guard let end = endDate else { return }
        endDate = end.addingTimeInterval(TimeInterval(seconds))
        if let activity, let endDate {
            let state = RestActivityAttributes.ContentState(endDate: endDate, exercise: exercise, nextSet: 0)
            Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
        }
    }

    func stop() {
        endDate = nil
        if let activity {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        activity = nil
    }
}
