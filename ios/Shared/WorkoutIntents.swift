import AppIntents
import ActivityKit
import Foundation

/// Hooks the running app registers so Live Activity buttons act on the live
/// workout state (rest timer, store, persistence). When the app process was
/// cold-launched just to run an intent, the hooks are unset and the intents
/// fall back to mutating the persisted draft on disk.
enum IntentBridge {
    @MainActor static var completeSet: (() -> Void)?
    @MainActor static var adjustRest: ((Int) -> Void)?
    @MainActor static var skipRest: (() -> Void)?
}

/// Mark the next planned set done and restart the rest timer — the lock
/// screen ✓ button.
struct CompleteSetIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Complete set"
    static let description = IntentDescription("Marks the next set done and restarts the rest timer.")

    @MainActor
    func perform() async throws -> some IntentResult {
        if let hook = IntentBridge.completeSet {
            hook()
        } else {
            DraftFallback.completeNextSet()
        }
        return .result()
    }
}

/// Adjust the running rest countdown (±seconds).
struct AdjustRestIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Adjust rest"
    static let description = IntentDescription("Adds or removes rest time.")

    @Parameter(title: "Seconds")
    var seconds: Int

    init() {}
    init(seconds: Int) {
        self.seconds = seconds
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        if let hook = IntentBridge.adjustRest {
            hook(seconds)
        } else {
            DraftFallback.adjustRest(by: seconds)
        }
        return .result()
    }
}

/// Skip the rest countdown entirely.
struct SkipRestIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Skip rest"
    static let description = IntentDescription("Ends the rest timer.")

    @MainActor
    func perform() async throws -> some IntentResult {
        if let hook = IntentBridge.skipRest {
            hook()
        } else {
            DraftFallback.skipRest()
        }
        return .result()
    }
}

/// JSON-level draft mutations for when the app's object graph isn't up —
/// operates on the persisted draft file and the Live Activity directly.
enum DraftFallback {
    private static var draftURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("forge-draft.json")
    }

    @MainActor
    static func completeNextSet() {
        guard let data = try? Data(contentsOf: draftURL),
              var draft = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var exercises = draft["exercises"] as? [[String: Any]] else { return }
        var restSeconds = 120
        var exerciseName = ""
        var nextSetNumber = 0
        var mutated = false
        outer: for (ei, var ex) in exercises.enumerated() {
            guard var sets = ex["sets"] as? [[String: Any]] else { continue }
            for (si, var set) in sets.enumerated() {
                let done = set["done"] as? Bool ?? false
                guard !done else { continue }
                // an AMRAP set's rep count is the whole point — never guess it
                if set["amrap"] as? Bool == true, set["reps"] as? Int == nil { break outer }
                // fill blanks from the previous done set / plan, like the app
                let prevDone = sets[..<si].last {
                    ($0["done"] as? Bool ?? false) && $0["reps"] is Int
                }
                if set["reps"] as? Int == nil {
                    set["reps"] = prevDone?["reps"] as? Int ?? ex["repMin"] as? Int
                }
                guard set["reps"] as? Int != nil else { break outer }
                if set["weight"] as? Double == nil, !(set["weight"] is NSNumber) {
                    set["weight"] = prevDone?["weight"] as? Double
                        ?? ex["suggestedWeight"] as? Double
                }
                set["done"] = true
                sets[si] = set
                ex["sets"] = sets
                exercises[ei] = ex
                restSeconds = ex["restSeconds"] as? Int ?? 120
                exerciseName = ex["name"] as? String ?? ""
                nextSetNumber = si + 2
                mutated = true
                break outer
            }
        }
        guard mutated else { return }
        draft["exercises"] = exercises
        if let out = try? JSONSerialization.data(withJSONObject: draft) {
            try? out.write(to: draftURL, options: .atomic)
        }
        if restSeconds > 0 {
            updateActivity(endDate: Date().addingTimeInterval(TimeInterval(restSeconds)),
                           exercise: exerciseName, nextSet: nextSetNumber)
        }
    }

    @MainActor
    static func adjustRest(by seconds: Int) {
        guard let activity = Activity<RestActivityAttributes>.activities.first else { return }
        let state = activity.content.state
        let newEnd = state.endDate.addingTimeInterval(TimeInterval(seconds))
        if newEnd <= Date() {
            skipRest()
            return
        }
        updateActivity(endDate: newEnd, exercise: state.exercise, nextSet: state.nextSet)
    }

    @MainActor
    static func skipRest() {
        for activity in Activity<RestActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    @MainActor
    static func updateActivity(endDate: Date, exercise: String, nextSet: Int) {
        guard let activity = Activity<RestActivityAttributes>.activities.first else { return }
        let state = RestActivityAttributes.ContentState(
            endDate: endDate, exercise: exercise, nextSet: nextSet)
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }
}
