import Foundation

/// Bounded QWERTY evidence for dictionary candidates, not an autocomplete dictionary.
/// This score is an edit cost, not a probability. Call only for native misspellings.
public enum KeyboardTypoPolicy {
    private static let positions: [Character: (Double, Double)] = {
        var result: [Character: (Double, Double)] = [:]
        for (row, text, offset) in [(0, "qwertyuiop", 0.0), (1, "asdfghjkl", 0.25), (2, "zxcvbnm", 0.75)] {
            for (column, key) in text.enumerated() { result[key] = (Double(column) + offset, Double(row)) }
        }
        return result
    }()

    public static func neighbors(_ a: Character, _ b: Character) -> Bool {
        guard a != b, let lhs = positions[a], let rhs = positions[b] else { return false }
        return hypot(lhs.0 - rhs.0, lhs.1 - rhs.1) <= 1.3
    }

    public static func cost(_ source: String, _ target: String, proximity: Bool) -> Double {
        let a = Array(source.lowercased()), b = Array(target.lowercased())
        guard a.count <= 32, b.count <= 32 else { return .infinity }
        var rows = Array(repeating: Array(repeating: 0.0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { rows[i][0] = Double(i) }
        for j in 0...b.count { rows[0][j] = Double(j) }
        guard !a.isEmpty, !b.isEmpty else { return Double(max(a.count, b.count)) }
        for i in 1...a.count {
            for j in 1...b.count {
                let substitution = a[i-1] == b[j-1] ? 0.0 : (proximity && neighbors(a[i-1], b[j-1]) ? 0.55 : 1.2)
                rows[i][j] = min(rows[i-1][j] + 1, rows[i][j-1] + 1, rows[i-1][j-1] + substitution)
                if i > 1, j > 1, a[i-1] == b[j-2], a[i-2] == b[j-1] {
                    rows[i][j] = min(rows[i][j], rows[i-2][j-2] + 0.7)
                }
            }
        }
        return rows[a.count][b.count]
    }

    /// A plural noun frame can distinguish neighboring final keys from singular/verb
    /// alternatives. Restrict to native rank 1 and an otherwise identical stem.
    public static func pluralReplacement(for original: String, native: String?, guesses: [String], prefix: String, proximity: Bool) -> String? {
        guard proximity, let native, guesses.first == native, native.hasSuffix("s"),
              original.count >= 5, original.dropLast() == native.dropLast(),
              let last = original.last, neighbors(last, "s"),
              prefix.last == " " else { return nil }
        let before = prefix.split(separator: " ").last.map(String.init)?.lowercased() ?? ""
        guard ["many", "several", "these", "those", "some", "more", "fewer", "multiple", "numerous", "other",
               "spelling", "typing", "grammar", "punctuation", "made", "makes", "make"].contains(before) else { return nil }
        return native
    }

    /// Require native agreement plus a clear weighted margin. Never rerank an arbitrary
    /// dictionary or infer a word solely from nearby keys. Only ASCII prose participates.
    public static func replacement(for original: String, native: String?, guesses: [String], proximity: Bool) -> String? {
        guard (5...24).contains(original.count), original.allSatisfy({ $0.isASCII && $0.isLetter }),
              !original.dropFirst().contains(where: \.isUppercase), let native,
              (3...26).contains(native.count), native.allSatisfy({ $0.isASCII && $0.isLetter }),
              !native.dropFirst().contains(where: \.isUppercase),
              original.first?.isUppercase == true || native.first?.isUppercase != true else { return nil }
        let source = original.lowercased(), target = native.lowercased()
        let distance = CorrectionPolicy.editDistance(Array(source), Array(target))
        guard distance == 2, source.count >= 6, source.first == target.first, source.suffix(3) == target.suffix(3) else { return nil }
        let score = cost(source, target, proximity: proximity)
        guard score <= 1.6 else { return nil }
        // Broad one-edit proximity choices regressed the corpus (amoung/amount,
        // reacing/reading). Leave those to context; proximity alone cannot decide them.
        guard proximity else { return nil }
        let alternatives = Set(guesses.prefix(5).map { $0.lowercased() }).filter { $0 != target }
        guard !alternatives.isEmpty else { return nil }
        for other in alternatives {
            if cost(source, other, proximity: proximity) - score < 0.4 { return nil }
        }
        return original.first?.isUppercase == true ? target.prefix(1).uppercased() + target.dropFirst() : target
    }
}
