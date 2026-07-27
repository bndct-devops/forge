import Foundation
import HealthKit

/// Apple Health integration, scoped by design: finished workouts flow OUT
/// (activity rings), body weight flows IN (Measurements). Everything else
/// belongs to Loom.
enum HealthSync {
    private static let store = HKHealthStore()
    private static let bodyMass = HKQuantityType(.bodyMass)

    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "health_sync") }
        set { UserDefaults.standard.set(newValue, forKey: "health_sync") }
    }

    static var available: Bool { HKHealthStore.isHealthDataAvailable() }

    static func requestAuthorization() async -> Bool {
        guard available else { return false }
        do {
            try await store.requestAuthorization(
                toShare: [HKObjectType.workoutType()],
                read: [bodyMass]
            )
            return true
        } catch {
            return false
        }
    }

    /// Save a finished session as a strength-training workout.
    static func saveWorkout(start: Date, end: Date) async {
        guard enabled, available, end > start else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        do {
            try await builder.beginCollection(at: start)
            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
        } catch {
            // Health write failing must never affect the Forge save
        }
    }

    /// Newest Health body-mass sample → Forge Measurements, deduped by time.
    static func importLatestWeight() async {
        guard enabled, available else { return }
        let sample: HKQuantitySample? = await withCheckedContinuation { cont in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(sampleType: bodyMass, predicate: nil,
                                      limit: 1, sortDescriptors: [sort]) { _, results, _ in
                cont.resume(returning: results?.first as? HKQuantitySample)
            }
            store.execute(query)
        }
        guard let sample else { return }
        let kg = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
        guard kg > 0 else { return }
        // only log if newer than the latest Forge entry
        let latest = (try? await ForgeAPI.measurements())?
            .first { $0.kind == "Weight" }?.latest
        if let latest,
           let latestDate = ISO8601DateFormatter().date(from: String(latest.measured_at.prefix(19)) + "Z"),
           sample.endDate <= latestDate.addingTimeInterval(60) {
            return
        }
        try? await ForgeAPI.addMeasurement(kind: "Weight", value: (kg * 10).rounded() / 10,
                                           measuredAt: sample.endDate)
    }
}
