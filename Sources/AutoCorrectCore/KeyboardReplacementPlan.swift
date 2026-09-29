import Foundation

/// A validated edit from a collapsed caret, with no temporary text selection.
/// The caller must revalidate the focused field and snapshot before posting events.
public struct KeyboardReplacementPlan: Equatable, Sendable {
    public let deleteCount: Int
    public let insertion: String
    public let expectedText: String
    /// UTF-16 offset within the bounded snapshot, not the entire field.
    public let expectedCaret: Int

    /// `text` ends exactly at the caret. Only the word and its delimiter suffix
    /// may be deleted; existing text before the word is preserved verbatim.
    public static func make(text: String, wordRange: NSRange, replacement: String) -> KeyboardReplacementPlan? {
        let length = text.utf16.count
        guard (1...256).contains(length), wordRange.location >= 0,
              wordRange.location <= length, wordRange.length > 0,
              wordRange.length <= length - wordRange.location,
              let range = Range(wordRange, in: text),
              (1...64).contains(replacement.utf16.count), isWord(replacement) else { return nil }

        let original = String(text[range])
        let suffix = String(text[range.upperBound...])
        let prefix = String(text[..<range.lowerBound])
        guard isWord(original), original != replacement,
              (1...8).contains(suffix.utf16.count),
              suffix.allSatisfy(CorrectionPolicy.isDelimiter) else { return nil }
        // Reject a range that names only the tail of a larger word/identifier.
        if let preceding = prefix.last {
            guard preceding.unicodeScalars.allSatisfy({ CharacterSet.whitespacesAndNewlines.contains($0) }) ||
                    "([\"'‘“«{".contains(preceding) else { return nil }
        }

        let removed = original + suffix
        // Backspace semantics vary for composed characters. ASCII makes the count
        // unambiguous while still allowing any Unicode text in the untouched prefix.
        guard (1...96).contains(removed.utf16.count),
              removed.unicodeScalars.allSatisfy({ (0x20...0x7E).contains($0.value) }) else { return nil }

        let insertion = replacement + suffix
        let expected = prefix + insertion
        return KeyboardReplacementPlan(deleteCount: removed.utf16.count, insertion: insertion,
                                       expectedText: expected, expectedCaret: expected.utf16.count)
    }

    private static func isWord(_ word: String) -> Bool {
        guard word.first?.isLetter == true, word.last?.isLetter == true else { return false }
        var apostrophes = 0
        for character in word {
            if character == "'" || character == "’" {
                apostrophes += 1
                guard apostrophes <= 1 else { return false }
            } else {
                guard character.unicodeScalars.allSatisfy({
                    CharacterSet.letters.contains($0) || CharacterSet.nonBaseCharacters.contains($0)
                }) else { return false }
            }
        }
        return true
    }
}
