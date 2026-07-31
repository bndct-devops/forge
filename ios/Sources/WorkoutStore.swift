import Foundation
import SwiftUI
import Combine
import ActivityKit

// MARK: - draft models (local until Finish syncs them)

struct DraftSet: Identifiable, Codable {
    var id = UUID()
    var weight: Double?      // nil = empty field showing "kg" placeholder
    var reps: Int?
    var warmup = false
    var setType: String?   // "drop" | "failure"
    var rpe: Double?
    var done = false
    var amrap = false
    /// AMRAP sets: the prescribed floor, shown as a "3+" placeholder. The reps
    /// field itself starts EMPTY so the real number has to be entered.
    var plannedReps: Int?
    var previous: String?    // per-set reference column ("25 kg × 12" / prescription)
}

struct AmrapHint: Codable {
    var weight: Double
    var beatReps: Int
}

struct DraftExercise: Identifiable, Codable {
    var id = UUID()
    var exerciseId: Int
    var name: String
    var muscleGroup: String?
    var restSeconds: Int
    var increment: Double
    var repMin: Int?
    var repMax: Int?
    var supersetWithNext = false
    var suggestedWeight: Double?
    var suggestionKind: String?
    var amrapHint: AmrapHint?
    var note: String?
    var sets: [DraftSet]
}

/// Snapshot written to disk so an app kill mid-workout loses nothing.
struct PersistedDraft: Codable {
    var name: String
    var startedAt: Date
    var finishIntent: Date?
    var clientId: String
    var serverId: Int?
    var programId: Int?
    var programLiftId: Int?
    var exercises: [DraftExercise]
}

@MainActor
final class WorkoutStore: ObservableObject {
    @Published var name: String
    @Published var exercises: [DraftExercise] = []
    @Published var loading = true
    private(set) var startedAt = Date()
    /// Stamped on the FIRST finish attempt so failed syncs and retries all
    /// carry the real end time, not the retry time.
    var finishIntent: Date?
    private(set) var clientId = UUID().uuidString
    var serverId: Int?
    var programId: Int?
    var programLiftId: Int?
    let rest = RestTimer()  // lives with the workout so minimizing keeps the timer + Live Activity
    private var persistCancellable: AnyCancellable?

    // MARK: from a routine (local draft, created at finish via sync)

    init(routine: Routine?) {
        self.name = routine?.name ?? "Workout"
        startPersisting()
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
                // values only from real history; targets stay ghost placeholders
                sets.append(DraftSet(
                    weight: ps?.weight,
                    reps: ps?.reps,
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
                // PREVIOUS column shows real history; the prescription lives
                // in the prefilled values (PWA semantics).
                let prevText: String?
                if let ps = se.previous_sets, i < ps.count {
                    prevText = "\(trim(ps[i].weight ?? 0)) kg × \(ps[i].reps)"
                } else {
                    prevText = nil
                }
                // The AMRAP set must not arrive pre-answered — prefilling its
                // prescribed floor makes "stop at 3" one tap away.
                let isAmrap = i < prescribed.count ? prescribed[i].amrap : false
                sets.append(DraftSet(
                    weight: s.weight,
                    reps: isAmrap ? nil : s.reps,
                    warmup: s.is_warmup ?? false,
                    amrap: isAmrap,
                    plannedReps: isAmrap ? s.reps : nil,
                    previous: prevText
                ))
            }
            if sets.isEmpty {
                sets = [DraftSet()]
            }
            let amrap = server.amrap_target.flatMap { t in
                t.we_id == se.id ? AmrapHint(weight: t.weight, beatReps: t.beat_reps) : nil
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
                suggestedWeight: se.suggested_weight,
                suggestionKind: se.suggestion_kind,
                amrapHint: amrap,
                note: se.note?.isEmpty == false ? se.note : nil,
                sets: sets
            ))
        }
        exercises = out
        loading = false
        startPersisting()
    }

    // MARK: from a persisted draft (app was killed mid-workout)

    init(restored draft: PersistedDraft) {
        self.name = draft.name
        self.startedAt = draft.startedAt
        self.finishIntent = draft.finishIntent
        self.clientId = draft.clientId
        self.serverId = draft.serverId
        self.programId = draft.programId
        self.programLiftId = draft.programLiftId
        self.exercises = draft.exercises
        self.loading = false
        startPersisting()
    }

    // MARK: persistence

    private static var draftURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("forge-draft.json")
    }

    static func loadPersisted() -> PersistedDraft? {
        guard let data = try? Data(contentsOf: draftURL) else { return nil }
        return try? JSONDecoder().decode(PersistedDraft.self, from: data)
    }

    static func clearPersisted() {
        try? FileManager.default.removeItem(at: draftURL)
    }

    private func startPersisting() {
        // objectWillChange fires before every mutation; the debounce writes
        // the settled state shortly after.
        persistCancellable = objectWillChange
            .debounce(for: .milliseconds(400), scheduler: DispatchQueue.main)
            .sink { [weak self] in self?.persist() }
    }

    private func persist() {
        guard !loading else { return }
        let draft = PersistedDraft(
            name: name, startedAt: startedAt, finishIntent: finishIntent,
            clientId: clientId,
            serverId: serverId, programId: programId, programLiftId: programLiftId,
            exercises: exercises
        )
        let dir = Self.draftURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(draft) {
            try? data.write(to: Self.draftURL, options: .atomic)
        }
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

    func moveExercise(at index: Int, offset: Int) {
        let target = index + offset
        guard exercises.indices.contains(index), exercises.indices.contains(target) else { return }
        exercises.swapAt(index, target)
    }

    func toggleSuperset(at index: Int) {
        guard exercises.indices.contains(index), index < exercises.count - 1 else { return }
        exercises[index].supersetWithNext.toggle()
    }

    /// Replace the exercise identity, keeping the logged sets (PWA swap
    /// semantics); the PREVIOUS ghosts refresh from the new lift's history.
    func swapExercise(at index: Int, with ex: LibraryExercise) {
        guard exercises.indices.contains(index) else { return }
        exercises[index].exerciseId = ex.id
        exercises[index].name = ex.name
        exercises[index].muscleGroup = ex.muscle_group
        exercises[index].suggestedWeight = nil
        exercises[index].suggestionKind = nil
        exercises[index].amrapHint = nil
        exercises[index].note = nil
        Task {
            let prev = (try? await ForgeAPI.recent(exerciseId: ex.id))?.first?.sets ?? []
            guard exercises.indices.contains(index), exercises[index].exerciseId == ex.id else { return }
            for i in exercises[index].sets.indices {
                let ps = i < prev.count ? prev[i] : nil
                exercises[index].sets[i].previous = ps.map { "\(trim($0.weight ?? 0)) kg × \($0.reps)" }
            }
        }
    }

    /// The PWA's warm-up ramp: 40/60/80% of the heaviest weight in play,
    /// snapped to 2.5 and deduped, inserted before the working sets.
    func warmupRamp(at index: Int) -> [(weight: Double, reps: Int)] {
        guard exercises.indices.contains(index) else { return [] }
        let ex = exercises[index]
        let filled = ex.sets.compactMap(\.weight).filter { $0 > 0 }
        guard let target = filled.max() ?? ex.suggestedWeight, target > 0 else { return [] }
        let step = 2.5
        var seen = Set<Double>()
        var out: [(Double, Int)] = []
        for (pct, reps) in [(0.4, 10), (0.6, 6), (0.8, 3)] {
            let w = max(step, ((target * pct) / step).rounded() * step)
            if w < target, !seen.contains(w) {
                seen.insert(w)
                out.append((w, reps))
            }
        }
        return out
    }

    func addWarmupSets(at index: Int) {
        let ramp = warmupRamp(at: index)
        guard !ramp.isEmpty, exercises.indices.contains(index) else { return }
        let sets = ramp.map { DraftSet(weight: $0.weight, reps: $0.reps, warmup: true, done: false) }
        exercises[index].sets.insert(contentsOf: sets, at: 0)
    }

    func setNote(at index: Int, text: String) {
        guard exercises.indices.contains(index) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        exercises[index].note = trimmed.isEmpty ? nil : trimmed
        let id = exercises[index].exerciseId
        Task { try? await ForgeAPI.putExerciseNote(id: id, text: trimmed) }
    }

    func removeSet(exIdx: Int, setIdx: Int) {
        guard exercises[exIdx].sets.indices.contains(setIdx) else { return }
        exercises[exIdx].sets.remove(at: setIdx)
    }

    func addSet(to exIdx: Int) {
        let template = exercises[exIdx].sets.last
        exercises[exIdx].sets.append(DraftSet(weight: template?.weight, reps: template?.reps))
    }

    /// The lock-screen ✓: complete the FIRST undone set. Empty fields fill
    /// with the best guess — the previous set of the exercise, then the rep
    /// minimum / suggested weight — because "set done" from the lock screen
    /// means "I did what was planned"; numbers stay editable in the table.
    func completeNextSet() {
        for exIdx in exercises.indices {
            guard let setIdx = exercises[exIdx].sets.firstIndex(where: { !$0.done }) else { continue }
            let ex = exercises[exIdx]
            var set = ex.sets[setIdx]
            // an AMRAP set's rep count is the whole point — never guess it
            if set.amrap, set.reps == nil { return }
            let prevDone = ex.sets[..<setIdx].last { $0.done && $0.reps != nil }
            if set.reps == nil {
                set.reps = prevDone?.reps ?? ex.repMin
            }
            guard set.reps != nil else { return } // nothing sensible to record
            if set.weight == nil {
                set.weight = prevDone?.weight ?? ex.suggestedWeight
            }
            set.done = true
            exercises[exIdx].sets[setIdx] = set
            finishIntent = nil
            if !ex.supersetWithNext, ex.restSeconds > 0 {
                rest.start(seconds: ex.restSeconds, exercise: ex.name,
                           nextSet: setIdx + 2, workoutName: name)
            }
            return
        }
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
            var sets: [SyncSet] = []
            for s in ex.sets {
                guard s.done, let reps = s.reps else { continue }
                sets.append(SyncSet(position: sets.count, weight: s.weight, reps: reps,
                                    is_completed: true, is_warmup: s.warmup,
                                    set_type: s.setType, rpe: s.rpe))
            }
            if !sets.isEmpty {
                exs.append(SyncExercise(
                    exercise_id: ex.exerciseId, position: i,
                    rest_seconds: ex.restSeconds, superset_with_next: ex.supersetWithNext,
                    rep_min: ex.repMin, rep_max: ex.repMax, sets: sets
                ))
            }
        }
        if finished, finishIntent == nil {
            finishIntent = Date()
        }
        return SyncWorkout(
            id: serverId, client_id: clientId, name: name, notes: nil,
            started_at: iso.string(from: startedAt),
            finished_at: finished ? iso.string(from: finishIntent ?? Date()) : nil,
            program_id: programId, program_lift_id: programLiftId,
            exercises: exs
        )
    }

    func discard() async {
        rest.stop()
        Self.clearPersisted()
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
        LocalNotifications.requestAuthorization()
        LocalNotifications.scheduleRestDone(at: endDate!, exercise: exercise, nextSet: nextSet)
    }

    func adjust(by seconds: Int) {
        guard let end = endDate else { return }
        let newEnd = end.addingTimeInterval(TimeInterval(seconds))
        if newEnd <= Date() {
            stop()
            return
        }
        endDate = newEnd
        if let activity, let endDate {
            let state = RestActivityAttributes.ContentState(endDate: endDate, exercise: exercise, nextSet: 0)
            Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
        }
        LocalNotifications.scheduleRestDone(at: newEnd, exercise: exercise, nextSet: 0)
    }

    func stop() {
        endDate = nil
        if let activity {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
        activity = nil
        LocalNotifications.cancelRestDone()
    }
}
