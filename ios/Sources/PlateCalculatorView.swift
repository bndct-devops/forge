import SwiftUI

/// Port of the PWA's PlateCalculator sheet: per-side loading diagram,
/// warm-up ramp, bar weight and plate inventory (synced to the account).
struct PlateCalculatorView: View {
    let initialWeight: Double?
    @Environment(\.dismiss) private var dismiss
    @State private var weightText = ""
    @State private var bar: Double = 0
    @State private var owned: Set<Double> = Set(PlateCalculatorView.allPlates.map(\.weight))
    @State private var configLoaded = false

    // IWF-style colors, softened a touch so they sit inside the theme
    struct Plate {
        let weight: Double
        let color: Color
        let height: Double // fraction of the rack height
    }

    static let allPlates: [Plate] = [
        Plate(weight: 25, color: Color(red: 0.753, green: 0.314, blue: 0.302), height: 0.96),
        Plate(weight: 20, color: Color(red: 0.310, green: 0.427, blue: 0.620), height: 0.96),
        Plate(weight: 15, color: Color(red: 0.722, green: 0.604, blue: 0.247), height: 0.88),
        Plate(weight: 10, color: Color(red: 0.353, green: 0.576, blue: 0.404), height: 0.78),
        Plate(weight: 5, color: Color(red: 0.910, green: 0.894, blue: 0.863), height: 0.62),
        Plate(weight: 2.5, color: Color(red: 0.239, green: 0.224, blue: 0.212), height: 0.48),
        Plate(weight: 1.25, color: Color(red: 0.541, green: 0.522, blue: 0.502), height: 0.38),
    ]
    static let barOptions: [Double] = [0, 20, 15, 10]
    private let step = 2.5

    private var target: Double {
        Double(weightText.replacingOccurrences(of: ",", with: ".")) ?? initialWeight ?? 0
    }

    private var plates: [Plate] { Self.allPlates.filter { owned.contains($0.weight) } }

    private var perSide: [Plate] {
        var side = max(0, (target - bar) / 2)
        var out: [Plate] = []
        for p in plates {
            while side >= p.weight - 1e-9 {
                out.append(p)
                side -= p.weight
            }
        }
        return out
    }

    private var remainder: Double {
        let loaded = perSide.reduce(0) { $0 + $1.weight } * 2 + bar
        return ((target - loaded) * 100).rounded() / 100
    }

    private var counts: [(Double, Int)] {
        var order: [Double] = []
        var map: [Double: Int] = [:]
        for p in perSide {
            if map[p.weight] == nil { order.append(p.weight) }
            map[p.weight, default: 0] += 1
        }
        return order.map { ($0, map[$0]!) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                FG.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        weightRow
                        barDiagram
                        summary
                        if target > bar { warmupRamp }
                        barPicker
                        platePicker
                        Color.clear.frame(height: 20)
                    }
                    .padding(18)
                }
            }
            .navigationTitle("Plate calculator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }.foregroundStyle(FG.ember)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            if weightText.isEmpty, let initialWeight { weightText = trim(initialWeight) }
            if !configLoaded, let raw = (try? await ForgeAPI.me())?.plate_config,
               let data = raw.data(using: .utf8),
               let cfg = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let b = cfg["bar"] as? Double, Self.barOptions.contains(b) { bar = b }
                if let ps = cfg["plates"] as? [Double], !ps.isEmpty { owned = Set(ps) }
                else if let ps = cfg["plates"] as? [Int], !ps.isEmpty { owned = Set(ps.map(Double.init)) }
            }
            configLoaded = true
        }
    }

    private var weightRow: some View {
        HStack(spacing: 12) {
            Spacer()
            stepButton("minus") { adjust(-step) }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                TextField("0", text: $weightText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 24, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(width: 110, height: 44)
                    .background(RoundedRectangle(cornerRadius: 12).fill(FG.card))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(FG.border, lineWidth: 1))
                Text("kg").font(.system(size: 14)).foregroundStyle(FG.muted)
            }
            stepButton("plus") { adjust(step) }
            Spacer()
        }
    }

    private func stepButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(RoundedRectangle(cornerRadius: 11).fill(FG.secondary))
        }
        .buttonStyle(.plain)
    }

    private func adjust(_ delta: Double) {
        weightText = trim(max(bar, ((target + delta) * 100).rounded() / 100))
    }

    // Half the bar, loaded left-to-right
    private var barDiagram: some View {
        GeometryReader { geo in
            let h = geo.size.height
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(FG.muted.opacity(0.6))
                    .frame(width: 32, height: 10)
                Rectangle()
                    .fill(FG.muted.opacity(0.7))
                    .frame(width: 6, height: 16)
                HStack(spacing: 4) {
                    ForEach(Array(perSide.enumerated()), id: \.offset) { _, p in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(p.color)
                            .frame(width: 14, height: h * p.height * 0.82)
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(.black.opacity(0.2), lineWidth: 1))
                    }
                }
                .padding(.leading, 4)
                RoundedRectangle(cornerRadius: 2)
                    .fill(FG.muted.opacity(0.6))
                    .frame(height: 10)
                    .frame(minWidth: 16, maxWidth: .infinity)
                    .padding(.leading, 4)
            }
            .frame(height: h)
        }
        .frame(height: 128)
        .padding(.horizontal, 16)
        .background(RoundedRectangle(cornerRadius: 14).fill(FG.secondary.opacity(0.6)))
    }

    private var summary: some View {
        VStack(spacing: 4) {
            if target < bar {
                Text("Below bar weight").font(.system(size: 14)).foregroundStyle(FG.muted)
            } else if counts.isEmpty {
                Text(bar > 0 ? "Empty bar" : "Nothing to plate")
                    .font(.system(size: 14)).foregroundStyle(FG.muted)
            } else {
                Text("Per side: " + counts.map { "\($0.1) × \(fmtPlate($0.0))" }.joined(separator: "  ·  "))
                    .font(.system(size: 14, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white)
            }
            if remainder > 0 && target >= bar {
                Text("\(trim(remainder)) kg can't be plated with your plates")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(FG.gold)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var warmupRamp: some View {
        var rows: [(String, Double, Int)] = []
        if bar > 0 { rows.append(("Empty bar", bar, 10)) }
        for (pct, reps) in [(0.4, 5), (0.6, 3), (0.8, 2)] {
            let w = max(bar, ((target * pct) / step).rounded() * step)
            if rows.last.map({ w > $0.1 }) ?? true {
                rows.append(("\(Int(pct * 100))%", w, reps))
            }
        }
        return VStack(alignment: .leading, spacing: 6) {
            Text("WARM-UP RAMP")
                .font(.system(size: 11, weight: .semibold)).tracking(0.8)
                .foregroundStyle(FG.muted)
            VStack(spacing: 4) {
                ForEach(rows, id: \.0) { label, w, reps in
                    HStack {
                        Text(label).font(.system(size: 13)).foregroundStyle(FG.muted)
                        Spacer()
                        Text("\(trim(w)) kg × \(reps)")
                            .font(.system(size: 13, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 9).fill(FG.secondary))
                }
                HStack {
                    Text("Working set").font(.system(size: 13, weight: .medium)).foregroundStyle(FG.ember)
                    Spacer()
                    Text("\(trim(target)) kg")
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(FG.ember)
                }
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 9).fill(FG.emberSoft))
            }
        }
    }

    private var barPicker: some View {
        HStack {
            Text("Bar weight").font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
            Spacer()
            Menu {
                ForEach(Self.barOptions, id: \.self) { b in
                    Button {
                        bar = b
                        saveConfig()
                    } label: {
                        if b == bar {
                            Label(b == 0 ? "Not counted" : "\(trim(b)) kg", systemImage: "checkmark")
                        } else {
                            Text(b == 0 ? "Not counted" : "\(trim(b)) kg")
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(bar == 0 ? "Not counted" : "\(trim(bar)) kg")
                        .font(.system(size: 13, weight: .medium))
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 10))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10).fill(FG.card))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(FG.border, lineWidth: 1))
            }
        }
    }

    private var platePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("YOUR PLATES")
                .font(.system(size: 11, weight: .semibold)).tracking(0.8)
                .foregroundStyle(FG.muted)
            FlowChips(plates: Self.allPlates, owned: owned) { w in
                var next = owned
                if next.contains(w) {
                    next.remove(w)
                    if next.isEmpty { return } // at least one plate
                } else {
                    next.insert(w)
                }
                owned = next
                saveConfig()
            }
        }
    }

    private func saveConfig() {
        let cfg: [String: Any] = ["bar": bar, "plates": Array(owned).sorted(by: >)]
        if let data = try? JSONSerialization.data(withJSONObject: cfg),
           let raw = String(data: data, encoding: .utf8) {
            Task { try? await ForgeAPI.updatePlateConfig(raw) }
        }
    }
}

/// Plate weights need two decimals (1.25), unlike set weights.
func fmtPlate(_ w: Double) -> String {
    if w == w.rounded() { return String(Int(w)) }
    var s = String(format: "%.2f", w)
    while s.hasSuffix("0") { s.removeLast() }
    return s
}

private struct FlowChips: View {
    let plates: [PlateCalculatorView.Plate]
    let owned: Set<Double>
    let toggle: (Double) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(plates, id: \.weight) { p in
                let active = owned.contains(p.weight)
                Button {
                    toggle(p.weight)
                } label: {
                    Text(fmtPlate(p.weight))
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .strikethrough(!active)
                        .foregroundStyle(active ? FG.ember : FG.muted.opacity(0.6))
                        .padding(.horizontal, 11).padding(.vertical, 7)
                        .background(Capsule().fill(active ? FG.emberSoft : FG.secondary.opacity(0.6)))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
