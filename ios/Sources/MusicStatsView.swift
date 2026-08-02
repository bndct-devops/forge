import SwiftUI

/// Train-time listening, aggregated from every workout soundtrack the app
/// captured. Grows with the data — one workout in, the page is sparse and
/// honest about it. Pushed from the Stats overview like Records.
struct MusicStatsView: View {
    @State private var stats: MusicStats?
    @State private var loading = true

    var body: some View {
        ZStack {
            FG.background.ignoresSafeArea()
            if loading {
                ProgressView().tint(FG.ember)
            } else if let s = stats, (s.workouts ?? 0) > 0 {
                content(s)
            } else {
                emptyState
            }
        }
        .navigationTitle("Music")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .task {
            stats = try? await ForgeAPI.musicStats()
            loading = false
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "music.note")
                .font(.system(size: 34)).foregroundStyle(FG.muted)
            Text("No soundtrack data yet")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
            Text("Enable \"Log music during workouts\" in Settings — every session you train with music starts filling this page.")
                .font(.system(size: 13)).foregroundStyle(FG.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
        }
    }

    private func content(_ s: MusicStats) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    statTile("\(s.songs ?? 0)", "songs played")
                    statTile("\(s.artists ?? 0)", "artists")
                    statTile("\(s.workouts ?? 0)", "workouts")
                }

                if let prSongs = s.pr_songs, !prSongs.isEmpty {
                    card {
                        HStack(spacing: 6) {
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 13)).foregroundStyle(FG.gold)
                            Text("PR songs")
                                .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        }
                        .padding(.bottom, 2)
                        ForEach(Array(prSongs.enumerated()), id: \.offset) { _, song in
                            songRow(song, trailing: "\(song.prs ?? 0) PR\((song.prs ?? 0) == 1 ? "" : "s")",
                                    trailingColor: FG.gold)
                        }
                    }
                }

                if let artists = s.top_artists, !artists.isEmpty {
                    let maxPlays = max(1, artists.first?.plays ?? 1)
                    card {
                        Text("Top artists while training")
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                            .padding(.bottom, 2)
                        ForEach(Array(artists.enumerated()), id: \.offset) { _, artist in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(artist.artist)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.white).lineLimit(1)
                                    Spacer()
                                    Text("\(artist.plays) play\(artist.plays == 1 ? "" : "s")")
                                        .font(.system(size: 11).monospacedDigit())
                                        .foregroundStyle(FG.muted)
                                }
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(FG.secondary)
                                        Capsule().fill(FG.ember.opacity(0.7))
                                            .frame(width: max(8, geo.size.width * CGFloat(artist.plays) / CGFloat(maxPlays)))
                                    }
                                }
                                .frame(height: 5)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }

                if let songs = s.top_songs, !songs.isEmpty {
                    card {
                        Text("Most played songs")
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                            .padding(.bottom, 2)
                        ForEach(Array(songs.enumerated()), id: \.offset) { i, song in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text("\(i + 1)")
                                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(FG.muted)
                                    .frame(width: 18, alignment: .center)
                                songRow(song, trailing: "×\(song.plays ?? 0)", trailingColor: FG.muted)
                            }
                        }
                    }
                }

                if let inferred = s.sources?.inferred, inferred > 0 {
                    Text("\(inferred) of \(s.songs ?? 0) songs were gap-filled from Apple Music's recently played (≈ in workout soundtracks) — the rest were heard live by the app.")
                        .font(.system(size: 11)).foregroundStyle(FG.muted)
                        .padding(.horizontal, 2)
                }

                Color.clear.frame(height: 30)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
        }
    }

    private func songRow(_ song: MusicSongRow, trailing: String, trailingColor: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(song.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white).lineLimit(1)
                if let artist = song.artist {
                    Text(artist)
                        .font(.system(size: 11)).foregroundStyle(FG.muted).lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            Text(trailing)
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(trailingColor)
        }
        .padding(.vertical, 3)
    }

    private func statTile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 17, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
            Text(label)
                .font(.system(size: 11)).foregroundStyle(FG.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14).fill(FG.card))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(FG.border, lineWidth: 1))
    }

    private func card(@ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(FG.card))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(FG.border, lineWidth: 1))
    }
}
