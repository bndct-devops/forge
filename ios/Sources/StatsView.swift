import SwiftUI
import Charts

/// Port of the PWA's StatsPage: Overview (streak, nudges, stalls, totals,
/// highlights, training calendar, year review) and Trends (weekly volume,
/// training days, rep ranges, PRs per month, muscle split, push/pull).
struct StatsView: View {
    @State private var stats: StatsResponse?
    @State private var recordEntries: [RecordEntry] = []
    @State private var weeklyGoal = 3
    // debug hooks: `-stats-trends` opens the Trends tab; `-measure <kind>`
    // pushes a measurement detail at launch
    @State private var tab = CommandLine.arguments.contains("-stats-trends") ? 1 : 0 // 0 overview, 1 trends
    @State private var debugMeasureKind: String? = {
        if let i = CommandLine.arguments.firstIndex(of: "-measure"), i + 1 < CommandLine.arguments.count {
            return CommandLine.arguments[i + 1]
        }
        return nil
    }()
    @State private var showDebugMeasure = false
    @State private var expandedGroup: String?
    @State private var volumeSelection: Date?
    @State private var loading = true

    var body: some View {
        NavigationStack {
            ZStack {
                FG.background.ignoresSafeArea()
                if loading {
                    ProgressView().tint(FG.ember)
                } else if let stats {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 14) {
                                segmented
                                if stats.totals.workouts == 0 {
                                    emptyState
                                } else if tab == 0 {
                                    overview(stats)
                                } else {
                                    trends(stats)
                                }
                                Color.clear.frame(height: 80).id("bottom")
                            }
                            .padding(.horizontal, 18)
                        }
                        .onAppear {
                            // debug hooks: `-scroll-bottom` / `-scroll-headroom` jump on launch
                            let target = CommandLine.arguments.contains("-scroll-bottom") ? "bottom"
                                : CommandLine.arguments.contains("-scroll-headroom") ? "headroom" : nil
                            if let target {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                    proxy.scrollTo(target, anchor: target == "headroom" ? .top : .bottom)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Stats")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: StatsStall.self) { stall in
                ExerciseDetailView(exerciseId: stall.exercise_id, name: stall.name)
            }
            .navigationDestination(isPresented: $showDebugMeasure) {
                MeasureDetailView(kind: debugMeasureKind ?? "Weight")
            }
        }
        .preferredColorScheme(.dark)
        .task {
            await load()
            if debugMeasureKind != nil { showDebugMeasure = true }
        }
        .refreshable { await load() }
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Text("No training data yet")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
            Text("Finish your first workout and your stats will grow here.")
                .font(.system(size: 13)).foregroundStyle(FG.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var segmented: some View {
        PillSegmented(options: ["Overview", "Trends"], selection: $tab)
    }

    // MARK: - overview

    @ViewBuilder
    private func overview(_ s: StatsResponse) -> some View {
        streakCard(s)
        ForEach(s.nudges ?? []) { n in
            HStack(spacing: 10) {
                Image(systemName: "moon").font(.system(size: 14)).foregroundStyle(FG.muted)
                (Text("No ") + Text(n.group).fontWeight(.semibold) + Text(" work in \(n.days) days"))
                    .font(.system(size: 14)).foregroundStyle(.white)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(FG.card))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(FG.border, lineWidth: 1))
        }
        if let stalls = s.stalls, !stalls.isEmpty {
            stallsCard(stalls)
        }
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            tile("Workouts", "\(s.totals.workouts)")
            tile("Total volume", fmtVolume(s.totals.volume))
            tile("Working sets", "\(s.totals.sets)")
            tile("PRs", "\(s.totals.prs)")
        }
        if let e = s.extras { highlightsCard(e, since: s.totals.since) }
        recordsLink
        calendarCard(s.calendar)
        if let year = s.year { yearCard(year) }
    }

    private func streakCard(_ s: StatsResponse) -> some View {
        let thisWeek = s.weeks.last?.workouts ?? 0
        return HStack(spacing: 12) {
            Image(systemName: "flame.fill")
                .font(.system(size: 20)).foregroundStyle(FG.ember)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 12).fill(FG.emberSoft))
            VStack(alignment: .leading, spacing: 3) {
                Text("\(s.streak_weeks) week\(s.streak_weeks == 1 ? "" : "s") streak")
                    .font(.system(size: 17, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                Text(thisWeek >= weeklyGoal
                     ? "weekly goal hit — \(thisWeek) workout\(thisWeek == 1 ? "" : "s") this week"
                     : "\(thisWeek) of \(weeklyGoal) workouts this week")
                    .font(.system(size: 13)).foregroundStyle(FG.muted)
                HStack(spacing: 4) {
                    ForEach(0..<max(weeklyGoal, 1), id: \.self) { i in
                        Capsule()
                            .fill(i < thisWeek ? FG.ember : FG.secondary)
                            .frame(height: 6)
                    }
                }
                .padding(.top, 3)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(FG.card))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .stroke(s.streak_weeks > 0 ? FG.ember.opacity(0.35) : FG.border, lineWidth: 1))
    }

    private func stallsCard(_ stalls: [StatsStall]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "chart.line.downtrend.xyaxis")
                    .font(.system(size: 12)).foregroundStyle(FG.muted)
                Text("Stalled lifts")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
            }
            .padding(.bottom, 2)
            ForEach(stalls) { st in
                NavigationLink(value: st) {
                    HStack {
                        (Text(st.name).fontWeight(.semibold).foregroundStyle(.white)
                         + Text("  stuck at \(trim(st.weight)) kg").foregroundStyle(FG.muted))
                            .font(.system(size: 14))
                            .lineLimit(1)
                        Spacer()
                        Text("\(st.sessions) sessions")
                            .font(.system(size: 12).monospacedDigit()).foregroundStyle(FG.muted)
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
            Text("same top weight, rep target missed — a deload or variation may help")
                .font(.system(size: 11)).foregroundStyle(FG.muted)
                .padding(.top, 2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(FG.card))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(FG.border, lineWidth: 1))
    }

    private func highlightsCard(_ e: StatsExtras, since: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            highlightRow("repeat", "Frequency", "\(trim(e.avg_per_week))× / week", nil)
            highlightRow("timer", "Average session", fmtDuration(e.avg_duration_seconds), "· \(fmtVolume(e.avg_volume))")
            highlightRow("hourglass", "Time under iron", fmtDuration(e.total_time_seconds), nil)
            highlightRow("flame", "Longest streak", "\(e.longest_streak_weeks) week\(e.longest_streak_weeks == 1 ? "" : "s")", nil)
            if let top = e.top_exercise {
                highlightRow("dumbbell", "Most trained", top.name, "· \(top.sessions) sessions")
            }
            if let day = e.busiest_weekday {
                highlightRow("calendar", "Favourite day", day, nil)
            }
            highlightRow("chart.line.uptrend.xyaxis", "This month", fmtVolume(e.month_volume),
                         e.prev_month_volume > 0
                            ? "· \(e.month_volume >= e.prev_month_volume ? "+" : "")\(Int(((e.month_volume - e.prev_month_volume) / e.prev_month_volume * 100).rounded()))% vs last"
                            : nil)
            if let since, let d = ISO8601DateFormatter().date(from: String(since.prefix(19)) + "Z") {
                highlightRow("scalemass", "Training since", d.formatted(.dateTime.month(.wide).year()), nil)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(FG.card))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(FG.border, lineWidth: 1))
    }

    private func highlightRow(_ icon: String, _ label: String, _ value: String, _ hint: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13)).foregroundStyle(FG.ember)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 9).fill(FG.emberSoft))
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.system(size: 11)).foregroundStyle(FG.muted)
                (Text(value).fontWeight(.semibold).foregroundStyle(.white)
                 + Text(hint.map { " \($0)" } ?? "").foregroundStyle(FG.muted))
                    .font(.system(size: 14))
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 6)
    }

    private var recordsLink: some View {
        HStack(spacing: 10) {
            NavigationLink {
                RecordsListView(entries: recordEntries)
            } label: {
                navTile("trophy", "Records", "all-time bests")
            }
            .buttonStyle(Pressable())
            NavigationLink {
                MeasureListView()
            } label: {
                navTile("ruler", "Measurements", "body tracking")
            }
            .buttonStyle(Pressable())
        }
    }

    private func navTile(_ icon: String, _ title: String, _ sub: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15)).foregroundStyle(FG.ember)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 10).fill(FG.emberSoft))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Text(sub).font(.system(size: 12)).foregroundStyle(FG.muted).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(FG.card))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(FG.border, lineWidth: 1))
    }

    // MARK: calendar heatmap

    private func calendarCard(_ days: [StatsCalendarDay]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Training calendar")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
            CalendarHeatmap(days: days)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(FG.card))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(FG.border, lineWidth: 1))
    }

    // MARK: year review

    private func yearCard(_ y: YearReview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: "\(y.year) so far")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                miniTile("Workouts", "\(y.workouts)")
                miniTile("Volume", fmtVolume(y.volume))
                miniTile("Working sets", "\(y.sets)")
                miniTile("PRs", "\(y.prs)")
            }
            VStack(alignment: .leading, spacing: 0) {
                if let pr = y.biggest_pr {
                    highlightRow("trophy", "Biggest PR", "\(trim(pr.weight)) kg × \(pr.reps)", "· \(pr.name)")
                }
                if let top = y.top_exercise {
                    highlightRow("dumbbell", "Most trained", top.name, "· \(top.sessions) sessions")
                }
                highlightRow("flame", "Longest streak", "\(y.longest_streak_weeks) week\(y.longest_streak_weeks == 1 ? "" : "s")", nil)
                highlightRow("calendar", "Biggest month", y.busiest_month.name, "· \(fmtVolume(y.busiest_month.volume))")
            }
            if y.months.count > 1 {
                let maxV = max(1, y.months.map(\.volume).max() ?? 1)
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(y.months) { m in
                        VStack(spacing: 2) {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(m.volume > 0 ? FG.ember : FG.secondary)
                                .frame(height: max(2, m.volume / maxV * 44))
                            Text(m.month).font(.system(size: 9)).foregroundStyle(FG.muted)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 64)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(FG.card))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(FG.border, lineWidth: 1))
    }

    // MARK: - trends

    @ViewBuilder
    private func trends(_ s: StatsResponse) -> some View {
        // PWA section order: volume → deep analytics → days/ranges → PRs → split
        weeklyVolumeCard(s)
        DeepTrendsSections(trends: s.trends)
        trainingDaysCard(s.trends.weekdays)
        repRangesCard(s.trends.rep_ranges, days: s.split_days)
        prsPerMonthCard(s.trends.prs_by_month)
        muscleSplitCard(s)
        if let balance = pushPull(s) { pushPullCard(balance, days: s.split_days) }
    }

    private func weeklyVolumeCard(_ s: StatsResponse) -> some View {
        let weeks: [(Date, StatsWeek)] = s.weeks.compactMap { w in
            guard let d = ISO8601DateFormatter().date(from: w.week_start + "T00:00:00Z") else { return nil }
            return (d, w)
        }
        let rpeColor = Color(red: 0.427, green: 0.529, blue: 0.671)
        let hasRpe = weeks.contains { $0.1.avg_rpe != nil }
        let maxVol = max(1, weeks.map(\.1.volume).max() ?? 1)
        return chartCard("Weekly volume") {
            if hasRpe {
                HStack(spacing: 14) {
                    HStack(spacing: 5) {
                        Circle().fill(FG.ember).frame(width: 8, height: 8)
                        Text("Volume").font(.system(size: 11)).foregroundStyle(FG.muted)
                    }
                    HStack(spacing: 5) {
                        Circle().fill(rpeColor).frame(width: 8, height: 8)
                        Text("Avg RPE").font(.system(size: 11)).foregroundStyle(FG.muted)
                    }
                }
            }
            Chart {
                ForEach(weeks, id: \.1.id) { d, w in
                    BarMark(x: .value("Week", d, unit: .weekOfYear), y: .value("Volume", w.volume))
                        .foregroundStyle(FG.ember)
                        .cornerRadius(3)
                }
                ForEach(weeks, id: \.1.id) { d, w in
                    // RPE (5–10) mapped onto the volume scale — one axis per chart
                    if let rpe = w.avg_rpe {
                        LineMark(x: .value("Week", d, unit: .weekOfYear),
                                 y: .value("Avg RPE", (min(10, max(5, rpe)) - 5) / 5 * maxVol),
                                 series: .value("s", "rpe"))
                            .foregroundStyle(rpeColor)
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                        PointMark(x: .value("Week", d, unit: .weekOfYear),
                                  y: .value("Avg RPE", (min(10, max(5, rpe)) - 5) / 5 * maxVol))
                            .foregroundStyle(rpeColor)
                            .symbolSize(20)
                    }
                }
                if let sel = volumeSelection,
                   let near = weeks.min(by: {
                       abs($0.0.timeIntervalSince(sel)) < abs($1.0.timeIntervalSince(sel))
                   }) {
                    RuleMark(x: .value("Week", near.0, unit: .weekOfYear))
                        .foregroundStyle(FG.muted.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .annotation(position: .top, spacing: 6,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            ChartTip(title: "Week of \(near.0.formatted(.dateTime.day().month(.abbreviated)))",
                                     value: fmtVolume(near.1.volume),
                                     secondary: [
                                        "\(near.1.workouts) workout\(near.1.workouts == 1 ? "" : "s")",
                                        near.1.avg_rpe.map { "avg RPE \(trim($0))" },
                                     ].compactMap { $0 }.joined(separator: " · "))
                        }
                }
            }
            .chartXSelection(value: $volumeSelection)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                        .font(.system(size: 10)).foregroundStyle(FG.muted)
                }
            }
            .chartYAxis { yAxisMarks(compact: true) }
            .frame(height: 170)
        }
    }

    private func trainingDaysCard(_ weekdays: [TrendWeekday]) -> some View {
        chartCard("Training days") {
            Chart(weekdays) { d in
                BarMark(x: .value("Day", d.day), y: .value("Workouts", d.workouts), width: .fixed(22))
                    .foregroundStyle(FG.ember)
                    .cornerRadius(3)
            }
            .chartXScale(domain: weekdays.map(\.day))
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel().font(.system(size: 10)).foregroundStyle(FG.muted)
                }
            }
            .chartYAxis { yAxisMarks(compact: false) }
            .frame(height: 140)
        }
    }

    private func repRangesCard(_ ranges: [TrendRepRange], days: Int) -> some View {
        let maxSets = max(1, ranges.map(\.sets).max() ?? 1)
        return VStack(alignment: .leading, spacing: 3) {
            Text("Rep ranges").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
            Text("working sets, last \(days) days").font(.system(size: 12)).foregroundStyle(FG.muted)
            VStack(spacing: 10) {
                ForEach(ranges) { r in
                    barRow(label: r.range, labelWidth: 48, value: r.sets, maxValue: maxSets)
                }
            }
            .padding(.top, 10)
            Text("reps per working set").font(.system(size: 12)).foregroundStyle(FG.muted).padding(.top, 10)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(FG.card))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(FG.border, lineWidth: 1))
    }

    private func prsPerMonthCard(_ months: [TrendPRMonth]) -> some View {
        chartCard("PRs per month") {
            Chart(months) { m in
                BarMark(x: .value("Month", m.month), y: .value("PRs", m.prs), width: .fixed(22))
                    .foregroundStyle(FG.gold)
                    .cornerRadius(3)
            }
            .chartXScale(domain: months.map(\.month))
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel().font(.system(size: 10)).foregroundStyle(FG.muted)
                }
            }
            .chartYAxis { yAxisMarks(compact: false) }
            .frame(height: 140)
        }
    }

    private func muscleSplitCard(_ s: StatsResponse) -> some View {
        let maxSets = max(1, s.muscle_groups.map(\.sets).max() ?? 1)
        return VStack(alignment: .leading, spacing: 3) {
            Text("Muscle split").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
            Text("working sets, last \(s.split_days) days").font(.system(size: 12)).foregroundStyle(FG.muted)
            VStack(spacing: 10) {
                if s.muscle_groups.isEmpty {
                    Text("No working sets in this window yet.")
                        .font(.system(size: 13)).foregroundStyle(FG.muted)
                }
                ForEach(s.muscle_groups) { g in
                    VStack(spacing: 6) {
                        Button {
                            withAnimation(.spring(duration: 0.3)) {
                                expandedGroup = expandedGroup == g.group ? nil : g.group
                            }
                        } label: {
                            barRow(label: g.group, labelWidth: 80, value: g.sets, maxValue: maxSets)
                        }
                        .buttonStyle(.plain)
                        if expandedGroup == g.group, let trend = s.muscle_trend[g.group] {
                            muscleTrend(trend)
                        }
                    }
                }
            }
            .padding(.top, 10)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(FG.card))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(FG.border, lineWidth: 1))
    }

    private func muscleTrend(_ weeks: [MuscleTrendWeek]) -> some View {
        let maxSets = max(1, weeks.map(\.sets).max() ?? 1)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(weeks) { w in
                    VStack(spacing: 2) {
                        Text(w.sets > 0 ? "\(w.sets)" : " ")
                            .font(.system(size: 9).monospacedDigit()).foregroundStyle(FG.muted)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(w.sets > 0 ? FG.ember : FG.secondary)
                            .frame(height: max(2, Double(w.sets) / Double(maxSets) * 40))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Text("sets per week, last \(weeks.count) weeks")
                .font(.system(size: 10)).foregroundStyle(FG.muted)
        }
        .padding(.leading, 92)
    }

    private struct PushPull {
        let rows: [(String, Int)]
        let maxSets: Int
        let ratio: String
        let note: String?
    }

    private func pushPull(_ s: StatsResponse) -> PushPull? {
        func sets(_ name: String) -> Int { s.muscle_groups.first { $0.group == name }?.sets ?? 0 }
        let press = sets("Chest") + sets("Shoulders")
        let pull = sets("Back")
        let legs = sets("Legs")
        guard press + pull > 0 else { return nil }
        let note: String?
        if pull == 0 || Double(press) / Double(pull) > 1.5 {
            note = "pressing-heavy — your shoulders would thank you for more rows and pulldowns"
        } else if pull > 0 && Double(press) / Double(pull) < 0.67 {
            note = "pull-heavy — room for more pressing if that is not deliberate"
        } else {
            note = nil
        }
        return PushPull(
            rows: [("Press", press), ("Pull", pull), ("Legs", legs)],
            maxSets: max(1, press, pull, legs),
            ratio: pull > 0 ? String(format: "%.1f", Double(press) / Double(pull)) : "∞",
            note: note
        )
    }

    private func pushPullCard(_ b: PushPull, days: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Push / pull balance").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
            Text("Chest + Shoulders vs Back — working sets, last \(days) days")
                .font(.system(size: 12)).foregroundStyle(FG.muted)
            VStack(spacing: 10) {
                ForEach(b.rows, id: \.0) { label, sets in
                    barRow(label: label, labelWidth: 80, value: sets, maxValue: b.maxSets)
                }
            }
            .padding(.top, 10)
            Text(b.note ?? "press : pull = \(b.ratio) : 1 — a reasonable balance")
                .font(.system(size: 12)).foregroundStyle(FG.muted).padding(.top, 10)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(FG.card))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(FG.border, lineWidth: 1))
    }

    // MARK: - shared pieces

    private func chartCard(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(FG.card))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(FG.border, lineWidth: 1))
    }

    private func yAxisMarks(compact: Bool) -> some AxisContent {
        AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
            AxisGridLine().foregroundStyle(FG.border.opacity(0.6))
            AxisValueLabel {
                if let v = value.as(Double.self) {
                    Text(compact && v >= 1000 ? "\(Int((v / 1000).rounded()))k" : trim(v))
                }
            }
            .font(.system(size: 10).monospacedDigit())
            .foregroundStyle(FG.muted)
        }
    }

    private func barRow(label: String, labelWidth: CGFloat, value: Int, maxValue: Int) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                .frame(width: labelWidth, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(FG.secondary)
                    Capsule().fill(FG.ember)
                        .frame(width: max(4, geo.size.width * Double(value) / Double(maxValue)))
                }
            }
            .frame(height: 16)
            Text("\(value)")
                .font(.system(size: 13).monospacedDigit()).foregroundStyle(FG.muted)
                .frame(width: 30, alignment: .trailing)
        }
    }

    private func tile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 11)).foregroundStyle(FG.muted)
            Text(value).font(.system(size: 17, weight: .semibold).monospacedDigit()).foregroundStyle(.white)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(FG.card))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(FG.border, lineWidth: 1))
    }

    private func miniTile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 10)).foregroundStyle(FG.muted)
            Text(value).font(.system(size: 15, weight: .semibold).monospacedDigit()).foregroundStyle(.white)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(FG.secondary))
    }

    private func load() async {
        async let statsTask = ForgeAPI.stats()
        async let recordsTask = ForgeAPI.records()
        async let meTask = ForgeAPI.me()
        stats = try? await statsTask
        recordEntries = (try? await recordsTask) ?? []
        weeklyGoal = (try? await meTask)?.weekly_goal ?? 3
        loading = false
    }
}

// MARK: - helpers shared with other stats surfaces

func fmtVolume(_ volume: Double) -> String {
    if volume >= 10000 { return "\(trim((volume / 100).rounded() / 10))k kg" }
    return "\(Int(volume.rounded())) kg"
}

func fmtDuration(_ totalSeconds: Int) -> String {
    let s = max(0, totalSeconds)
    let h = s / 3600
    let m = (s % 3600) / 60
    if h > 0 { return "\(h)h \(m)m" }
    if m > 0 { return s % 60 > 0 ? "\(m)m \(s % 60)s" : "\(m)m" }
    return "\(s)s"
}

// MARK: - GitHub-style training calendar

/// Monday-aligned week columns × 7 day rows at fixed 12px cells; shows as
/// many of the most recent weeks as fit the width.
private struct CalendarHeatmap: View {
    let days: [StatsCalendarDay]

    private let cell: CGFloat = 12
    private let gap: CGFloat = 3
    private let labelCol: CGFloat = 30

    var body: some View {
        GeometryReader { geo in
            let fitWeeks = max(8, Int((geo.size.width - labelCol + gap) / (cell + gap)))
            let allWeeks = stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
            let weeks = Array(allWeeks.suffix(fitWeeks))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 0) {
                    Color.clear.frame(width: labelCol, height: 1)
                    ForEach(Array(weeks.enumerated()), id: \.offset) { i, _ in
                        Text(monthLabel(weeks: weeks, index: i))
                            .font(.system(size: 9)).foregroundStyle(FG.muted)
                            .fixedSize()
                            .frame(width: cell + gap, alignment: .leading)
                            .clipped(antialiased: false)
                    }
                }
                .frame(height: 11)
                HStack(alignment: .top, spacing: gap) {
                    VStack(alignment: .trailing, spacing: gap) {
                        ForEach(Array(["Mon", "", "Wed", "", "Fri", "", ""].enumerated()), id: \.offset) { _, d in
                            Text(d).font(.system(size: 9)).foregroundStyle(FG.muted)
                                .frame(width: labelCol - gap, height: cell, alignment: .trailing)
                        }
                    }
                    ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                        VStack(spacing: gap) {
                            ForEach(week) { d in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(heatColor(d.workouts))
                                    .frame(width: cell, height: cell)
                            }
                        }
                    }
                }
                HStack(spacing: 5) {
                    Spacer()
                    Text("Less").font(.system(size: 10)).foregroundStyle(FG.muted)
                    ForEach(0..<3, id: \.self) { n in
                        RoundedRectangle(cornerRadius: 3).fill(heatColor(n)).frame(width: 10, height: 10)
                    }
                    Text("More").font(.system(size: 10)).foregroundStyle(FG.muted)
                }
                .padding(.top, 4)
            }
        }
        .frame(height: 11 + 4 + 7 * 12 + 6 * 3 + 4 + 18)
    }

    private func heatColor(_ workouts: Int) -> Color {
        workouts == 0 ? FG.secondary : workouts == 1 ? FG.ember.opacity(0.55) : FG.ember
    }

    private func monthLabel(weeks: [[StatsCalendarDay]], index: Int) -> String {
        guard let first = weeks[index].first else { return "" }
        let month = String(first.date.dropFirst(5).prefix(2))
        if index > 0, let prev = weeks[index - 1].first,
           String(prev.date.dropFirst(5).prefix(2)) == month {
            return ""
        }
        let names = ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun",
                     "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return names[Int(month) ?? 0]
    }
}

// MARK: - records list (pushed from Overview)

struct RecordsListView: View {
    let entries: [RecordEntry]
    @State private var query = ""

    private var filtered: [RecordEntry] {
        query.isEmpty ? entries : entries.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        ZStack {
            FG.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(filtered) { r in
                        NavigationLink {
                            ExerciseDetailView(exerciseId: r.exercise_id, name: r.name)
                        } label: {
                            recordRow(r)
                        }
                        .buttonStyle(Pressable())
                    }
                    Color.clear.frame(height: 40)
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
            }
        }
        .navigationTitle("Records")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query)
        .preferredColorScheme(.dark)
    }

    private func recordRow(_ r: RecordEntry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(r.name).font(.system(size: 14, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                Text("\(r.muscle_group ?? "") · \(r.sessions) sessions")
                    .font(.system(size: 11)).foregroundStyle(FG.muted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let bw = r.best_weight {
                    Text("\(trim(bw.weight)) kg × \(bw.reps)")
                        .font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(.white)
                }
                if let rm = r.best_1rm {
                    Text("1RM \(trim(rm.value)) kg")
                        .font(.system(size: 11).monospacedDigit()).foregroundStyle(FG.muted)
                }
            }
        }
        .padding(13)
        .background(RoundedRectangle(cornerRadius: 13).fill(FG.card))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(FG.border, lineWidth: 1))
    }
}
