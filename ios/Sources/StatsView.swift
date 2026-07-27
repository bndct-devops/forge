import SwiftUI

struct StatsView: View {
    @State private var stats: StatsResponse?
    @State private var records: [RecordEntry] = []
    @State private var loading = true

    var body: some View {
        NavigationStack {
            ZStack {
                FG.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if loading {
                            ProgressView().tint(FG.ember).frame(maxWidth: .infinity).padding(.vertical, 40)
                        }

                        if let s = stats {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                tile("Week streak", "\(s.streak_weeks)")
                                tile("Workouts", "\(s.totals.workouts)")
                                tile("Volume", "\(fmtVol(s.totals.volume)) kg")
                                tile("Sets · PRs", "\(s.totals.sets) · \(s.totals.prs)")
                            }

                            Text("Weekly volume")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.top, 10)
                            weeklyChart(s.weeks.suffix(8))
                        }

                        if !records.isEmpty {
                            Text("Records")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.top, 10)

                            VStack(spacing: 0) {
                                ForEach(Array(records.enumerated()), id: \.element.id) { i, r in
                                    HStack(spacing: 10) {
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(r.name).font(.system(size: 14, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                                            Text(r.muscle_group ?? "").font(.system(size: 11)).foregroundStyle(FG.muted)
                                        }
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 1) {
                                            if let bw = r.best_weight {
                                                Text("\(trim(bw.weight)) kg × \(bw.reps)")
                                                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                                                    .foregroundStyle(.white)
                                            }
                                            if let rm = r.best_1rm {
                                                Text("1RM \(trim(rm.value)) kg")
                                                    .font(.system(size: 11).monospacedDigit())
                                                    .foregroundStyle(FG.muted)
                                            }
                                        }
                                    }
                                    .padding(.vertical, 10)
                                    .padding(.horizontal, 14)
                                    if i < records.count - 1 {
                                        Rectangle().fill(FG.border.opacity(0.6)).frame(height: 1).padding(.leading, 14)
                                    }
                                }
                            }
                            .background(RoundedRectangle(cornerRadius: 14).fill(FG.card))
                            .overlay(RoundedRectangle(cornerRadius: 14).stroke(FG.border, lineWidth: 1))
                        }

                        Text("Deep dives live in the Forge web app.")
                            .font(.system(size: 12))
                            .foregroundStyle(FG.muted)
                            .padding(.top, 8)

                        Color.clear.frame(height: 30)
                    }
                    .padding(.horizontal, 18)
                }
            }
            .navigationTitle("Stats")
            .navigationBarTitleDisplayMode(.large)
        }
        .preferredColorScheme(.dark)
        .task {
            stats = try? await ForgeAPI.stats()
            records = (try? await ForgeAPI.records()) ?? []
            loading = false
        }
        .refreshable {
            stats = try? await ForgeAPI.stats()
            records = (try? await ForgeAPI.records()) ?? []
        }
    }

    private func tile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 12)).foregroundStyle(FG.muted)
            Text(value).font(.system(size: 20, weight: .semibold).monospacedDigit()).foregroundStyle(.white)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(FG.card))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(FG.border, lineWidth: 1))
    }

    private func weeklyChart(_ weeks: ArraySlice<StatsWeek>) -> some View {
        let maxVol = max(weeks.map(\.volume).max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(weeks), id: \.id) { w in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(w.volume > 0 ? FG.ember : FG.secondary)
                            .frame(height: max(4, 90 * w.volume / maxVol))
                            .frame(maxWidth: .infinity)
                        Text(String(w.week_start.suffix(5).prefix(5)).replacingOccurrences(of: "-", with: "/"))
                            .font(.system(size: 8).monospacedDigit())
                            .foregroundStyle(FG.muted)
                    }
                }
            }
            .frame(height: 110, alignment: .bottom)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(FG.card))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(FG.border, lineWidth: 1))
    }

    private func fmtVol(_ v: Double) -> String {
        v >= 10000 ? String(format: "%.1fk", v / 1000) : trim(v)
    }
}
