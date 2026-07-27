import Foundation
import Network

/// Finished workouts that couldn't reach the server wait here and flush
/// automatically once the network is back. Sync is idempotent by client_id,
/// so retries are safe.
@MainActor
final class SyncQueue: ObservableObject {
    static let shared = SyncQueue()

    @Published private(set) var pendingCount = 0
    private var flushing = false
    private let monitor = NWPathMonitor()

    private var queueURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("forge-pending-sync.json")
    }

    private init() {
        pendingCount = load().count
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in await self?.flush() }
        }
        monitor.start(queue: DispatchQueue.global(qos: .utility))
    }

    private func load() -> [SyncWorkout] {
        guard let data = try? Data(contentsOf: queueURL) else { return [] }
        return (try? JSONDecoder().decode([SyncWorkout].self, from: data)) ?? []
    }

    private func store(_ docs: [SyncWorkout]) {
        pendingCount = docs.count
        if docs.isEmpty {
            try? FileManager.default.removeItem(at: queueURL)
            return
        }
        let dir = queueURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(docs) {
            try? data.write(to: queueURL, options: .atomic)
        }
    }

    func enqueue(_ doc: SyncWorkout) {
        var docs = load()
        docs.removeAll { $0.client_id == doc.client_id }
        docs.append(doc)
        store(docs)
    }

    /// Push every queued workout; keeps whatever still fails.
    func flush() async {
        guard !flushing else { return }
        flushing = true
        defer { flushing = false }
        var remaining: [SyncWorkout] = []
        for doc in load() {
            do {
                try await ForgeAPI.sync(doc)
            } catch let error as APIError {
                // the server actively rejected it — retrying won't help,
                // but keep it so the data is never silently dropped
                _ = error
                remaining.append(doc)
            } catch {
                remaining.append(doc)
            }
        }
        store(remaining)
    }
}
