import Foundation

/// Identifies a prose word that should start with a capital: a completed word after an
/// unambiguous sentence ending, or the first word of a field whose start the caller has
/// verified. The caller owns the feature toggle, ignored/custom rules, field-start
/// evidence (focus, caret, total length) and focused-field validation.
public enum SentenceCapitalization {
    /// Returns the word to capitalize, including a single-letter word such as "i" or "a".
    /// `caret` and the returned range use UTF-16 offsets, matching Accessibility APIs.
    /// A sentence-ending period, question mark, or exclamation followed by whitespace is
    /// required unless `atFieldStart` is true and only whitespace or opening quotes and
    /// brackets precede the word in `text`. `text` must then begin at the field's start.
    public static func candidate(in text: String, caret: Int, atFieldStart: Bool = false) -> CorrectionCandidate? {
        guard caret > 0, caret <= text.utf16.count,
              let caretRange = Range(NSRange(location: caret, length: 0), in: text) else { return nil }
        let prefix = text[..<caretRange.lowerBound]
        guard let last = prefix.last, CorrectionPolicy.isDelimiter(last) else { return nil }
        var end = prefix.index(before: prefix.endIndex)
        guard end > prefix.startIndex else { return nil }
        if last == " ", prefix[prefix.index(before: end)] == " " { return nil }
        while end > prefix.startIndex, closingPunctuation.contains(prefix[prefix.index(before: end)]) {
            end = prefix.index(before: end)
        }

        var start = end
        var count = 0
        while start > prefix.startIndex {
            let previous = prefix.index(before: start)
            if isWhitespace(prefix[previous]) { break }
            count += 1
            guard count <= 64 else { return nil }
            start = previous
        }
        while start < end, openingQuotesAndBrackets.contains(prefix[start]) {
            start = prefix.index(after: start)
        }
        guard start < end else { return nil }
        let word = String(prefix[start..<end])
        guard isWord(word, maximumLength: 32), word.first?.isLowercase == true,
              !word.dropFirst().contains(where: { $0.isUppercase }),
              followsSentenceEnd(in: prefix, wordStart: start) || (atFieldStart && startsField(prefix, wordStart: start))
        else { return nil }
        return CorrectionCandidate(original: word, range: NSRange(start..<end, in: text))
    }

    /// The unfinished first word of an otherwise empty field, for immediate capitalization
    /// as it is typed: `text` is everything from the verified field start to the caret and
    /// must consist of optional whitespace/opening quotes or brackets plus one lowercase
    /// ASCII word (at most 24 letters, one interior apostrophe). Anything else — a capital,
    /// emoji, digit, symbol, backtick, path or URL character, a completed word — is nil.
    public static func fieldStartCandidate(in text: String) -> CorrectionCandidate? {
        guard !text.isEmpty, text.utf16.count <= 64 else { return nil }
        var start = text.startIndex
        while start < text.endIndex, isWhitespace(text[start]) || openingQuotesAndBrackets.contains(text[start]) {
            start = text.index(after: start)
        }
        guard start < text.endIndex else { return nil }
        let word = String(text[start...])
        guard (1...24).contains(word.count), let first = word.first, first.isASCII, first.isLowercase,
              word.last?.isLetter == true else { return nil }
        var apostrophes = 0
        for character in word {
            if character == "'" || character == "’" {
                apostrophes += 1
                guard apostrophes <= 1 else { return nil }
            } else {
                guard character.isASCII, character.isLetter, character.isLowercase else { return nil }
            }
        }
        return CorrectionCandidate(original: word, range: NSRange(start..<text.endIndex, in: text))
    }

    /// Capitalizes only the first letter; the remaining spelling and casing are preserved.
    /// This can also be applied to a spelling correction selected for an eligible candidate.
    public static func replacement(for word: String) -> String? {
        guard word.count <= 120, !word.isEmpty,
              word.split(separator: " ", omittingEmptySubsequences: false).allSatisfy({ isWord(String($0), maximumLength: 64) }),
              let first = word.first, first.isLowercase else { return nil }
        return String(first).uppercased() + word.dropFirst()
    }

    private static let openingQuotesAndBrackets = "([{\"'“‘«"
    private static let closingQuotesAndBrackets = ")]}\"'”’»"
    private static let closingPunctuation = ".,!?;:)]}\"”»"

    // These endings are ambiguous without understanding the sentence. Leave them alone.
    private static let abbreviations: Set<String> = [
        "mr", "mrs", "ms", "dr", "prof", "sr", "jr", "st", "rev", "hon", "gen", "col", "lt", "sgt", "capt",
        "etc", "vs", "no", "nos", "fig", "figs", "vol", "vols", "pp", "ed", "eds", "dept", "approx", "est",
        "inc", "ltd", "co", "corp", "ave", "blvd", "rd", "mt", "ft", "oz", "lb", "lbs",
        "jan", "feb", "mar", "apr", "jun", "jul", "aug", "sep", "sept", "oct", "nov", "dec"
    ]

    /// Only whitespace and opening quotes/brackets may precede the field's first word.
    private static func startsField(_ prefix: Substring, wordStart: String.Index) -> Bool {
        prefix[..<wordStart].allSatisfy { isWhitespace($0) || openingQuotesAndBrackets.contains($0) }
    }

    private static func followsSentenceEnd(in prefix: Substring, wordStart: String.Index) -> Bool {
        var cursor = wordStart
        while cursor > prefix.startIndex, openingQuotesAndBrackets.contains(prefix[prefix.index(before: cursor)]) {
            cursor = prefix.index(before: cursor)
        }
        let beforeWhitespace = cursor
        while cursor > prefix.startIndex, isWhitespace(prefix[prefix.index(before: cursor)]) {
            cursor = prefix.index(before: cursor)
        }
        guard cursor < beforeWhitespace else { return false }
        while cursor > prefix.startIndex, closingQuotesAndBrackets.contains(prefix[prefix.index(before: cursor)]) {
            cursor = prefix.index(before: cursor)
        }
        guard cursor > prefix.startIndex else { return false }
        var period = prefix.index(before: cursor)
        guard ".!?".contains(prefix[period]), period > prefix.startIndex else { return false }
        let emphatic = prefix[period] == "!" || prefix[period] == "?"
        if emphatic {
            // Treat ?!, !!, and ?? as one ending, but still reject paths/URLs/code
            // in the preceding token rather than mistaking their punctuation for prose.
            while period > prefix.startIndex, "!?".contains(prefix[prefix.index(before: period)]) {
                period = prefix.index(before: period)
            }
        }
        // Dotted initials, domains, decimal numbers, paths, and ellipses fail the plain-word check.
        var tokenStart = period
        var count = 0
        while tokenStart > prefix.startIndex {
            let previous = prefix.index(before: tokenStart)
            if isWhitespace(prefix[previous]) { break }
            count += 1
            guard count <= 128 else { return false }
            tokenStart = previous
        }
        var preceding = String(prefix[tokenStart..<period])
        while let first = preceding.first, openingQuotesAndBrackets.contains(first) { preceding.removeFirst() }
        while let last = preceding.last, closingQuotesAndBrackets.contains(last) { preceding.removeLast() }
        guard isWord(preceding, maximumLength: 64), emphatic || preceding.count > 1 else { return false }
        return emphatic || !abbreviations.contains(UserDictionary.normalizedKey(preceding))
    }

    private static func isWhitespace(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }

    private static func isWord(_ word: String, maximumLength: Int) -> Bool {
        guard (1...maximumLength).contains(word.count), word.first?.isLetter == true,
              word.last?.isLetter == true else { return false }
        var apostrophes = 0
        for character in word {
            if character == "'" || character == "’" {
                apostrophes += 1
                guard apostrophes <= 1 else { return false }
            } else if !character.unicodeScalars.allSatisfy({
                CharacterSet.letters.contains($0) || CharacterSet.nonBaseCharacters.contains($0)
            }) {
                return false
            }
        }
        return true
    }
}
