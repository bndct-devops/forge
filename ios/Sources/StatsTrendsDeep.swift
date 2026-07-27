import SwiftUI
import Charts

/// The deep-analysis Trends sections from the PWA's StatsPage: block
/// comparison, form & fatigue, top lifts, TM headroom, cycles, cycle report,
/// velocity, relative strength, standards, trajectory, recovery, detraining,
/// pacing, time of day. Each renders only when the backend has the data.
struct DeepTrendsSections: View {
    let trends: StatsTrends

    static let seriesColors: [Color] = [
        FG.ember,
        Color(red: 0.427, green: 0.529, blue: 0.671),  // #6d87ab
        Color(red: 0.353, green: 0.576, blue: 0.404),  // #5a9367
    ]

    var body: some View {
        if let b = trends.blocks { blocksCard(b) }
        if let l = trends.load { loadCard(l) }
        if let tl = trends.top_lifts, !tl.names.isEmpty {
            seriesCard("Top lifts — estimated 1RM", subtitle: nil, series: tl, suffix: " kg")
        }
        if let hr = trends.headroom, !hr.isEmpty { headroomCard(hr).id("headroom") }
        if let c = trends.cycles, !c.isEmpty { cyclesCard(c) }
        if let r = trends.cycle_report, !r.isEmpty { cycleReportCard(r) }
        if let v = trends.velocity, !v.isEmpty { velocityCard(v) }
        if let rel = trends.relative, !rel.names.isEmpty {
            seriesCard("Relative strength",
                       subtitle: "estimated 1RM ÷ bodyweight — honest progress while cutting or bulking",
                       series: rel, suffix: "×")
        }
        if let s = trends.standards, !s.isEmpty { standardsCard(s) }
        if let f = trends.forecast, !f.isEmpty { forecastCard(f) }
        if let r = trends.recovery, !r.isEmpty { recoveryCard(r) }
        if let d = trends.detraining { detrainingCard(d) }
        if let p = trends.pacing { pacingCard(p) }
        if let t = trends.times, t.count >= 2 { timeOfDayCard(t) }
    }

    // MARK: shared

    private func card(_ title: String, _ subtitle: String?,
                      @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
            if let subtitle {
                Text(subtitle).font(.system(size: 12)).foregroundStyle(FG.muted)
            }
            content().padding(.top, 9)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(FG.card))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(FG.border, lineWidth: 1))
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.system(size: 11)).foregroundStyle(FG.muted).lineLimit(1)
        }
    }

    private func weekDate(_ s: String) -> Date? {
        ISO8601DateFormatter().date(from: s + "T00:00:00Z")
    }

    private func axisStyle(some chart: some View) -> some View { chart }

    // MARK: this block vs last

    private func blocksCard(_ b: TrendBlocks) -> some View {
        card("This block vs last", "\(b.days)-day training blocks, sets per muscle group") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    blockTile("Volume", fmtVolume(b.current.volume),
                              b.previous.volume > 0
                                ? "\(b.current.volume >= b.previous.volume ? "+" : "")\(Int(((b.current.volume - b.previous.volume) / b.previous.volume * 100).rounded()))% vs last block"
                                : nil)
                    blockTile("Workouts", "\(b.current.workouts)", "vs \(b.previous.workouts) last block")
                }
                VStack(spacing: 8) {
                    ForEach(b.groups) { g in
                        HStack(spacing: 12) {
                            Text(g.group).font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                                .frame(width: 80, alignment: .leading)
                            Spacer()
                            Text("\(g.previous) → \(g.current)")
                                .font(.system(size: 13).monospacedDigit()).foregroundStyle(FG.muted)
                            Text(g.current == g.previous ? "±0" : "\(g.current > g.previous ? "+" : "")\(g.current - g.previous)")
                                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                                .foregroundStyle(g.current > g.previous ? FG.success
                                                 : g.current < g.previous ? FG.destructive : FG.muted)
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }
                if !b.lifts.isEmpty {
                    Divider().overlay(FG.border.opacity(0.5))
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(b.lifts) { l in
                            HStack(spacing: 12) {
                                Text(l.name).font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(trim(l.previous)) → \(trim(l.current)) kg")
                                    .font(.system(size: 13).monospacedDigit()).foregroundStyle(FG.muted)
                                Text("\(l.current >= l.previous ? "+" : "")\(String(format: "%.1f", l.current - l.previous))")
                                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(l.current >= l.previous ? FG.success : FG.destructive)
                                    .frame(width: 52, alignment: .trailing)
                            }
                        }
                        Text("best estimated 1RM per block")
                            .font(.system(size: 10)).foregroundStyle(FG.muted)
                    }
                }
            }
        }
    }

    private func blockTile(_ label: String, _ value: String, _ hint: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 11)).foregroundStyle(FG.muted)
            Text(value).font(.system(size: 16, weight: .semibold).monospacedDigit()).foregroundStyle(.white)
            if let hint {
                Text(hint).font(.system(size: 10).monospacedDigit()).foregroundStyle(FG.muted)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(FG.secondary))
    }

    // MARK: form & fatigue

    private static let loadStatus: [String: (String, String)] = [
        "fresh": ("Fresh", "fatigue is low — a good stretch to push"),
        "productive": ("Productive", "building fitness at a sustainable clip"),
        "overreaching": ("Overreaching", "fatigue is outrunning fitness — plan an easier day"),
    ]

    private func loadCard(_ l: TrendLoad) -> some View {
        let status = Self.loadStatus[l.status] ?? (l.status, "")
        let days: [(Date, TrendLoadDay)] = l.days.compactMap { d in
            weekDate(d.date).map { ($0, d) }
        }
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("Form & fatigue").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                Text(status.0)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(l.status == "overreaching" ? FG.destructive : FG.ember)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(l.status == "overreaching"
                        ? FG.destructive.opacity(0.15) : FG.emberSoft))
            }
            Text("\(status.1) — 42-day fitness vs 7-day fatigue, from daily training load")
                .font(.system(size: 12)).foregroundStyle(FG.muted)
            HStack(spacing: 14) {
                legendDot(FG.ember, "Fitness")
                legendDot(Self.seriesColors[1], "Fatigue")
            }
            .padding(.top, 8)
            Chart {
                ForEach(days, id: \.1.id) { d, day in
                    LineMark(x: .value("Date", d), y: .value("Fitness", day.fitness),
                             series: .value("s", "fitness"))
                        .foregroundStyle(FG.ember)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    LineMark(x: .value("Date", d), y: .value("Fatigue", day.fatigue),
                             series: .value("s", "fatigue"))
                        .foregroundStyle(Self.seriesColors[1])
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                        .font(.system(size: 10)).foregroundStyle(FG.muted)
                }
            }
            .chartYAxis { deepYAxis() }
            .frame(height: 180)
            .padding(.top, 8)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(FG.card))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(FG.border, lineWidth: 1))
    }

    // MARK: multi-series line card (top lifts / relative strength)

    private func seriesCard(_ title: String, subtitle: String?, series: NamedSeries, suffix: String) -> some View {
        let rows: [(Date, String, Double)] = series.weeks.flatMap { wk -> [(Date, String, Double)] in
            guard let d = weekDate(wk.week_start) else { return [] }
            return series.names.compactMap { name in
                wk.values[name].map { (d, name, $0) }
            }
        }
        return card(title, subtitle) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(series.names.enumerated()), id: \.element) { i, name in
                        legendDot(Self.seriesColors[i % Self.seriesColors.count], name)
                    }
                }
                MultiSeriesChart(rows: rows, names: series.names, suffix: suffix)
            }
        }
    }

    // MARK: TM headroom

    private func headroomCard(_ items: [TrendHeadroom]) -> some View {
        card("TM headroom",
             "AMRAP e1RM vs training max — around +10% is a healthy TM, near 0% a bump is outpacing you, negative means deload it") {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(items) { h in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(h.lift).font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                                .lineLimit(1)
                            Spacer()
                            Text("\(h.latest.headroom > 0 ? "+" : "")\(trim(h.latest.headroom))%")
                                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                                .foregroundStyle(h.latest.headroom >= 5 ? FG.success
                                                 : h.latest.headroom >= 0 ? .white : FG.destructive)
                        }
                        Text("C\(h.latest.cycle) W\(h.latest.week) · \(trim(h.latest.weight))×\(h.latest.reps) → e1RM \(trim(h.latest.e1rm)) vs TM \(trim(h.latest.tm)) kg")
                            .font(.system(size: 12).monospacedDigit()).foregroundStyle(FG.muted)
                        if h.points.count > 1 {
                            HStack(alignment: .bottom, spacing: 4) {
                                ForEach(Array(h.points.enumerated()), id: \.offset) { i, pt in
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(pt.headroom >= 0 ? FG.ember : FG.destructive)
                                        .opacity(0.45 + 0.55 * Double(i + 1) / Double(h.points.count))
                                        .frame(height: max(4, min(36, (pt.headroom + 5) / 20 * 36)))
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .frame(height: 36, alignment: .bottom)
                            .padding(.top, 6)
                        }
                    }
                }
            }
        }
    }

    // MARK: cycle over cycle

    private func cyclesCard(_ lifts: [TrendCycleLift]) -> some View {
        card("Cycle over cycle",
             "the same program week, one cycle apart — reps held at a higher weight is the cleanest progress there is") {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(lifts) { c in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(c.lift).font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                        ForEach(c.weeks) { wk in
                            let delta: Double? = wk.cycles.count > 1
                                ? ((wk.cycles.last!.e1rm - wk.cycles.first!.e1rm) * 10).rounded() / 10
                                : nil
                            HStack(spacing: 8) {
                                Text("W\(wk.week)")
                                    .font(.system(size: 12)).foregroundStyle(FG.muted)
                                    .frame(width: 28, alignment: .leading)
                                Text(wk.cycles.map { "\(trim($0.weight))×\($0.reps)" }.joined(separator: " → "))
                                    .font(.system(size: 12).monospacedDigit()).foregroundStyle(.white)
                                    .lineLimit(1)
                                Spacer()
                                if let delta {
                                    Text("\(delta > 0 ? "+" : "")\(trim(delta)) e1RM")
                                        .font(.system(size: 12).monospacedDigit())
                                        .foregroundStyle(delta > 0 ? FG.success : delta < 0 ? FG.destructive : FG.muted)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: cycle report

    private func cycleReportCard(_ reports: [TrendCycleReport]) -> some View {
        card("Cycle report",
             "the last completed cycle, closed out — a TM bump is earned when the cycle's best AMRAP already covers the new max") {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(reports) { r in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(r.program) · Cycle \(r.cycle) · \(shortDate(r.from)) – \(shortDate(r.to))")
                            .font(.system(size: 12)).foregroundStyle(FG.muted)
                        ForEach(r.lifts) { l in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(l.lift).font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                                        .lineLimit(1)
                                    Spacer()
                                    Text("TM \(trim(l.tm)) → \(trim(l.tm_next)) · \(l.earned ? "earned" : "not shown") \(l.margin > 0 ? "+" : "")\(trim(l.margin))%")
                                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                                        .foregroundStyle(l.earned ? FG.success : FG.destructive)
                                        .padding(.horizontal, 8).padding(.vertical, 3)
                                        .background(Capsule().fill((l.earned ? FG.success : FG.destructive).opacity(0.15)))
                                }
                                Text(l.weeks.map { "W\($0.week) \(trim($0.weight))×\($0.reps) (\(trim($0.e1rm)))" }
                                    .joined(separator: " · "))
                                    .font(.system(size: 12).monospacedDigit()).foregroundStyle(FG.muted)
                            }
                        }
                        if !r.accessories.isEmpty {
                            Divider().overlay(FG.border.opacity(0.5))
                            Text("ACCESSORIES MOVED")
                                .font(.system(size: 10, weight: .semibold)).tracking(0.8)
                                .foregroundStyle(FG.muted)
                            Text(r.accessories.map { "\($0.name) \(trim($0.from)) → \(trim($0.to)) kg" }
                                .joined(separator: "  ·  "))
                                .font(.system(size: 12).monospacedDigit()).foregroundStyle(FG.muted)
                        }
                    }
                }
            }
        }
    }

    // MARK: velocity

    private func velocityCard(_ items: [TrendVelocity]) -> some View {
        card("Progression velocity",
             "sessions needed per weight increase on rep-range work — fast movers are working, slow movers may need attention") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(items) { v in
                    HStack(spacing: 8) {
                        Text(v.name).font(.system(size: 13)).foregroundStyle(.white).lineLimit(1)
                        Spacer()
                        Text("\(trim(v.current_weight)) kg · \(v.sessions_at_current) session\(v.sessions_at_current == 1 ? "" : "s") · \(v.last_min_reps)/\(v.rep_max) reps")
                            .font(.system(size: 11).monospacedDigit()).foregroundStyle(FG.muted)
                        Text("+1 per \(trim(v.sessions_per_increase))")
                            .font(.system(size: 13, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.white)
                    }
                }
            }
        }
    }

    // MARK: standards

    private func standardsCard(_ items: [TrendStandard]) -> some View {
        card("Strength standards",
             "best e1RM ÷ bodyweight vs population standards — barbell lifts only, and standards are approximate") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(items) { s in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(s.lift).font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                            Spacer()
                            (Text(s.level).fontWeight(.semibold).foregroundStyle(.white)
                             + Text(" · \(trim(s.ratio))×BW").foregroundStyle(FG.muted))
                                .font(.system(size: 12))
                        }
                        HStack(spacing: 4) {
                            ForEach(0..<5, id: \.self) { i in
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(FG.secondary)
                                        Capsule().fill(FG.ember)
                                            .frame(width: geo.size.width * min(1, max(0, s.score - Double(i))))
                                    }
                                }
                                .frame(height: 8)
                            }
                        }
                    }
                }
                HStack {
                    ForEach(["Untrained", "Novice", "Intermediate", "Advanced", "Elite"], id: \.self) { l in
                        Text(l).font(.system(size: 9)).foregroundStyle(FG.muted)
                        if l != "Elite" { Spacer() }
                    }
                }
            }
        }
    }

    // MARK: trajectory

    private func forecastCard(_ items: [TrendForecast]) -> some View {
        card("Trajectory",
             "straight-line fit through 12 weeks of estimated 1RM — a compass, not a promise") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(items) { f in
                    HStack(spacing: 8) {
                        Text(f.name).font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer()
                        if let milestone = f.milestone, let eta = f.eta {
                            if f.slope > 0 {
                                Text("+\(trim(f.slope)) kg/wk")
                                    .font(.system(size: 11).monospacedDigit()).foregroundStyle(FG.success)
                            }
                            Text("\(trim(milestone)) kg ≈ \(shortDate(eta))")
                                .font(.system(size: 13).monospacedDigit()).foregroundStyle(FG.muted)
                        } else {
                            Text("holding steady at \(trim(f.current)) kg")
                                .font(.system(size: 12)).foregroundStyle(FG.muted)
                        }
                    }
                }
            }
        }
    }

    // MARK: recovery

    private func recoveryCard(_ items: [TrendRecovery]) -> some View {
        let maxAbs = max(1, items.map { abs($0.pct) }.max() ?? 1)
        return card("Recovery sweet spot",
                    "session strength vs your recent baseline, by rest days before it") {
            VStack(spacing: 10) {
                ForEach(items) { r in
                    HStack(spacing: 12) {
                        Text(r.bucket == "4+" ? "4+ days" : "\(r.bucket) day\(r.bucket == "1" ? "" : "s")")
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                            .frame(width: 64, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(FG.secondary)
                                Capsule().fill(r.pct >= 0 ? FG.ember : FG.destructive.opacity(0.6))
                                    .frame(width: max(4, geo.size.width * abs(r.pct) / maxAbs))
                            }
                        }
                        .frame(height: 16)
                        Text("\(r.pct >= 0 ? "+" : "")\(trim(r.pct))%")
                            .font(.system(size: 13, weight: .semibold).monospacedDigit())
                            .foregroundStyle(r.pct >= 0 ? FG.success : FG.destructive)
                            .frame(width: 52, alignment: .trailing)
                        Text("\(r.n)×")
                            .font(.system(size: 11).monospacedDigit()).foregroundStyle(FG.muted)
                            .frame(width: 28, alignment: .trailing)
                    }
                }
            }
        }
    }

    // MARK: detraining

    private func detrainingCard(_ d: TrendDetraining) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "hourglass")
                .font(.system(size: 17)).foregroundStyle(FG.ember)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 12).fill(FG.emberSoft))
            VStack(alignment: .leading, spacing: 2) {
                Text("Layoffs cost you ~\(trim(abs(d.pct_per_week)))% strength per week away")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                Text("measured across \(d.events) training breaks of 2+ weeks\(d.pct_per_week < 0 ? " — you actually came back stronger" : "")")
                    .font(.system(size: 12)).foregroundStyle(FG.muted)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(FG.card))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(FG.border, lineWidth: 1))
    }

    // MARK: pacing

    private func pacingCard(_ p: TrendPacing) -> some View {
        let weeks: [(Date, Double)] = p.weeks.compactMap { w in
            guard let d = weekDate(w.week_start), let r = w.avg_rest_seconds else { return nil }
            return (d, r)
        }
        return card("Pacing", "measured rest between sets and how densely you train") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    blockTile("Avg rest",
                              p.avg_rest_seconds.map { "\(restClock($0)) min" } ?? "—", nil)
                    blockTile("Density",
                              p.avg_density.map { "\(trim($0)) kg/min" } ?? "—", nil)
                }
                if weeks.count >= 2 {
                    Chart(weeks, id: \.0) { d, r in
                        LineMark(x: .value("Week", d), y: .value("Rest", r))
                            .foregroundStyle(FG.ember)
                            .lineStyle(StrokeStyle(lineWidth: 2))
                            .interpolationMethod(.monotone)
                        PointMark(x: .value("Week", d), y: .value("Rest", r))
                            .foregroundStyle(FG.ember)
                            .symbolSize(22)
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                            AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                                .font(.system(size: 10)).foregroundStyle(FG.muted)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                            AxisGridLine().foregroundStyle(FG.border.opacity(0.6))
                            AxisValueLabel {
                                if let v = value.as(Double.self) { Text(restClock(v)) }
                            }
                            .font(.system(size: 10).monospacedDigit())
                            .foregroundStyle(FG.muted)
                        }
                    }
                    .frame(height: 140)
                }
            }
        }
    }

    // MARK: time of day

    private func timeOfDayCard(_ items: [TrendTimeOfDay]) -> some View {
        card("Time of day",
             "strength index: your session 1RMs vs that lift's average — 100 is your normal") {
            VStack(spacing: 10) {
                ForEach(items) { t in
                    HStack(spacing: 12) {
                        Text(t.bucket)
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                            .frame(width: 78, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(FG.secondary)
                                if let idx = t.index {
                                    Capsule()
                                        .fill(idx >= 100 ? FG.ember : FG.muted.opacity(0.35))
                                        .frame(width: geo.size.width * min(1, max(0.04, (idx - 85) / 30)))
                                }
                            }
                        }
                        .frame(height: 16)
                        Text(t.index.map { trim($0) } ?? "—")
                            .font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(.white)
                            .frame(width: 34, alignment: .trailing)
                        Text("\(t.workouts)×")
                            .font(.system(size: 11).monospacedDigit()).foregroundStyle(FG.muted)
                            .frame(width: 28, alignment: .trailing)
                    }
                }
            }
        }
    }

    // MARK: helpers

    private func deepYAxis() -> some AxisContent {
        AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
            AxisGridLine().foregroundStyle(FG.border.opacity(0.6))
            AxisValueLabel {
                if let v = value.as(Double.self) {
                    Text(v >= 1000 ? "\(Int((v / 1000).rounded()))k" : trim(v))
                }
            }
            .font(.system(size: 10).monospacedDigit())
            .foregroundStyle(FG.muted)
        }
    }

    private func shortDate(_ iso: String) -> String {
        guard let d = ISO8601DateFormatter().date(from: String(iso.prefix(10)) + "T00:00:00Z") else {
            return String(iso.prefix(10))
        }
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return f.string(from: d)
    }

    private func restClock(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return "\(s / 60):\(String(format: "%02d", s % 60))"
    }
}

/// Multi-series line chart with its own selection tooltip (top lifts,
/// relative strength).
private struct MultiSeriesChart: View {
    let rows: [(Date, String, Double)]
    let names: [String]
    let suffix: String
    @State private var selection: Date?

    var body: some View {
        Chart {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                LineMark(x: .value("Week", row.0), y: .value("Value", row.2),
                         series: .value("Lift", row.1))
                    .foregroundStyle(by: .value("Lift", row.1))
                    .lineStyle(StrokeStyle(lineWidth: 2))
                PointMark(x: .value("Week", row.0), y: .value("Value", row.2))
                    .foregroundStyle(by: .value("Lift", row.1))
                    .symbolSize(22)
            }
            if let sel = selection,
               let near = rows.map(\.0).min(by: {
                   abs($0.timeIntervalSince(sel)) < abs($1.timeIntervalSince(sel))
               }) {
                RuleMark(x: .value("Week", near))
                    .foregroundStyle(FG.muted.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, spacing: 6,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        tip(for: near)
                    }
            }
        }
        .chartXSelection(value: $selection)
        .chartForegroundStyleScale(domain: names,
                                   range: Array(DeepTrendsSections.seriesColors.prefix(max(1, names.count))))
        .chartLegend(.hidden)
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    .font(.system(size: 10)).foregroundStyle(FG.muted)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(FG.border.opacity(0.6))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(v >= 1000 ? "\(Int((v / 1000).rounded()))k" : trim(v))
                    }
                }
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(FG.muted)
            }
        }
        .frame(height: 190)
    }

    private func tip(for week: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Week of \(week.formatted(.dateTime.day().month(.abbreviated)))")
                .font(.system(size: 10)).foregroundStyle(FG.muted)
            ForEach(Array(names.enumerated()), id: \.element) { i, name in
                if let v = rows.first(where: { $0.0 == week && $0.1 == name })?.2 {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(DeepTrendsSections.seriesColors[i % DeepTrendsSections.seriesColors.count])
                            .frame(width: 6, height: 6)
                        Text("\(trim(v))\(suffix)")
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.white)
                    }
                }
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 9).fill(FG.secondary))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(FG.border, lineWidth: 1))
    }
}
