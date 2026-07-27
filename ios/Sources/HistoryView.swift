import SwiftUI

struct HistoryView: View {
    @State private var mode = 0 // 0 list, 1 calendar
    @State private var workouts: [WorkoutListItem] = []
    @State private var loading = true
    @State private var canLoadMore = true
    @State private var monthAnchor = Date()

    var body: some View {
        NavigationStack {
            ZStack {
                FG.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        segmented
                        if loading {
                            ProgressView().tint(FG.ember).frame(maxWidth: .infinity).padding(.vertical, 40)
                        } else if workouts.isEmpty {
                            Text("No workouts yet.").font(.system(size: 14)).foregroundStyle(FG.muted).padding(.top, 20)
                        } else if mode == 0 {
                            listBody
                        } else {
                            CalendarBody(workouts: workouts, monthAnchor: $monthAnchor)
                        }
                        Color.clear.frame(height: 80)
                    }
                    .padding(.horizontal, 18)
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.large)
        }
        .preferredColorScheme(.dark)
        .task { await load(reset: true) }
        .refreshable { await load(reset: true) }
    }

    private var segmented: some View {
        PillSegmented(options: ["List", "Calendar"], selection: $mode)
    }

    private var listBody: some View {
        VStack(spacing: 10) {
            ForEach(workouts) { w in
                NavigationLink {
                    WorkoutDetailView(workoutId: w.id) { await load(reset: true) }
                } label: {
                    workoutRow(w)
                }
                .buttonStyle(Pressable())
            }
            if canLoadMore {
                Button {
                    Task { await load(reset: false) }
                } label: {
                    Text("Load more")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(FG.ember)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func workoutRow(_ w: WorkoutListItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(w.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                Spacer()
                Text(fmtDate(w.started_at))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(FG.muted)
            }
            HStack(spacing: 8) {
                if let d = w.duration_seconds { statChip("\(d / 60) min") }
                if let v = w.total_volume { statChip("\(trim(v)) kg") }
                if let s = w.total_sets { statChip("\(s) sets") }
                if let p = w.pr_count, p > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "trophy.fill").font(.system(size: 10)).foregroundStyle(FG.gold)
                        Text("\(p)")
                    }
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(FG.gold)
                }
            }
            if let summaries = w.exercise_summaries, !summaries.isEmpty {
                Text(summaries.joined(separator: ", "))
                    .font(.system(size: 12))
                    .foregroundStyle(FG.muted)
                    .lineLimit(2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(FG.card))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(FG.border, lineWidth: 1))
    }

    private func statChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium).monospacedDigit())
            .foregroundStyle(FG.muted)
    }

    private func load(reset: Bool) async {
        if reset {
            workouts = []
            canLoadMore = true
        }
        let page = (try? await ForgeAPI.workouts(limit: 20, offset: workouts.count)) ?? []
        workouts += page
        canLoadMore = page.count == 20
        loading = false
    }
}

func fmtDate(_ iso: String) -> String {
    guard let d = ISO8601DateFormatter().date(from: String(iso.prefix(19)) + "Z") else {
        return String(iso.prefix(10))
    }
    let f = DateFormatter()
    f.dateFormat = "EEE d MMM"
    return f.string(from: d)
}

// MARK: - calendar

private struct CalendarBody: View {
    let workouts: [WorkoutListItem]
    @Binding var monthAnchor: Date

    private var calendar: Calendar { Calendar.current }

    private var workoutsByDay: [Int: [WorkoutListItem]] {
        var out: [Int: [WorkoutListItem]] = [:]
        for w in workouts {
            guard let d = ISO8601DateFormatter().date(from: String(w.started_at.prefix(19)) + "Z") else { continue }
            if calendar.isDate(d, equalTo: monthAnchor, toGranularity: .month) {
                out[calendar.component(.day, from: d), default: []].append(w)
            }
        }
        return out
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button {
                    monthAnchor = calendar.date(byAdding: .month, value: -1, to: monthAnchor)!
                } label: {
                    Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold)).foregroundStyle(FG.muted).padding(8)
                }
                Spacer()
                Text(monthTitle)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    monthAnchor = calendar.date(byAdding: .month, value: 1, to: monthAnchor)!
                } label: {
                    Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(FG.muted).padding(8)
                }
            }

            let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
            LazyVGrid(columns: cols, spacing: 6) {
                ForEach(["M", "T", "W", "T", "F", "S", "S"].indices, id: \.self) { i in
                    Text(["M", "T", "W", "T", "F", "S", "S"][i])
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(FG.muted)
                }
                ForEach(0..<leadingBlanks, id: \.self) { _ in Color.clear.frame(height: 40) }
                ForEach(1...daysInMonth, id: \.self) { day in
                    let has = workoutsByDay[day] != nil
                    if has, let w = workoutsByDay[day]?.first {
                        NavigationLink {
                            WorkoutDetailView(workoutId: w.id) {}
                        } label: {
                            dayCell(day, active: true)
                        }
                        .buttonStyle(.plain)
                    } else {
                        dayCell(day, active: false)
                    }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(FG.card))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(FG.border, lineWidth: 1))
    }

    private func dayCell(_ day: Int, active: Bool) -> some View {
        Text("\(day)")
            .font(.system(size: 13, weight: active ? .bold : .regular).monospacedDigit())
            .foregroundStyle(active ? .black.opacity(0.8) : FG.muted)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(RoundedRectangle(cornerRadius: 8).fill(active ? FG.ember : FG.secondary.opacity(0.4)))
    }

    private var monthTitle: String {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f.string(from: monthAnchor)
    }

    private var daysInMonth: Int {
        calendar.range(of: .day, in: .month, for: monthAnchor)?.count ?? 30
    }

    private var leadingBlanks: Int {
        let comps = calendar.dateComponents([.year, .month], from: monthAnchor)
        let first = calendar.date(from: comps)!
        return (calendar.component(.weekday, from: first) + 5) % 7
    }
}
