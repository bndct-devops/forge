import SwiftUI

/// The workout-complete celebration: staggered stat reveal, PR trophies,
/// comparison to the last same-named session, per-exercise breakdown and a
/// prominent share button (branded stat-card image).
struct FinishSummaryView: View {
    @ObservedObject var store: WorkoutStore
    let summary: FinishSummary?
    let queuedOffline: Bool
    let onDone: () -> Void

    @State private var appeared = false
    @State private var shownVolume: Double = 0

    private var volume: Double { summary?.total_volume ?? store.volume }
    private var sets: Int { summary?.total_sets ?? store.doneSets }
    private var minutes: Int {
        (summary?.duration_seconds).map { $0 / 60 }
            ?? Int(Date().timeIntervalSince(store.startedAt) / 60)
    }
    private var prs: [FinishPR] { summary?.prs ?? [] }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 14) {
                    header
                    statTiles
                    if !prs.isEmpty { prCard }
                    if let c = summary?.comparison { comparisonCard(c) }
                    breakdown
                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal, 18)
                .padding(.top, 20)
            }
            actions
        }
        .onAppear {
            withAnimation(.spring(duration: 0.5, bounce: 0.4)) { appeared = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                withAnimation(.easeOut(duration: 0.9)) { shownVolume = volume }
            }
        }
    }

    // MARK: header

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 46)).foregroundStyle(FG.ember)
                .scaleEffect(appeared ? 1 : 0.4)
                .opacity(appeared ? 1 : 0)
            Text(queuedOffline ? "Saved on this phone" : "Workout complete")
                .font(.system(size: 24, weight: .bold)).foregroundStyle(.white)
            if let n = summary?.workout_number {
                (Text("Workout #\(n)").fontWeight(.semibold).foregroundStyle(FG.ember)
                 + Text(summary?.week_workouts.map { " · \($0)\(ordinal($0)) this week" } ?? "")
                    .foregroundStyle(FG.muted))
                    .font(.system(size: 14))
            } else if queuedOffline {
                Text("No connection — it syncs to Forge automatically once you're back online.")
                    .font(.system(size: 13)).foregroundStyle(FG.muted)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .stagger(0, appeared)
    }

    // MARK: stat tiles

    private var statTiles: some View {
        HStack(spacing: 10) {
            statTile("VOLUME", Text("\(fmtVolume(shownVolume))")
                .contentTransition(.numericText(value: shownVolume)))
                .stagger(1, appeared)
            statTile("SETS", Text("\(sets)")).stagger(2, appeared)
            statTile("TIME", Text("\(minutes) min")).stagger(3, appeared)
        }
    }

    private func statTile(_ label: String, _ value: some View) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .semibold)).tracking(0.8)
                .foregroundStyle(FG.muted)
            value
                .font(.system(size: 18, weight: .bold).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 13).fill(FG.card))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(FG.border, lineWidth: 1))
    }

    // MARK: PRs

    private var prCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "trophy.fill").font(.system(size: 13)).foregroundStyle(FG.gold)
                Text("\(prs.count) personal record\(prs.count == 1 ? "" : "s")")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(FG.gold)
            }
            ForEach(prs) { pr in
                HStack {
                    Text(pr.exercise_name ?? "").font(.system(size: 13)).foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer()
                    Text(pr.kind == "reps"
                         ? "\(Int(pr.value ?? 0)) reps"
                         : "\(trim(pr.value ?? 0)) kg × \(pr.reps ?? 0)")
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(FG.gold.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(FG.gold.opacity(0.35), lineWidth: 1))
        .stagger(4, appeared)
    }

    // MARK: comparison

    private func comparisonCard(_ c: FinishComparison) -> some View {
        let delta = volume - (c.prev_volume ?? 0)
        return HStack(spacing: 10) {
            Image(systemName: delta >= 0 ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(delta >= 0 ? FG.success : FG.destructive)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 9)
                    .fill((delta >= 0 ? FG.success : FG.destructive).opacity(0.15)))
            VStack(alignment: .leading, spacing: 1) {
                (Text("\(delta >= 0 ? "+" : "")\(fmtVolume(delta)) ")
                    .fontWeight(.semibold)
                    .foregroundStyle(delta >= 0 ? FG.success : FG.destructive)
                 + Text("vs last \(summary?.name ?? "session")").foregroundStyle(FG.muted))
                    .font(.system(size: 13))
                    .lineLimit(2)
                if let prev = c.prev_date {
                    Text(relativeMeasureDate(prev))
                        .font(.system(size: 11)).foregroundStyle(FG.muted)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(FG.card))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(FG.border, lineWidth: 1))
        .stagger(5, appeared)
    }

    // MARK: per-exercise breakdown

    private var breakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(store.exercises.enumerated()), id: \.element.id) { i, ex in
                let done = ex.sets.filter(\.done)
                if !done.isEmpty {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(ex.name)
                                .font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                                .lineLimit(1)
                            Text("\(done.count) set\(done.count == 1 ? "" : "s") · \(fmtVolume(exVolume(done)))")
                                .font(.system(size: 12).monospacedDigit()).foregroundStyle(FG.muted)
                        }
                        Spacer()
                        if let best = done.max(by: {
                            ($0.weight ?? 0) * Double($0.reps ?? 0) < ($1.weight ?? 0) * Double($1.reps ?? 0)
                        }), let reps = best.reps {
                            Text((best.weight ?? 0) > 0
                                 ? "\(trim(best.weight!)) × \(reps)"
                                 : "\(reps) reps")
                                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                                .foregroundStyle(FG.ember)
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 12).fill(FG.card))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(FG.border, lineWidth: 1))
                    .stagger(6 + i, appeared)
                }
            }
        }
    }

    // MARK: actions

    private var actions: some View {
        HStack(spacing: 10) {
            ShareLink(
                item: shareImage(),
                preview: SharePreview("Forge workout", image: shareImage())
            ) {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 14, weight: .semibold))
                    Text("Share").font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(FG.ember)
                .frame(maxWidth: .infinity).frame(height: 50)
                .background(RoundedRectangle(cornerRadius: 14).fill(FG.emberSoft))
            }
            .buttonStyle(Pressable())
            Button {
                onDone()
            } label: {
                Text("Done")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.8))
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(RoundedRectangle(cornerRadius: 14).fill(FG.ember))
            }
            .buttonStyle(Pressable())
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .stagger(7, appeared)
    }

    // MARK: share card

    @MainActor
    private func shareImage() -> Image {
        renderShareCard(ShareCard(
            name: summary?.name ?? store.name,
            date: Date(),
            volume: volume, sets: sets, minutes: minutes,
            prCount: prs.count,
            workoutNumber: summary?.workout_number
        ))
    }

    // MARK: helpers

    private func exVolume(_ sets: [DraftSet]) -> Double {
        sets.filter { !$0.warmup }.reduce(0) { $0 + ($1.weight ?? 0) * Double($1.reps ?? 0) }
    }

    private func ordinal(_ n: Int) -> String {
        switch n {
        case 1: return "st"
        case 2: return "nd"
        case 3: return "rd"
        default: return "th"
        }
    }
}

@MainActor
func renderShareCard(_ card: ShareCard) -> Image {
    let renderer = ImageRenderer(content: card)
    renderer.scale = 3
    if let ui = renderer.uiImage {
        return Image(uiImage: ui)
    }
    return Image(systemName: "dumbbell.fill")
}

/// Staggered entrance: fade + rise, delayed per index.
private struct Stagger: ViewModifier {
    let index: Int
    let shown: Bool

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .animation(.spring(duration: 0.45).delay(Double(index) * 0.07), value: shown)
    }
}

private extension View {
    func stagger(_ index: Int, _ shown: Bool) -> some View {
        modifier(Stagger(index: index, shown: shown))
    }
}

/// The branded stat card rendered for sharing — used by the finish screen
/// and past-workout detail pages.
struct ShareCard: View {
    let name: String
    let date: Date
    let volume: Double
    let sets: Int
    let minutes: Int
    let prCount: Int
    let workoutNumber: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(FG.ember)
                Text("FORGE")
                    .font(.system(size: 14, weight: .bold))
                    .tracking(3)
                    .foregroundStyle(FG.ember)
                Spacer()
                if let n = workoutNumber {
                    Text("#\(n)")
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(FG.muted)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.system(size: 13))
                    .foregroundStyle(FG.muted)
            }
            HStack(spacing: 12) {
                cardStat(fmtVolume(volume), "volume")
                cardStat("\(sets)", "sets")
                cardStat("\(minutes) min", "time")
            }
            if prCount > 0 {
                HStack(spacing: 6) {
                    Image(systemName: "trophy.fill").font(.system(size: 13)).foregroundStyle(FG.gold)
                    Text("\(prCount) personal record\(prCount == 1 ? "" : "s")")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(FG.gold)
                }
            }
        }
        .padding(26)
        .frame(width: 420, alignment: .leading)
        .background(FG.background)
        .overlay(alignment: .bottom) {
            Rectangle().fill(FG.ember).frame(height: 5)
        }
    }

    private func cardStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 21, weight: .bold).monospacedDigit())
                .foregroundStyle(.white)
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold)).tracking(1)
                .foregroundStyle(FG.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
