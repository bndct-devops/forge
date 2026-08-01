import Foundation

/// Exercise names carry punctuation nobody types: "Plate-Loaded",
/// "Single-Arm", "(Volume)". `localizedCaseInsensitiveContains` makes the
/// hyphen mandatory, so "plate loaded" finds nothing. Matching normalises
/// both sides and requires every query word to appear somewhere in the name,
/// in any order — "plate loaded", "plateloaded" and "plate chest" all find
/// "Plate-Loaded Incline Chest Press". Mirrors frontend/src/lib/search.ts.
enum ExerciseSearch {
    static func normalize(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        let cleaned = folded.map { $0.isLetter || $0.isNumber ? $0 : " " }
        return String(cleaned).split(separator: " ").joined(separator: " ")
    }

    /// Precompiles the query so a list filter normalises it once, not per row.
    static func matcher(for query: String) -> (String) -> Bool {
        let tokens = normalize(query).split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return { _ in true } }
        return { name in
            let spaced = normalize(name)
            // Squashed lets a token span a separator the user left out
            let squashed = spaced.replacingOccurrences(of: " ", with: "")
            return tokens.allSatisfy { spaced.contains($0) || squashed.contains($0) }
        }
    }

    static func matches(_ name: String, query: String) -> Bool {
        matcher(for: query)(name)
    }
}
