import Foundation

/// Tokenization for scanning existing text. Detection comes from the native checker; these
/// rules decide which tokens may carry a mark: plain lowercase words only. Names (Initialcase),
/// acronyms, mixed case and structured tokens (paths, addresses, code, numbers) never do.
public enum SpellingScan {
    public struct Token: Equatable, Sendable {
        public let range: NSRange
        public let word: String
    }

    private static let opening = "([{\"“«"
    private static let closing = ")]}\"”»" + ".,!?;:"

    /// Eligible words in `text` with UTF-16 ranges local to it. The token that contains or
    /// ends at `activeCaret` is the word being typed and is excluded.
    public static func tokens(in text: String, activeCaret: Int?) -> [Token] {
        var result: [Token] = []
        let nsText = text as NSString
        var index = 0
        let length = nsText.length
        while index < length {
            guard !isWhitespace(nsText.character(at: index)) else { index += 1; continue }
            var end = index
            while end < length, !isWhitespace(nsText.character(at: end)) { end += 1 }
            defer { index = end }
            var start = index
            var stop = end
            while start < stop, opening.contains(Character(UnicodeScalar(nsText.character(at: start)) ?? " ")) { start += 1 }
            while stop > start, closing.contains(Character(UnicodeScalar(nsText.character(at: stop - 1)) ?? " ")) { stop -= 1 }
            // Single quotes double as apostrophes: trim a trailing one only with a matching
            // opener, so a possessive (dogs') never becomes a word.
            if start < stop, let first = UnicodeScalar(nsText.character(at: start)), first == "'" || first == "‘" {
                start += 1
                let closer: UnicodeScalar = first == "‘" ? "’" : "'"
                if start < stop, UnicodeScalar(nsText.character(at: stop - 1)) == closer { stop -= 1 }
            }
            guard start < stop else { continue }
            let word = nsText.substring(with: NSRange(location: start, length: stop - start))
            guard isEligible(word) else { continue }
            if let caret = activeCaret, caret > start, caret <= stop { continue }
            result.append(Token(range: NSRange(location: start, length: stop - start), word: word))
        }
        return result
    }

    /// Marks for tokens whose exact range the native checker reported as misspelled.
    /// `windowStart` makes locations absolute; `accepts` applies caller policy (ignored
    /// words, recognized names, user rules).
    public static func marks(in text: String, windowStart: Int, misspelledRanges: [NSRange],
                             activeCaret: Int?, accepts: (String) -> Bool) -> [SpellingMark] {
        let flagged = Set(misspelledRanges.map { "\($0.location):\($0.length)" })
        return tokens(in: text, activeCaret: activeCaret).compactMap { token in
            guard flagged.contains("\(token.range.location):\(token.range.length)"), accepts(token.word) else { return nil }
            return SpellingMark(location: windowStart + token.range.location, word: token.word)
        }
    }

    private static func isEligible(_ word: String) -> Bool {
        guard (2...32).contains(word.count), word.first?.isLetter == true, word.last?.isLetter == true,
              word.first?.isLowercase == true, !word.contains(where: \.isUppercase) else { return false }
        var apostrophes = 0
        for character in word {
            if character == "'" || character == "’" {
                apostrophes += 1
                if apostrophes > 1 { return false }
            } else if !character.isLetter {
                return false
            }
        }
        return true
    }

    private static func isWhitespace(_ unit: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(unit) else { return false }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }
}
