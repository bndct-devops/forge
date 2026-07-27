import SwiftUI
import Charts

/// Port of the PWA's MeasureListPage / MeasureDetailPage: body measurements
/// with trend tiles, logged-vs-trend chart, entry management.
struct MeasureListView: View {
    @State private var kinds: [MeasureKind] = []
    @State private var loading = true

    var body: some View {
        ZStack {
            FG.background.ignoresSafeArea()
            if loading {
                ProgressView().tint(FG.ember)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(kinds.enumerated()), id: \.element.id) { i, k in
                            NavigationLink {
                                MeasureDetailView(kind: k.kind)
                            } label: {
                                HStack {
                                    Text(k.kind)
                                        .font(.system(size: 15, weight: .medium)).foregroundStyle(.white)
                                    Spacer()
                                    if let latest = k.latest {
                                        Text("\(trim(latest.value)) \(measureUnit(k.kind))")
                                            .font(.system(size: 14, weight: .semibold).monospacedDigit())
                                            .foregroundStyle(.white)
                                        Text(relativeMeasureDate(latest.measured_at))
                                            .font(.system(size: 13)).foregroundStyle(FG.muted)
                                    } else {
                                        Text("—").font(.system(size: 14)).foregroundStyle(FG.muted)
                                    }
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 11)).foregroundStyle(FG.muted)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 14)
                            }
                            .buttonStyle(.plain)
                            if i < kinds.count - 1 {
                                Divider().overlay(FG.border.opacity(0.5)).padding(.leading, 16)
                            }
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 14).fill(FG.card))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(FG.border, lineWidth: 1))
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                }
            }
        }
        .navigationTitle("Measurements")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .task {
            kinds = (try? await ForgeAPI.measurements()) ?? []
            loading = false
        }
    }
}

struct MeasureDetailView: View {
    let kind: String
    @State private var entries: [MeasureEntry] = []
    @State private var trend: MeasureTrend?
    @State private var loading = true
    @State private var adding = false
    @State private var value = ""
    @State private var when = Date()
    @State private var chartSelection: Date?

    private var unit: String { measureUnit(kind) }

    var body: some View {
        ZStack {
            FG.background.ignoresSafeArea()
            if loading {
                ProgressView().tint(FG.ember)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let t = trend, t.trend != nil { trendTiles(t) }
                        chartCard
                        entriesList
                        Color.clear.frame(height: 30)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                }
            }
        }
        .navigationTitle(kind)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    value = ""
                    when = Date()
                    adding = true
                } label: {
                    Image(systemName: "plus").foregroundStyle(FG.ember)
                }
            }
        }
        .sheet(isPresented: $adding) { addSheet }
        .preferredColorScheme(.dark)
        .task { await load() }
    }

    private func trendTiles(_ t: MeasureTrend) -> some View {
        HStack(spacing: 8) {
            trendTile("TREND", t.trend.map { "\(trim($0)) \(unit)" } ?? "—",
                      t.bmi.map { "BMI \(trim($0))" })
            trendTile("PER WEEK", t.rate_per_week.map { "\($0 > 0 ? "+" : "")\(trim($0)) \(unit)" } ?? "—", nil)
            trendTile("28 DAYS", t.change_28d.map { "\($0 > 0 ? "+" : "")\(trim($0)) \(unit)" } ?? "—", nil)
        }
    }

    private func trendTile(_ label: String, _ value: String, _ sub: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 10, weight: .semibold)).tracking(0.5).foregroundStyle(FG.muted)
            Text(value).font(.system(size: 15, weight: .semibold).monospacedDigit()).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.7)
            if let sub {
                Text(sub).font(.system(size: 11).monospacedDigit()).foregroundStyle(FG.muted)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(FG.card))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(FG.border, lineWidth: 1))
    }

    private struct ChartRow: Identifiable {
        let id: String
        let date: Date
        let actual: Double
        let trend: Double?
    }

    private var chartRows: [ChartRow] {
        let iso = ISO8601DateFormatter()
        func parse(_ s: String) -> Date? {
            iso.date(from: String(s.prefix(19)) + "Z")
        }
        if let t = trend, t.points.count >= 2 {
            return t.points.compactMap { p in
                parse(p.measured_at).map { ChartRow(id: p.measured_at, date: $0, actual: p.actual, trend: p.trend) }
            }
        }
        return entries.reversed().compactMap { e in
            parse(e.measured_at).map { ChartRow(id: "\(e.id)", date: $0, actual: e.value, trend: nil) }
        }
    }

    @ViewBuilder
    private var chartCard: some View {
        let rows = chartRows
        if rows.count >= 2 {
            VStack(alignment: .leading, spacing: 10) {
                if trend?.points.count ?? 0 >= 2 {
                    HStack(spacing: 14) {
                        legendDot(FG.muted, "Logged")
                        legendDot(FG.ember, "Trend")
                    }
                }
                Chart {
                    ForEach(rows) { r in
                        LineMark(x: .value("Date", r.date), y: .value("Logged", r.actual), series: .value("s", "logged"))
                            .foregroundStyle(FG.muted.opacity(0.45))
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                            .interpolationMethod(.monotone)
                        PointMark(x: .value("Date", r.date), y: .value("Logged", r.actual))
                            .foregroundStyle(FG.muted.opacity(0.6))
                            .symbolSize(16)
                    }
                    ForEach(rows) { r in
                        if let t = r.trend {
                            LineMark(x: .value("Date", r.date), y: .value("Trend", t), series: .value("s", "trend"))
                                .foregroundStyle(FG.ember)
                                .lineStyle(StrokeStyle(lineWidth: 2))
                                .interpolationMethod(.monotone)
                        }
                    }
                    if let sel = chartSelection,
                       let near = rows.min(by: {
                           abs($0.date.timeIntervalSince(sel)) < abs($1.date.timeIntervalSince(sel))
                       }) {
                        RuleMark(x: .value("Date", near.date))
                            .foregroundStyle(FG.muted.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .annotation(position: .top, spacing: 6,
                                        overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                ChartTip(title: near.date.formatted(.dateTime.day().month(.abbreviated)),
                                         value: "\(trim(near.actual)) \(unit)",
                                         secondary: near.trend.map { "trend \(trim($0)) \(unit)" })
                            }
                    }
                }
                .chartXSelection(value: $chartSelection)
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                            .font(.system(size: 10)).foregroundStyle(FG.muted)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine().foregroundStyle(FG.border.opacity(0.6))
                        AxisValueLabel().font(.system(size: 10).monospacedDigit()).foregroundStyle(FG.muted)
                    }
                }
                .frame(height: 180)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(FG.card))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(FG.border, lineWidth: 1))
        }
    }

    private func legendDot(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.system(size: 11)).foregroundStyle(FG.muted)
        }
    }

    @ViewBuilder
    private var entriesList: some View {
        if entries.isEmpty {
            Text("No entries yet — add your first \(kind.lowercased()) measurement.")
                .font(.system(size: 13)).foregroundStyle(FG.muted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .stroke(FG.border, style: StrokeStyle(lineWidth: 1, dash: [5])))
        } else {
            VStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { i, e in
                    HStack {
                        Text("\(trim(e.value)) \(unit)")
                            .font(.system(size: 14, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.white)
                        Spacer()
                        Text(relativeMeasureDate(e.measured_at))
                            .font(.system(size: 13)).foregroundStyle(FG.muted)
                        Button {
                            Task {
                                try? await ForgeAPI.deleteMeasurement(id: e.id)
                                entries.removeAll { $0.id == e.id }
                                trend = try? await ForgeAPI.measurementTrend(kind: kind)
                            }
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 13)).foregroundStyle(FG.muted)
                                .padding(6)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    if i < entries.count - 1 {
                        Divider().overlay(FG.border.opacity(0.5)).padding(.leading, 16)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 14).fill(FG.card))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(FG.border, lineWidth: 1))
        }
    }

    private var addSheet: some View {
        NavigationStack {
            ZStack {
                FG.background.ignoresSafeArea()
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Value (\(unit))")
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(.white)
                        TextField("", text: $value)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 16).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14).frame(height: 48)
                            .background(RoundedRectangle(cornerRadius: 12).fill(FG.card))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(FG.border, lineWidth: 1))
                    }
                    DatePicker("When", selection: $when)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .tint(FG.ember)
                    Button {
                        let parsed = Double(value.replacingOccurrences(of: ",", with: "."))
                        guard let parsed, parsed > 0 else { return }
                        Task {
                            try? await ForgeAPI.addMeasurement(kind: kind, value: parsed, measuredAt: when)
                            adding = false
                            await load()
                        }
                    } label: {
                        Text("Save")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .background(RoundedRectangle(cornerRadius: 14).fill(FG.ember))
                            .foregroundStyle(.black.opacity(0.8))
                    }
                    .disabled(value.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity(value.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                    Spacer()
                }
                .padding(18)
            }
            .navigationTitle("Add \(kind.lowercased())")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { adding = false }.foregroundStyle(FG.muted)
                }
            }
        }
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
    }

    private func load() async {
        entries = (try? await ForgeAPI.measurements(kind: kind)) ?? []
        // Height is a constant, not a trend — the endpoint 404s it by design
        if kind != "Height" {
            trend = try? await ForgeAPI.measurementTrend(kind: kind)
        }
        loading = false
    }
}

func measureUnit(_ kind: String) -> String {
    if kind == "Weight" { return "kg" }
    if kind == "Body fat" { return "%" }
    return "cm"
}

func relativeMeasureDate(_ iso: String) -> String {
    guard let d = ISO8601DateFormatter().date(from: String(iso.prefix(19)) + "Z") else {
        return String(iso.prefix(10))
    }
    let days = Calendar.current.dateComponents([.day], from: d, to: Date()).day ?? 0
    if days == 0 { return "Today" }
    if days == 1 { return "Yesterday" }
    if days < 7 { return "\(days)d ago" }
    let f = DateFormatter()
    f.dateFormat = "d MMM"
    return f.string(from: d)
}
