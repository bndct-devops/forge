import Foundation
import MediaPlayer
import UIKit

/// One observation of the system player: what was playing at `ts`, and how
/// far into the song. `position` is the payoff — a single mid-song snapshot
/// back-computes when the song started, so even sparse observations (the app
/// is suspended between sets) reconstruct a near-continuous timeline.
struct MusicEvent: Codable {
    var ts: Date
    var title: String
    var artist: String?
    var album: String?
    var appleId: String?     // playbackStoreID — stable catalog id when streaming
    var position: Double?
}

/// Watches the system Music player while a workout runs and records which
/// songs play. No background execution: change notifications cover the
/// foreground, and every set completion / app foregrounding takes a snapshot —
/// you open the app to log every set anyway, so the soundtrack assembles
/// itself from moments the app is awake.
@MainActor
final class MusicTracker {
    private static let key = "musicTracking"
    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static var authorized: Bool { MPMediaLibrary.authorizationStatus() == .authorized }

    static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { cont in
            MPMediaLibrary.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
    }

    private(set) var events: [MusicEvent] = []
    /// Fires after a new event lands so the owning store can persist.
    var onEvent: (() -> Void)?

    private let player = MPMusicPlayerController.systemMusicPlayer
    private var observers: [NSObjectProtocol] = []
    private var observing = false

    /// Arm the tracker for a workout, seeding events restored from a draft.
    func start(restoring restored: [MusicEvent] = []) {
        events = restored
        guard Self.enabled, Self.authorized, !observing else { return }
        observing = true
        player.beginGeneratingPlaybackNotifications()
        let center = NotificationCenter.default
        for name: Notification.Name in [
            .MPMusicPlayerControllerNowPlayingItemDidChange,
            .MPMusicPlayerControllerPlaybackStateDidChange,
        ] {
            observers.append(center.addObserver(forName: name, object: player, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.snapshot() }
            })
        }
        observers.append(center.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.snapshot() }
        })
        snapshot()
    }

    func stop() {
        guard observing else { return }
        observing = false
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        player.endGeneratingPlaybackNotifications()
    }

    /// Record what's playing right now. Safe to call any time — no-ops when
    /// tracking is off, nothing plays, or nothing changed since the last look.
    func snapshot() {
        guard observing, player.playbackState == .playing,
              let item = player.nowPlayingItem, let title = item.title else { return }
        let storeId = item.playbackStoreID
        let event = MusicEvent(
            ts: Date(),
            title: title,
            artist: item.artist,
            album: item.albumTitle,
            appleId: (storeId.isEmpty || storeId == "0") ? nil : storeId,
            position: player.currentPlaybackTime.isFinite ? player.currentPlaybackTime : nil
        )
        if let last = events.last, identity(last) == identity(event),
           event.ts.timeIntervalSince(last.ts) < 20 {
            return  // same song moments later — nothing new to learn
        }
        guard events.count < 2000 else { return }
        events.append(event)
        onEvent?()
    }

    private func identity(_ e: MusicEvent) -> String {
        e.appleId ?? "\(e.title)|\(e.artist ?? "")"
    }

    /// Collapse the event stream into per-song play windows for sync.
    /// started_at back-computes from the playback position when known;
    /// ended_at is the last moment the song was observed (an understatement).
    static func segments(from events: [MusicEvent]) -> [SyncSong] {
        struct Run {
            var key: String
            var first: MusicEvent
            var start: Date
            var lastSeen: Date
        }
        var runs: [Run] = []
        for e in events.sorted(by: { $0.ts < $1.ts }) {
            let key = e.appleId ?? "\(e.title)|\(e.artist ?? "")"
            let estimatedStart = e.position.map { e.ts.addingTimeInterval(-$0) } ?? e.ts
            if var run = runs.last, run.key == key {
                run.start = min(run.start, estimatedStart)
                run.lastSeen = e.ts
                runs[runs.count - 1] = run
            } else {
                runs.append(Run(key: key, first: e, start: estimatedStart, lastSeen: e.ts))
            }
        }
        let iso = ISO8601DateFormatter()
        return runs.enumerated().map { i, run in
            SyncSong(
                position: i,
                title: run.first.title,
                artist: run.first.artist,
                album: run.first.album,
                apple_id: run.first.appleId,
                started_at: iso.string(from: run.start),
                ended_at: run.lastSeen > run.start ? iso.string(from: run.lastSeen) : nil
            )
        }
    }
}
