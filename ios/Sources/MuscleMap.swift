import SwiftUI

// MARK: - SVG path-data parser

/// Parses SVG path data (M/m L/l H/h V/v C/c S/s Q/q T/t A/a Z/z, compressed
/// numbers and arc flags) into a SwiftUI Path. Ports the anatomy figures from
/// the PWA's bodyPaths.ts.
enum SVGPath {
    static func parse(_ d: String) -> Path {
        var path = Path()
        let scanner = Tokenizer(d)
        var cmd: Character = " "
        var current = CGPoint.zero
        var start = CGPoint.zero
        var lastControl: CGPoint?
        var lastQControl: CGPoint?

        while let token = scanner.nextCommandOrNumber(for: cmd) {
            switch token {
            case .command(let c):
                cmd = c
                if c == "Z" || c == "z" {
                    path.closeSubpath()
                    current = start
                    lastControl = nil
                    lastQControl = nil
                }
                continue
            case .number(let first):
                let rel = cmd.isLowercase
                func pt(_ x: Double, _ y: Double) -> CGPoint {
                    rel ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                }
                switch Character(cmd.uppercased()) {
                case "M":
                    let y = scanner.number() ?? 0
                    current = pt(first, y)
                    path.move(to: current)
                    start = current
                    // subsequent implicit pairs are LineTo
                    cmd = rel ? "l" : "L"
                    lastControl = nil; lastQControl = nil
                case "L":
                    let y = scanner.number() ?? 0
                    current = pt(first, y)
                    path.addLine(to: current)
                    lastControl = nil; lastQControl = nil
                case "H":
                    current = CGPoint(x: rel ? current.x + first : first, y: current.y)
                    path.addLine(to: current)
                    lastControl = nil; lastQControl = nil
                case "V":
                    current = CGPoint(x: current.x, y: rel ? current.y + first : first)
                    path.addLine(to: current)
                    lastControl = nil; lastQControl = nil
                case "C":
                    let y1 = scanner.number() ?? 0
                    let c1 = pt(first, y1)
                    let c2 = pt(scanner.number() ?? 0, scanner.number() ?? 0)
                    let end = pt(scanner.number() ?? 0, scanner.number() ?? 0)
                    path.addCurve(to: end, control1: c1, control2: c2)
                    lastControl = c2; lastQControl = nil
                    current = end
                case "S":
                    let y2 = scanner.number() ?? 0
                    let c2 = pt(first, y2)
                    let end = pt(scanner.number() ?? 0, scanner.number() ?? 0)
                    let c1 = lastControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                    path.addCurve(to: end, control1: c1, control2: c2)
                    lastControl = c2; lastQControl = nil
                    current = end
                case "Q":
                    let y1 = scanner.number() ?? 0
                    let c1 = pt(first, y1)
                    let end = pt(scanner.number() ?? 0, scanner.number() ?? 0)
                    path.addQuadCurve(to: end, control: c1)
                    lastQControl = c1; lastControl = nil
                    current = end
                case "T":
                    let y = scanner.number() ?? 0
                    let end = pt(first, y)
                    let c1 = lastQControl.map { CGPoint(x: 2 * current.x - $0.x, y: 2 * current.y - $0.y) } ?? current
                    path.addQuadCurve(to: end, control: c1)
                    lastQControl = c1; lastControl = nil
                    current = end
                case "A":
                    let ry = scanner.number() ?? 0
                    let rotation = scanner.number() ?? 0
                    let largeArc = (scanner.flag() ?? 0) != 0
                    let sweep = (scanner.flag() ?? 0) != 0
                    let end = pt(scanner.number() ?? 0, scanner.number() ?? 0)
                    addArc(&path, from: current, to: end, rx: first, ry: ry,
                           rotation: rotation, largeArc: largeArc, sweep: sweep)
                    lastControl = nil; lastQControl = nil
                    current = end
                default:
                    break
                }
            }
        }
        return path
    }

    /// Endpoint-parameterized elliptical arc → cubic bézier segments
    /// (SVG spec appendix B.2.4).
    private static func addArc(_ path: inout Path, from p0: CGPoint, to p1: CGPoint,
                               rx rxIn: Double, ry ryIn: Double, rotation: Double,
                               largeArc: Bool, sweep: Bool) {
        var rx = abs(rxIn), ry = abs(ryIn)
        if rx < 1e-9 || ry < 1e-9 || (p0.x == p1.x && p0.y == p1.y) {
            path.addLine(to: p1)
            return
        }
        let phi = rotation * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx2 = (p0.x - p1.x) / 2, dy2 = (p0.y - p1.y) / 2
        let x1p = cosPhi * dx2 + sinPhi * dy2
        let y1p = -sinPhi * dx2 + cosPhi * dy2
        // scale radii up if they can't span the endpoints
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            let s = sqrt(lambda)
            rx *= s; ry *= s
        }
        let rxs = rx * rx, rys = ry * ry
        let num = rxs * rys - rxs * y1p * y1p - rys * x1p * x1p
        let den = rxs * y1p * y1p + rys * x1p * x1p
        var coef = sqrt(max(0, num / den))
        if largeArc == sweep { coef = -coef }
        let cxp = coef * rx * y1p / ry
        let cyp = -coef * ry * x1p / rx
        let cx = cosPhi * cxp - sinPhi * cyp + (p0.x + p1.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (p0.y + p1.y) / 2

        func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
            let dot = ux * vx + uy * vy
            let len = sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy))
            var a = acos(min(1, max(-1, dot / len)))
            if ux * vy - uy * vx < 0 { a = -a }
            return a
        }
        let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var dTheta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep && dTheta > 0 { dTheta -= 2 * .pi }
        if sweep && dTheta < 0 { dTheta += 2 * .pi }

        let segments = max(1, Int(ceil(abs(dTheta) / (.pi / 2))))
        let delta = dTheta / Double(segments)
        let t = 4 / 3.0 * tan(delta / 4)
        var theta = theta1
        for _ in 0..<segments {
            let cos1 = cos(theta), sin1 = sin(theta)
            let theta2 = theta + delta
            let cos2 = cos(theta2), sin2 = sin(theta2)
            func onEllipse(_ c: Double, _ s: Double) -> CGPoint {
                CGPoint(x: cx + rx * c * cosPhi - ry * s * sinPhi,
                        y: cy + rx * c * sinPhi + ry * s * cosPhi)
            }
            func derivative(_ c: Double, _ s: Double) -> CGPoint {
                CGPoint(x: -rx * s * cosPhi - ry * c * sinPhi,
                        y: -rx * s * sinPhi + ry * c * cosPhi)
            }
            let e1 = onEllipse(cos1, sin1), e2 = onEllipse(cos2, sin2)
            let d1 = derivative(cos1, sin1), d2 = derivative(cos2, sin2)
            path.addCurve(to: e2,
                          control1: CGPoint(x: e1.x + t * d1.x, y: e1.y + t * d1.y),
                          control2: CGPoint(x: e2.x - t * d2.x, y: e2.y - t * d2.y))
            theta = theta2
        }
    }

    // MARK: tokenizer

    enum Token {
        case command(Character)
        case number(Double)
    }

    final class Tokenizer {
        private let chars: [Character]
        private var i = 0

        init(_ s: String) { chars = Array(s) }

        private func skipSeparators() {
            while i < chars.count, chars[i] == " " || chars[i] == "," || chars[i] == "\n" || chars[i] == "\t" {
                i += 1
            }
        }

        /// Next token: an explicit command letter, or a number (implicit
        /// repetition of the previous command).
        func nextCommandOrNumber(for _: Character) -> Token? {
            skipSeparators()
            guard i < chars.count else { return nil }
            let c = chars[i]
            if c.isLetter {
                i += 1
                return .command(c)
            }
            guard let n = number() else { return nil }
            return .number(n)
        }

        /// Parses one number, honouring SVG's compressed forms:
        /// ".44.43" = 0.44, 0.43 and "-.9-.1" = -0.9, -0.1.
        func number() -> Double? {
            skipSeparators()
            guard i < chars.count else { return nil }
            var s = ""
            var seenDot = false
            var seenExp = false
            if chars[i] == "-" || chars[i] == "+" { s.append(chars[i]); i += 1 }
            while i < chars.count {
                let c = chars[i]
                if c.isNumber {
                    s.append(c); i += 1
                } else if c == "." {
                    if seenDot { break }
                    seenDot = true; s.append(c); i += 1
                } else if (c == "e" || c == "E") && !seenExp {
                    seenExp = true; seenDot = true; s.append(c); i += 1
                    if i < chars.count, chars[i] == "-" || chars[i] == "+" { s.append(chars[i]); i += 1 }
                } else {
                    break
                }
            }
            return Double(s)
        }

        /// Arc flags may be jammed together with the following number ("01-.9"):
        /// consume exactly one digit.
        func flag() -> Double? {
            skipSeparators()
            guard i < chars.count, chars[i] == "0" || chars[i] == "1" else { return number() }
            let v = chars[i] == "1" ? 1.0 : 0.0
            i += 1
            return v
        }
    }
}

// MARK: - muscle inference (port of frontend/src/lib/muscles.ts)

struct MusclePattern {
    let regex: NSRegularExpression
    let primary: [String]
    let secondary: [String]

    init(_ pattern: String, _ primary: [String], _ secondary: [String]) {
        // patterns are audited; a failure here is a programming error
        regex = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        self.primary = primary
        self.secondary = secondary
    }
}

enum Muscles {
    static let label: [String: String] = [
        "chest": "Chest", "front-delts": "Front delts", "rear-delts": "Rear delts",
        "biceps": "Biceps", "triceps": "Triceps", "forearms": "Forearms",
        "abs": "Abs", "obliques": "Obliques", "traps": "Traps", "lats": "Lats",
        "lower-back": "Lower back", "glutes": "Glutes", "quads": "Quads",
        "hamstrings": "Hamstrings", "adductors": "Adductors", "calves": "Calves",
    ]

    private static let groupRegions: [String: [String]] = [
        "Chest": ["chest"],
        "Back": ["lats", "traps", "lower-back"],
        "Shoulders": ["front-delts", "rear-delts"],
        "Arms": ["biceps", "triceps", "forearms"],
        "Legs": ["quads", "glutes", "hamstrings", "adductors", "calves"],
        "Core": ["abs", "obliques"],
        "Full Body": ["chest", "lats", "front-delts", "quads", "glutes", "hamstrings", "abs"],
    ]

    // Order matters: earlier patterns win ("leg curl" before "curl",
    // "upright row" before "row").
    private static let patterns: [MusclePattern] = [
        MusclePattern("leg curl|nordic", ["hamstrings"], ["calves"]),
        MusclePattern("leg extension", ["quads"], []),
        MusclePattern("calf|calves", ["calves"], []),
        MusclePattern("glute ham raise", ["hamstrings"], ["glutes", "calves"]),
        MusclePattern("hip thrust|glute|kickback", ["glutes"], ["hamstrings"]),
        MusclePattern("abduction", ["glutes"], []),
        MusclePattern("adduction", ["adductors"], []),
        MusclePattern("rdl|romanian|stiff.?leg", ["hamstrings", "glutes"], ["lower-back", "forearms", "traps"]),
        MusclePattern("good morning", ["hamstrings", "glutes", "lower-back"], []),
        MusclePattern("rack pull", ["traps", "lower-back", "glutes"], ["hamstrings", "forearms", "lats"]),
        MusclePattern("deadlift", ["hamstrings", "glutes", "lower-back"], ["lats", "traps", "forearms", "quads"]),
        MusclePattern("clean|snatch", ["quads", "glutes", "hamstrings", "traps"], ["front-delts", "lower-back", "calves", "forearms"]),
        MusclePattern("kettlebell swing", ["glutes", "hamstrings"], ["lower-back", "abs", "front-delts", "forearms"]),
        MusclePattern("farmer", ["forearms", "traps"], ["abs", "quads", "glutes", "calves"]),
        MusclePattern("thruster", ["quads", "glutes", "front-delts"], ["triceps", "hamstrings", "abs"]),
        MusclePattern("squat|leg press|lunge|hack|step.?up", ["quads", "glutes"], ["hamstrings", "adductors", "lower-back"]),
        MusclePattern("back extension|hyperextension", ["lower-back"], ["glutes", "hamstrings"]),
        MusclePattern("face pull|rear delt|reverse fly|reverse pec deck", ["rear-delts"], ["traps"]),
        MusclePattern("shrug", ["traps"], []),
        MusclePattern("upright row", ["front-delts", "traps"], ["biceps", "forearms"]),
        MusclePattern("pullover", ["lats", "chest"], ["triceps"]),
        MusclePattern("straight.?arm", ["lats"], ["triceps"]),
        MusclePattern("pulldown|pull.?up|chin.?up", ["lats"], ["biceps", "rear-delts"]),
        MusclePattern("row", ["lats", "traps"], ["biceps", "rear-delts", "lower-back"]),
        MusclePattern("front raise", ["front-delts"], []),
        MusclePattern("lateral raise|side raise|y raise", ["front-delts", "rear-delts"], []),
        MusclePattern("push press", ["front-delts"], ["triceps", "quads", "glutes"]),
        MusclePattern("landmine press", ["front-delts"], ["chest", "triceps"]),
        MusclePattern("overhead press|shoulder press|military|arnold|seated (barbell|dumbbell) press", ["front-delts"], ["triceps", "traps"]),
        MusclePattern("bench dip|machine dip|close.?grip bench", ["triceps"], ["chest", "front-delts"]),
        MusclePattern("tricep|pushdown|skull|extension", ["triceps"], []),
        MusclePattern("pec deck", ["chest"], ["front-delts"]),
        MusclePattern("fly", ["chest"], ["front-delts"]),
        MusclePattern("bench|chest press|push.?up|dip|dumbbell press|incline press|decline press", ["chest"], ["front-delts", "triceps"]),
        MusclePattern("reverse\\s.*curl|wrist", ["forearms"], ["biceps"]),
        MusclePattern("curl", ["biceps"], ["forearms"]),
        MusclePattern("side plank", ["obliques"], ["abs"]),
        MusclePattern("woodchop|russian twist|pallof", ["obliques"], ["abs"]),
        MusclePattern("crunch|sit.?up|plank|rollout|leg raise|knee raise|ab wheel|dead bug", ["abs"], ["obliques"]),
    ]

    static func regions(for name: String, group: String?) -> (primary: [String], secondary: [String]) {
        let range = NSRange(name.startIndex..., in: name)
        for p in patterns where p.regex.firstMatch(in: name, range: range) != nil {
            return (p.primary, p.secondary)
        }
        return (groupRegions[group ?? ""] ?? [], [])
    }
}

// MARK: - view

struct MuscleMapView: View {
    let primary: [String]
    let secondary: [String]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            figure(paths: BodyPaths.front, offsetX: 0, label: "FRONT")
            figure(paths: BodyPaths.back, offsetX: 724, label: "BACK")
        }
        .frame(maxWidth: .infinity)
    }

    private func figure(paths: [BodyPath], offsetX: CGFloat, label: String) -> some View {
        VStack(spacing: 6) {
            FigureCanvas(paths: paths, offsetX: offsetX, primary: primary, secondary: secondary)
                .aspectRatio(724.0 / 1448.0, contentMode: .fit)
                .frame(maxWidth: 150)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .tracking(2)
                .foregroundStyle(FG.muted)
        }
    }
}

private struct FigureCanvas: View {
    let paths: [BodyPath]
    let offsetX: CGFloat
    let primary: [String]
    let secondary: [String]

    // parse once per figure, cached across renders
    private static var cache: [CGFloat: [(String?, Path)]] = [:]

    private var parsed: [(String?, Path)] {
        if let hit = Self.cache[offsetX] { return hit }
        let out = paths.map { ($0.region, SVGPath.parse($0.d)) }
        Self.cache[offsetX] = out
        return out
    }

    var body: some View {
        let shapes = parsed
        Canvas { ctx, size in
            let scale = size.width / 724.0
            ctx.translateBy(x: -offsetX * scale, y: 0)
            ctx.scaleBy(x: scale, y: scale)
            for (region, path) in shapes {
                let color: Color
                if let r = region, primary.contains(r) {
                    color = FG.ember
                } else if let r = region, secondary.contains(r) {
                    color = FG.ember.opacity(0.35)
                } else if region != nil {
                    color = .white.opacity(0.09)
                } else {
                    color = .white.opacity(0.05)
                }
                ctx.fill(path, with: .color(color))
            }
        }
    }
}
