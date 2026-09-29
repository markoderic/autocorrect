import Foundation

/// A word immediately before a typed delimiter. The range uses Accessibility's UTF-16 offsets.
public struct CorrectionCandidate: Equatable, Sendable {
    public let original: String
    public let range: NSRange

    public init(original: String, range: NSRange) {
        self.original = original
        self.range = range
    }
}

/// Conservative, side-effect-free rules shared by the keyboard and Accessibility layers.
public enum CorrectionPolicy {
    /// Only ordinary spaces and sentence punctuation trigger a correction. Return and Tab
    /// deliberately do not: they can send a message, submit a form, or move focus.
    public static func isDelimiter(_ character: Character) -> Bool {
        " .,!?;:)]}\"”».".contains(character)
    }

    /// Finds a complete word just before `caret`, expressed as a UTF-16 offset in `text`.
    /// Callers must separately require an empty selection and revalidate the focused field
    /// and its value immediately before applying a replacement. Invalid offsets return nil.
    public static func candidate(in text: String, caret: Int) -> CorrectionCandidate? {
        guard caret > 0, caret <= text.utf16.count,
              let caretRange = Range(NSRange(location: caret, length: 0), in: text) else {
            return nil
        }
        let prefix = text[..<caretRange.lowerBound]
        guard let last = prefix.last, isDelimiter(last) else { return nil }

        // A repeated space must not revisit a word the user already accepted or reverted.
        var end = prefix.index(before: prefix.endIndex)
        guard end > prefix.startIndex else { return nil }
        if last == " ", prefix[prefix.index(before: end)] == " " { return nil }

        // Permit sentence punctuation followed by a space, but never cross whitespace.
        while end > prefix.startIndex, isClosingPunctuation(prefix[prefix.index(before: end)]) {
            end = prefix.index(before: end)
        }
        guard end > prefix.startIndex else { return nil }

        var start = end
        var scanned = 0
        while start > prefix.startIndex {
            let previous = prefix.index(before: start)
            if prefix[previous].unicodeScalars.allSatisfy({ CharacterSet.whitespacesAndNewlines.contains($0) }) {
                break
            }
            scanned += 1
            guard scanned <= 64 else { return nil }
            start = previous
        }

        // Opening quotation marks / brackets are prose. Other prefixes (e.g. @ or /)
        // remain part of the token and are rejected below as likely structured text.
        while start < end, "([\"“«{".contains(prefix[start]) {
            start = prefix.index(after: start)
        }
        guard start < end else { return nil }
        let word = String(prefix[start..<end])
        guard isPlainWord(word), hasSafeCase(word) else { return nil }
        return CorrectionCandidate(original: word, range: NSRange(start..<end, in: text))
    }

    /// Returns a spelling suggestion with the original initial capitalization preserved.
    /// Only one insertion, deletion, substitution, or adjacent transposition is accepted.
    /// Three-letter words require a transposition; two-letter words are left untouched.
    /// This is a confidence gate, not a dictionary: callers must establish that the source
    /// is misspelled and obtain suggestions from a local spell checker first.
    public static func confidentReplacement(for original: String, suggestion: String) -> String? {
        guard isPlainWord(original), hasSafeCase(original), isPlainWord(suggestion),
              hasSafeCase(suggestion) else { return nil }
        let source = original.precomposedStringWithCanonicalMapping.lowercased()
        let target = suggestion.precomposedStringWithCanonicalMapping.lowercased()
        guard source != target else { return nil }
        let left = Array(source)
        let right = Array(target)
        guard left.count >= 3 else { return nil }
        let transposition = isAdjacentTransposition(left, right)
        guard (left.count == 3 && transposition) ||
                (left.count >= 4 && (transposition || isSingleEdit(left, right))) else {
            return nil
        }
        if original.first?.isUppercase == true {
            return target.prefix(1).uppercased() + target.dropFirst()
        }
        // A capitalized suggestion for lowercase input is often a name, not a typo.
        guard suggestion.first?.isUppercase != true else { return nil }
        return target
    }

    private static func isClosingPunctuation(_ character: Character) -> Bool {
        ".,!?;:)]}\"”»".contains(character)
    }

    private static func isPlainWord(_ word: String) -> Bool {
        guard (2...32).contains(word.count), word.first?.isLetter == true,
              word.last?.isLetter == true else { return false }
        var apostrophes = 0
        for character in word {
            if character == "'" || character == "’" {
                apostrophes += 1
                if apostrophes > 1 { return false }
            } else if !character.unicodeScalars.allSatisfy({
                CharacterSet.letters.contains($0) || CharacterSet.nonBaseCharacters.contains($0)
            }) {
                return false
            }
        }
        return true
    }

    private static func hasSafeCase(_ word: String) -> Bool {
        // Reject ALLCAPS and camelCase while accepting lowercase, Initialcase, and scripts
        // without upper/lowercase. Digits and symbols are handled by isPlainWord.
        !word.dropFirst().contains(where: { $0.isUppercase })
    }

    private static func isAdjacentTransposition(_ left: [Character], _ right: [Character]) -> Bool {
        guard left.count == right.count else { return false }
        let mismatches = left.indices.filter { left[$0] != right[$0] }
        guard mismatches.count == 2, mismatches[1] == mismatches[0] + 1 else { return false }
        let index = mismatches[0]
        return left[index] == right[index + 1] && left[index + 1] == right[index]
    }

    private static func isSingleEdit(_ left: [Character], _ right: [Character]) -> Bool {
        guard abs(left.count - right.count) <= 1 else { return false }
        var i = 0
        var j = 0
        var edits = 0
        while i < left.count, j < right.count {
            if left[i] == right[j] {
                i += 1
                j += 1
            } else {
                edits += 1
                if edits > 1 { return false }
                if left.count >= right.count { i += 1 }
                if right.count >= left.count { j += 1 }
            }
        }
        edits += (left.count - i) + (right.count - j)
        return edits == 1
    }
}
