import SwiftUI
import Charts

/// Port of the PWA's ExerciseDetailPage: pinned note, variation chips,
/// record tiles, muscle map, metric chart with ranges, training percentages,
/// and per-workout history.
struct ExerciseDetailView: View {
    @State private var exerciseId: Int
    @State private var title: String
    @State private var stats: ExerciseStats?
    @State private var includeFamily = false
    @State private var metric = "best_1rm"
    @State private var range = "all"
    @State private var noteText = ""
    @State private var noteFocusedOnce = false
    @FocusState private var noteFocused: Bool

    init(exerciseId: Int, name: String) {
        _exerciseId = State(initialValue: exerciseId)
        _title = State(initialValue: name)
    }

    private var isBodyweight: Bool { stats?.exercise.equipment == "Bodyweight" }

    private var metricOptions: [(String, String)] {
        isBodyweight
            ? [("best_reps", "Reps"), ("best_weight", "Weight"), ("volume", "Volume")]
            : [("best_1rm", "1RM"), ("best_weight", "Weight"), ("volume", "Volume")]
    }

    private var metricLabel: String {
        ["best_1rm": "Est. 1RM", "best_weight": "Best weight",
         "best_reps": "Most reps", "volume": "Volume"][metric] ?? metric
    }

    var body: some View {
        ZStack {
            FG.background.ignoresSafeArea()
            if let stats {
                content(stats)
            } else {
                ProgressView().tint(FG.ember)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .task(id: "\(exerciseId)-\(includeFamily)") { await load() }
    }

    private func content(_ s: ExerciseStats) -> some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                subtitle(s)
                noteField(s)
                if !s.variations.isEmpty { variationChips(s) }

                if (s.records?.times_performed ?? 0) == 0 {
                    muscleCard(s)
                    VStack(spacing: 4) {
                        Text("No sets logged yet")
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        Text("Records and progress will appear once you train this exercise.")
                            .font(.system(size: 13)).foregroundStyle(FG.muted)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                } else if let r = s.records {
                    tiles(r)
                    muscleCard(s)
                    chartCard(s).id("chart")
                    if let rm = r.best_1rm { percentages(rm) }
                    historySection(s)
                }
                Color.clear.frame(height: 30).id("bottom")
            }
            .padding(.horizontal, 18)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            // debug hook: `-scroll-bottom` jumps to the end for verification
            let target = CommandLine.arguments.contains("-scroll-bottom") ? "bottom"
                : CommandLine.arguments.contains("-scroll-chart") ? "chart" : nil
            if let target {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    proxy.scrollTo(target, anchor: target == "chart" ? .top : .bottom)
                }
            }
        }
        }
    }

    // MARK: header bits

    private func subtitle(_ s: ExerciseStats) -> some View {
        Text([s.exercise.muscle_group, s.exercise.equipment,
              s.exercise.grip.map { "\($0) grip" },
              s.exercise.is_custom ? "Custom" : nil]
            .compactMap { $0 }.joined(separator: " · "))
            .font(.system(size: 13))
            .foregroundStyle(FG.muted)
            .padding(.top, 4)
    }

    private func noteField(_ s: ExerciseStats) -> some View {
        TextField("Pinned note — cues, seat height, grip width", text: $noteText, axis: .vertical)
            .font(.system(size: 14))
            .foregroundStyle(.white)
            .focused($noteFocused)
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(RoundedRectangle(cornerRadius: 12).fill(FG.card))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(noteFocused ? FG.ember.opacity(0.6) : FG.border, lineWidth: 1))
            .onChange(of: noteFocused) { _, focused in
                if focused { noteFocusedOnce = true }
                if !focused, noteFocusedOnce, noteText != (s.note ?? "") {
                    Task { try? await ForgeAPI.putExerciseNote(id: s.exercise.id, text: noteText) }
                }
            }
    }

    private func variationChips(_ s: ExerciseStats) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Button {
                    includeFamily.toggle()
                } label: {
                    Text(includeFamily ? "All variations" : "+ All variations")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(includeFamily ? .black : FG.ember)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(includeFamily ? FG.ember : FG.emberSoft))
                }
                .buttonStyle(.plain)
                ForEach(s.variations) { v in
                    Button {
                        if v.id != exerciseId {
                            exerciseId = v.id
                            title = v.name
                        }
                    } label: {
                        Text(v.name)
                            .font(.system(size: 13, weight: v.id == exerciseId ? .semibold : .medium))
                            .foregroundStyle(v.id == exerciseId ? FG.ember : .white)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Capsule().fill(v.id == exerciseId ? FG.emberSoft : FG.secondary))
                            .overlay(Capsule().stroke(v.id == exerciseId ? FG.ember : .clear, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: record tiles

    private func tiles(_ r: ExerciseRecords) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            tile("Best weight",
                 r.best_weight.map { "\(trim($0.weight)) kg" } ?? "—",
                 r.best_weight.map { "× \($0.reps)" })
            tile("Est. 1RM (Epley)",
                 r.best_1rm.map { "\(trim($0.value)) kg" } ?? "—",
                 r.best_1rm.flatMap { rm in
                     rm.weight.map { "\(trim($0)) kg × \(rm.reps ?? 0)" }
                 })
            tile("Best set volume",
                 r.best_volume_set.map { "\(trim($0.value)) kg" } ?? "—",
                 r.best_volume_set.flatMap { v in
                     v.weight.map { "\(trim($0)) kg × \(v.reps ?? 0)" }
                 })
            if let br = r.best_reps {
                tile("Most reps (BW)", "\(br.reps) reps", nil)
            }
            tile("Workouts", "\(r.times_performed ?? 0)", nil)
        }
    }

    private func tile(_ label: String, _ value: String, _ sub: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 11)).foregroundStyle(FG.muted)
            Text(value).font(.system(size: 17, weight: .semibold).monospacedDigit()).foregroundStyle(.white)
            if let sub {
                Text(sub).font(.system(size: 11).monospacedDigit()).foregroundStyle(FG.muted)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(FG.card))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(FG.border, lineWidth: 1))
    }

    // MARK: muscle map

    @ViewBuilder
    private func muscleCard(_ s: ExerciseStats) -> some View {
        let worked = Muscles.regions(for: s.exercise.name, group: s.exercise.muscle_group)
        if !worked.primary.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Muscles worked")
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                MuscleMapView(primary: worked.primary, secondary: worked.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text("Primary").foregroundStyle(FG.muted)
                        Text(worked.primary.compactMap { Muscles.label[$0] }.joined(separator: ", "))
                            .fontWeight(.semibold).foregroundStyle(.white)
                    }
                    if !worked.secondary.isEmpty {
                        HStack(spacing: 4) {
                            Text("Secondary").foregroundStyle(FG.muted)
                            Text(worked.secondary.compactMap { Muscles.label[$0] }.joined(separator: ", "))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                    }
                }
                .font(.system(size: 13))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(FG.card))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(FG.border, lineWidth: 1))
        }
    }

    // MARK: chart

    private struct ChartPoint: Identifiable {
        let id: Int
        let date: Date
        let value: Double
    }

    private func chartData(_ s: ExerciseStats) -> [ChartPoint] {
        let cutoff: Date? = {
            switch range {
            case "3m": return Calendar.current.date(byAdding: .day, value: -92, to: Date())
            case "1y": return Calendar.current.date(byAdding: .day, value: -366, to: Date())
            default: return nil
            }
        }()
        let iso = ISO8601DateFormatter()
        return s.chart.enumerated().compactMap { i, c in
            guard let d = iso.date(from: String(c.date.prefix(19)) + "Z")
                    ?? iso.date(from: String(c.date.prefix(10)) + "T00:00:00Z") else { return nil }
            if let cutoff, d < cutoff { return nil }
            let v: Double? = ["best_1rm": c.best_1rm, "best_weight": c.best_weight,
                              "best_reps": c.best_reps, "volume": c.volume][metric] ?? nil
            guard let v else { return nil }
            return ChartPoint(id: i, date: d, value: v)
        }
    }

    private func chartCard(_ s: ExerciseStats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(metricLabel)
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                Spacer()
                HStack(spacing: 2) {
                    ForEach(["3m", "1y", "all"], id: \.self) { r in
                        Button {
                            range = r
                        } label: {
                            Text(r.uppercased())
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(range == r ? FG.ember : FG.muted)
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .background(RoundedRectangle(cornerRadius: 7)
                                    .fill(range == r ? FG.emberSoft : .clear))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 0) {
                ForEach(metricOptions, id: \.0) { value, label in
                    Button {
                        metric = value
                    } label: {
                        Text(label)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(metric == value ? .white : FG.muted)
                            .frame(maxWidth: .infinity).frame(height: 30)
                            .background(RoundedRectangle(cornerRadius: 7)
                                .fill(metric == value ? FG.card : .clear))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 9).fill(FG.secondary))

            let data = chartData(s)
            if data.isEmpty {
                Text("No data in this range.")
                    .font(.system(size: 13)).foregroundStyle(FG.muted)
                    .frame(maxWidth: .infinity).padding(.vertical, 40)
            } else {
                chart(data)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(FG.card))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(FG.border, lineWidth: 1))
    }

    @ViewBuilder
    private func chart(_ data: [ChartPoint]) -> some View {
        Chart(data) { p in
            if metric == "volume" {
                BarMark(x: .value("Date", p.date, unit: .day), y: .value("Volume", p.value))
                    .foregroundStyle(FG.ember)
                    .cornerRadius(3)
            } else {
                LineMark(x: .value("Date", p.date), y: .value(metricLabel, p.value))
                    .foregroundStyle(FG.ember)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Date", p.date), y: .value(metricLabel, p.value))
                    .foregroundStyle(FG.ember)
                    .symbolSize(28)
            }
        }
        .chartYScale(domain: .automatic(includesZero: metric == "volume"))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    .font(.system(size: 10))
                    .foregroundStyle(FG.muted)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(FG.border.opacity(0.6))
                AxisValueLabel()
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(FG.muted)
            }
        }
        .frame(height: 210)
    }

    // MARK: training percentages

    private func percentages(_ rm: Record1RMRef) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Training percentages")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
            Text("of your \(trim(rm.value)) kg estimated 1RM, rounded to 2.5")
                .font(.system(size: 12)).foregroundStyle(FG.muted)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach([95, 90, 85, 80, 75, 70, 65, 60], id: \.self) { pct in
                    VStack(spacing: 1) {
                        Text("\(pct)%").font(.system(size: 11)).foregroundStyle(FG.muted)
                        Text(trim((rm.value * Double(pct) / 100 / 2.5).rounded() * 2.5))
                            .font(.system(size: 14, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 9).fill(FG.secondary))
                }
            }
            .padding(.top, 8)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(FG.card))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(FG.border, lineWidth: 1))
    }

    // MARK: history

    @ViewBuilder
    private func historySection(_ s: ExerciseStats) -> some View {
        if !s.history.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("History")
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                ForEach(s.history) { h in
                    NavigationLink {
                        WorkoutDetailView(workoutId: h.workout_id) { await load() }
                    } label: {
                        historyCard(h)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func historyCard(_ h: ExerciseHistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(h.workout_name)
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                Spacer()
                Text(relativeDate(h.date))
                    .font(.system(size: 12)).foregroundStyle(FG.muted)
            }
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(h.sets.enumerated()), id: \.offset) { i, set in
                    HStack(spacing: 8) {
                        Text("\(i + 1)")
                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                            .foregroundStyle(FG.muted)
                            .frame(width: 16)
                        Text("\(trim(set.weight ?? 0)) kg × \(set.reps)")
                            .font(.system(size: 13).monospacedDigit())
                            .foregroundStyle(FG.muted)
                        if set.is_pr {
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 11)).foregroundStyle(FG.gold)
                        }
                    }
                }
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 13).fill(FG.card))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(FG.border, lineWidth: 1))
    }

    private func relativeDate(_ iso: String) -> String {
        guard let d = ISO8601DateFormatter().date(from: String(iso.prefix(19)) + "Z") else {
            return String(iso.prefix(10))
        }
        let days = Calendar.current.dateComponents([.day], from: d, to: Date()).day ?? 0
        if days == 0 { return "Today" }
        if days == 1 { return "Yesterday" }
        if days < 7 { return "\(days)d ago" }
        return fmtDate(iso)
    }

    // MARK: data

    private func load() async {
        stats = try? await ForgeAPI.exerciseStats(id: exerciseId, family: includeFamily)
        if let s = stats {
            title = s.exercise.name
            noteText = s.note ?? ""
            // bodyweight work has no meaningful 1RM — chart reps instead
            if s.records?.best_1rm == nil, s.records?.best_reps != nil, metric == "best_1rm" {
                metric = "best_reps"
            }
        }
    }
}
