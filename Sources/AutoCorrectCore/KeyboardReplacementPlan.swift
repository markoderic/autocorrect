import Foundation

/// A validated edit from a collapsed caret, with no temporary text selection.
/// The caller must revalidate the focused field and snapshot before posting events.
public struct KeyboardReplacementPlan: Equatable, Sendable {
    public let deleteCount: Int
    public let insertion: String
    public let expectedText: String
    /// UTF-16 offset within the bounded snapshot, not the entire field.
    public let expectedCaret: Int

    /// `text` ends exactly at the caret. A validated word or previously expanded phrase
    /// and up to 96 ASCII characters following its delimiter may be replaced. The exact
    /// following text is reinserted, allowing delayed correction and phrase reversal.
    /// Set `reversingExpansion` only for a recorded expansion being undone; this allows
    /// its original phrase to begin or end with punctuation or numbers.
    public static func make(text: String, wordRange: NSRange, replacement: String,
                            reversingExpansion: Bool = false) -> KeyboardReplacementPlan? {
        let length = text.utf16.count
        guard (1...256).contains(length), wordRange.location >= 0,
              wordRange.location <= length, wordRange.length > 0,
              wordRange.length <= length - wordRange.location,
              let range = Range(wordRange, in: text),
              UserDictionary.isValidReplacement(replacement) else { return nil }

        let original = String(text[range])
        let suffix = String(text[range.upperBound...])
        let prefix = String(text[..<range.lowerBound])
        guard UserDictionary.isValidReplacement(original),
              reversingExpansion || (original.first?.isLetter == true && original.last?.isLetter == true),
              original != replacement,
              (1...96).contains(suffix.utf16.count),
              let delimiter = suffix.first,
              CorrectionPolicy.isDelimiter(delimiter) ||
                (delimiter == "'" && prefix.last == "'") ||
                (delimiter == "’" && prefix.last == "‘") else { return nil }
        // Reject a range that names only the tail of a larger word/identifier.
        if let preceding = prefix.last {
            guard preceding.unicodeScalars.allSatisfy({ CharacterSet.whitespacesAndNewlines.contains($0) }) ||
                    "([\"'‘“«{".contains(preceding) else { return nil }
        }

        let removed = original + suffix
        // Backspace semantics vary for composed characters. ASCII makes the count
        // unambiguous while still allowing any Unicode text in the untouched prefix.
        // The supported smart quotes and nonbreaking spaces also use one unit/deletion.
        guard (1...216).contains(removed.utf16.count),
              removed.allSatisfy({ TypingTypography.isSupportedKeystroke(String($0)) }) else { return nil }

        let insertion = replacement + suffix
        let expected = prefix + insertion
        return KeyboardReplacementPlan(deleteCount: removed.utf16.count, insertion: insertion,
                                       expectedText: expected, expectedCaret: expected.utf16.count)
    }

}
