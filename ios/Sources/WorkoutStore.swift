import Foundation
import SwiftUI
import ActivityKit

// MARK: - draft models (local until Finish syncs them)

struct DraftSet: Identifiable {
    let id = UUID()
    var weight: Double?      // nil = empty field showing "kg" placeholder
    var reps: Int?
    var warmup = false
    var rpe: Double?
    var done = false
    var amrap = false
    var previous: String?    // per-set reference column ("25 kg × 12" / prescription)
}

struct DraftExercise: Identifiable {
    let id = UUID()
    var exerciseId: Int
    var name: String
    var muscleGroup: String?
    var restSeconds: Int
    var increment: Double
    var repMin: Int?
    var repMax: Int?
    var supersetWithNext = false
    var sets: [DraftSet]
}

@MainActor
final class WorkoutStore: ObservableObject {
    @Published var name: String
    @Published var exercises: [DraftExercise] = []
    @Published var loading = true
    let startedAt = Date()
    let clientId = UUID().uuidString
    var serverId: Int?
    var programId: Int?
    var programLiftId: Int?
    let rest = RestTimer()  // lives with the workout so minimizing keeps the timer + Live Activity

    // MARK: from a routine (local draft, created at finish via sync)

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
            var prevSets: [RecentSet] = []
            if let recent = try? await ForgeAPI.recent(exerciseId: re.exercise_id), let last = recent.first {
                prevSets = last.sets
            }
            var sets: [DraftSet] = []
            for i in 0..<max(1, re.set_count) {
                let ps = i < prevSets.count ? prevSets[i] : nil
                sets.append(DraftSet(
                    weight: ps?.weight,
                    reps: ps?.reps ?? re.rep_min,
                    previous: ps.map { "\(trim($0.weight ?? 0)) kg × \($0.reps)" }
                ))
            }
            out.append(DraftExercise(
                exerciseId: re.exercise_id,
                name: re.name,
                muscleGroup: re.muscle_group,
                restSeconds: re.rest_seconds ?? 120,
                increment: re.increment ?? 2.5,
                repMin: re.rep_min,
                repMax: re.rep_max,
                supersetWithNext: re.superset_with_next,
                sets: sets
            ))
        }
        exercises = out
        loading = false
    }

    // MARK: from a program start (server-side active workout)

    init(server: ServerWorkout) {
        self.name = server.name
        self.serverId = server.id
        self.programId = server.program_id
        self.programLiftId = server.program_lift_id
        var out: [DraftExercise] = []
        for (exIdx, se) in server.exercises.enumerated() {
            let prescribed = exIdx == 0 ? (server.program?.sets ?? []) : []
            var sets: [DraftSet] = []
            for (i, s) in se.sets.enumerated() {
                let p = i < prescribed.count ? prescribed[i] : nil
                let prevText: String?
                if let p {
                    prevText = "\(trim(p.weight)) × \(p.reps)\(p.amrap ? "+" : "")"
                } else if let ps = se.previous_sets, i < ps.count {
                    prevText = "\(trim(ps[i].weight ?? 0)) kg × \(ps[i].reps)"
                } else {
                    prevText = nil
                }
                sets.append(DraftSet(
                    weight: s.weight,
                    reps: s.reps,
                    warmup: s.is_warmup ?? false,
                    amrap: p?.amrap ?? false,
                    previous: prevText
                ))
            }
            if sets.isEmpty {
                sets = [DraftSet()]
            }
            out.append(DraftExercise(
                exerciseId: se.exercise_id,
                name: se.name,
                muscleGroup: se.muscle_group,
                restSeconds: se.rest_seconds ?? 150,
                increment: 2.5,
                repMin: se.rep_min,
                repMax: se.rep_max,
                supersetWithNext: se.superset_with_next ?? false,
                sets: sets
            ))
        }
        exercises = out
        loading = false
    }

    // MARK: editing

    func addExercise(_ ex: LibraryExercise) {
        exercises.append(DraftExercise(
            exerciseId: ex.id, name: ex.name, muscleGroup: ex.muscle_group,
            restSeconds: 120, increment: 2.5, repMin: nil, repMax: nil,
            sets: [DraftSet()]
        ))
        let idx = exercises.count - 1
        Task {
            if let recent = try? await ForgeAPI.recent(exerciseId: ex.id), let last = recent.first, let s = last.sets.first {
                exercises[idx].sets = [DraftSet(
                    weight: s.weight, reps: s.reps,
                    previous: "\(trim(s.weight ?? 0)) kg × \(s.reps)"
                )]
            }
        }
    }

    func removeExercise(at index: Int) {
        exercises.remove(at: index)
    }

    func addSet(to exIdx: Int) {
        let template = exercises[exIdx].sets.last
        exercises[exIdx].sets.append(DraftSet(weight: template?.weight, reps: template?.reps))
    }

    var doneSets: Int { exercises.flatMap(\.sets).filter(\.done).count }
    var volume: Double {
        exercises.flatMap(\.sets).filter { $0.done && !$0.warmup }
            .reduce(0) { $0 + ($1.weight ?? 0) * Double($1.reps ?? 0) }
    }

    // MARK: finish / discard

    func buildSync(finished: Bool) -> SyncWorkout {
        let iso = ISO8601DateFormatter()
        var exs: [SyncExercise] = []
        for (i, ex) in exercises.enumerated() {
            let sets = ex.sets.compactMap { s -> SyncSet? in
                guard s.done, let reps = s.reps else { return nil }
                return SyncSet(weight: s.weight, reps: reps, is_completed: true,
                               is_warmup: s.warmup, set_type: nil, rpe: s.rpe)
            }
            if !sets.isEmpty {
                exs.append(SyncExercise(
                    exercise_id: ex.exerciseId, position: i,
                    rest_seconds: ex.restSeconds, superset_with_next: ex.supersetWithNext,
                    rep_min: ex.repMin, rep_max: ex.repMax, sets: sets
                ))
            }
        }
        return SyncWorkout(
            id: serverId, client_id: clientId, name: name, notes: nil,
            started_at: iso.string(from: startedAt),
            finished_at: finished ? iso.string(from: Date()) : nil,
            program_id: programId, program_lift_id: programLiftId,
            exercises: exs
        )
    }

    func discard() async {
        rest.stop()
        if let serverId {
            try? await ForgeAPI.deleteWorkout(id: serverId)
        }
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
