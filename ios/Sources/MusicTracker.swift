import Foundation
import MediaPlayer
import MusicKit
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
        let media = await withCheckedContinuation { cont in
            MPMediaLibrary.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        // MusicKit consent rides the same opt-in moment (recently-played
        // gap-fill); denying it only loses the gap-fill, so it can't veto
        _ = await MusicAuthorization.request()
        return media
    }

    private(set) var events: [MusicEvent] = []
    /// Songs Apple Music's recently-played knows about that the live
    /// snapshots never saw — HomePod/Watch playback, locked-phone gaps.
    /// Kept separate so the two capture paths stay comparable in the data.
    private(set) var inferred: [SyncSong] = []
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

    /// Ask Apple Music what played since the workout started and keep what
    /// the live snapshots missed. Requires the MusicKit app service on the
    /// App ID and an Apple Music subscription — every failure path is a
    /// silent no-op, so live capture never depends on this.
    func reconcile(since workoutStart: Date) async {
        guard Self.enabled else { return }
        var status = MusicAuthorization.currentStatus
        if status == .notDetermined {
            status = await MusicAuthorization.request()
        }
        guard status == .authorized else { return }
        var request = MusicRecentlyPlayedRequest<Song>()
        request.limit = 30
        guard let response = try? await request.response() else { return }

        var known = Set(events.map(identity))
        events.forEach { known.insert("\($0.title)|\($0.artist ?? "")") }
        let iso = ISO8601DateFormatter()
        var found: [SyncSong] = []
        for song in response.items {
            // Without a per-play timestamp there is no honest way to place
            // the song inside the workout — skip rather than guess.
            guard let played = song.lastPlayedDate, played >= workoutStart else { continue }
            let key = song.id.rawValue
            let altKey = "\(song.title)|\(song.artistName)"
            guard !known.contains(key), !known.contains(altKey) else { continue }
            known.insert(key)
            found.append(SyncSong(
                position: 0,  // merged + renumbered at sync
                title: song.title,
                artist: song.artistName,
                album: song.albumTitle,
                apple_id: key,
                started_at: iso.string(from: played),
                ended_at: nil,
                source: "inferred"
            ))
        }
        inferred = found
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
