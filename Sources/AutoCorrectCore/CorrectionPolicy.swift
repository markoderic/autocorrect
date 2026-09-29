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
    /// `caseExceptions` contains explicit custom correction keys normalized with
    /// `UserDictionary.normalizedKey`. Only the capitalization rule is relaxed for them.
    public static func candidate(in text: String, caret: Int, caseExceptions: Set<String> = []) -> CorrectionCandidate? {
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
        guard (word == "i" || (word == "I" && caseExceptions.contains("i")) || isPlainWord(word)),
              hasSafeCase(word) || caseExceptions.contains(UserDictionary.normalizedKey(word)) else { return nil }
        return CorrectionCandidate(original: word, range: NSRange(start..<end, in: text))
    }

    /// Returns a spelling suggestion with the original initial capitalization preserved.
    /// Only one insertion, deletion, substitution, or adjacent transposition is accepted.
    /// Three-letter words require a transposition; two-letter words are left untouched.
    /// This is a confidence gate, not a dictionary: callers must establish that the source
    /// is misspelled and obtain suggestions from a local spell checker first.
    public static func confidentReplacement(for original: String, suggestion: String) -> String? {
        validatedReplacement(for: original, suggestion: suggestion, allowShortInsertion: false)
    }

    /// Chooses from the native spell checker's contextual correction and ranked guesses.
    /// Call only after the native checker identifies `original` as misspelled. For three
    /// ASCII consonants, prefer a guess that preserves every typed letter and inserts one
    /// vowel (for example, "ths" → "this") over a substitution. First consider the
    /// native automatic recommendation with a conservative edit-distance gate. Three-letter
    /// words may gain one letter or transpose two; substitutions and deletions stay blocked.
    /// Beyond that gate, its first ranked guess can qualify: one edit for 5+ letters, or
    /// two for 8+ letters with matching ends. A native two-edit automatic recommendation
    /// may also qualify within the first three guesses when it is uniquely closest.
    /// Another top-five guess at equal or closer distance blocks this fallback. These are
    /// safety heuristics, not calibrated probabilities or proof of the writer's intent.
    public static func preferredAutomaticReplacement(for original: String, systemCorrection: String?, guesses: [String]) -> String? {
        guard isPlainWord(original), hasSafeCase(original) else { return nil }
        let source = Array(UserDictionary.normalizedKey(original))
        if source.count == 3, source.allSatisfy({ "bcdfghjklmnpqrstvwxz".contains($0) }) {
            for guess in guesses {
                let target = Array(UserDictionary.normalizedKey(guess))
                guard isSingleVowelInsertion(source, target),
                      let replacement = validatedReplacement(for: original, suggestion: guess, allowShortInsertion: true) else {
                    continue
                }
                return replacement
            }
        }
        if let systemCorrection,
           let replacement = validatedReplacement(for: original, suggestion: systemCorrection, allowShortInsertion: true) {
            return replacement
        }
        return rankedGuessReplacement(for: original, systemCorrection: systemCorrection, guesses: guesses)
    }

    private static func rankedGuessReplacement(for original: String, systemCorrection: String?, guesses: [String]) -> String? {
        guard original.count >= 5, let first = guesses.first else { return nil }
        let source = Array(UserDictionary.normalizedKey(original))
        var selected = first
        if let systemCorrection, isPlainWord(systemCorrection) {
            let systemKey = UserDictionary.normalizedKey(systemCorrection)
            if guesses.prefix(3).contains(where: { UserDictionary.normalizedKey($0) == systemKey }),
               editDistance(source, Array(systemKey)) == 2 {
                selected = systemCorrection
            }
        }
        guard isPlainWord(selected), hasSafeCase(selected),
              original.first?.isUppercase == true || selected.first?.isUppercase != true else { return nil }
        let targetKey = UserDictionary.normalizedKey(selected)
        let target = Array(targetKey)
        let distance = editDistance(source, target)
        guard distance > 0, distance <= 2 else { return nil }
        if distance == 2 {
            guard source.count >= 8, target.count >= 8, source.first == target.first, source.last == target.last,
                  distance * 4 <= source.count else { return nil }
        }
        // Native rank alone is not a confidence score. Demand a full edit of separation
        // from every other top-five guess and any different automatic recommendation.
        let competitors = Array(guesses.prefix(5)) + (systemCorrection.map { [$0] } ?? [])
        for competitor in competitors where isPlainWord(competitor) {
            let key = UserDictionary.normalizedKey(competitor)
            if key != targetKey, editDistance(source, Array(key)) <= distance { return nil }
        }
        return original.first?.isUppercase == true
            ? targetKey.prefix(1).uppercased() + targetKey.dropFirst() : targetKey
    }

    /// Optimal-string-alignment distance: insertion, deletion, substitution, and adjacent
    /// transposition. Work is bounded by our 32-character word limit and five native guesses.
    /// Sources: https://norvig.com/spell-correct.html and https://github.com/wolfgarbe/SymSpell
    /// Unlike those full correctors, this layer only validates candidates provided by macOS.
    private static func editDistance(_ source: [Character], _ target: [Character]) -> Int {
        var rows = Array(repeating: Array(repeating: 0, count: target.count + 1), count: source.count + 1)
        for i in 0...source.count { rows[i][0] = i }
        for j in 0...target.count { rows[0][j] = j }
        guard !source.isEmpty, !target.isEmpty else { return max(source.count, target.count) }
        for i in 1...source.count {
            for j in 1...target.count {
                let cost = source[i - 1] == target[j - 1] ? 0 : 1
                rows[i][j] = min(rows[i - 1][j] + 1, rows[i][j - 1] + 1, rows[i - 1][j - 1] + cost)
                if i > 1, j > 1, source[i - 1] == target[j - 2], source[i - 2] == target[j - 1] {
                    rows[i][j] = min(rows[i][j], rows[i - 2][j - 2] + 1)
                }
            }
        }
        return rows[source.count][target.count]
    }

    private static func validatedReplacement(for original: String, suggestion: String, allowShortInsertion: Bool) -> String? {
        guard isPlainWord(original), hasSafeCase(original), isPlainWord(suggestion),
              hasSafeCase(suggestion) else { return nil }
        let source = original.precomposedStringWithCanonicalMapping.lowercased()
        let target = suggestion.precomposedStringWithCanonicalMapping.lowercased()
        guard source != target else { return nil }
        let left = Array(source)
        let right = Array(target)
        guard left.count >= 3 else { return nil }
        let transposition = isAdjacentTransposition(left, right)
        let shortInsertion = allowShortInsertion && right.count == left.count + 1 && isSingleEdit(left, right)
        guard (left.count == 3 && (transposition || shortInsertion)) ||
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

    private static func isSingleVowelInsertion(_ source: [Character], _ target: [Character]) -> Bool {
        guard target.count == source.count + 1 else { return false }
        var index = 0
        while index < source.count, source[index] == target[index] { index += 1 }
        return "aeiou".contains(target[index]) && source[index...].elementsEqual(target[(index + 1)...])
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
