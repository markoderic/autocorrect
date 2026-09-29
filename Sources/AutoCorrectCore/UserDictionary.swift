import Foundation

/// Validated, local spelling preferences. Ignored words take precedence when the engine
/// consults this dictionary; a word may deliberately appear in both collections.
public struct UserDictionary: Equatable, Sendable {
    public let ignoredWords: Set<String>
    public let corrections: [String: String]

    /// A stable lookup key that treats case and canonically equivalent Unicode equally.
    public static func normalizedKey(_ word: String) -> String {
        word.precomposedStringWithCanonicalMapping.lowercased().precomposedStringWithCanonicalMapping
    }

    /// Reads one ignored word or `typo -> replacement` pair per line. A Unicode arrow
    /// (`→`) is also accepted. Blank lines are ignored, and errors use one-based lines.
    /// Replacement phrases and casing are retained exactly after trimming ordinary spaces.
    public static func parse(ignoredText: String, correctionsText: String) throws -> UserDictionary {
        var ignoredWords = Set<String>()
        for (offset, line) in lines(ignoredText).enumerated() {
            let word = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !word.isEmpty else { continue }
            guard word.lowercased() == "i" || isWord(word, length: 2...32) else {
                throw ValidationError(section: .ignoredWords, line: offset + 1,
                                      reason: "Enter one word of 2–32 letters (or i), with at most one interior apostrophe.")
            }
            ignoredWords.insert(normalizedKey(word))
        }

        var corrections: [String: String] = [:]
        var firstLines: [String: Int] = [:]
        for (offset, line) in lines(correctionsText).enumerated() {
            guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let arrows = [line.range(of: "->"), line.range(of: "→")].compactMap { $0 }
            guard let arrow = arrows.min(by: { $0.lowerBound < $1.lowerBound }) else {
                throw ValidationError(section: .corrections, line: offset + 1,
                                      reason: "Use one pair in the form typo -> replacement.")
            }
            let source = String(line[..<arrow.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let replacement = String(line[arrow.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: " "))
            guard source.lowercased() == "i" || isWord(source, length: 2...32) else {
                throw ValidationError(section: .corrections, line: offset + 1,
                                      reason: "The typo must be one word of 2–32 letters (or i), with at most one interior apostrophe.")
            }
            guard isValidReplacement(replacement) else {
                throw ValidationError(section: .corrections, line: offset + 1,
                                      reason: "The replacement must contain 1–120 printable characters, with no tabs, line breaks, or control characters.")
            }
            let key = normalizedKey(source)
            if let firstLine = firstLines[key] {
                throw ValidationError(section: .corrections, line: offset + 1,
                                      reason: "This typo already has a correction on line \(firstLine). Keep only one entry per typo.")
            }
            corrections[key] = replacement
            firstLines[key] = offset + 1
        }
        return UserDictionary(ignoredWords: ignoredWords, corrections: corrections)
    }

    /// Shared validation for saved phrases and insertion plans. Ordinary spaces and printable
    /// punctuation are allowed; invisible controls, line separators, and empty phrases are not.
    public static func isValidReplacement(_ replacement: String) -> Bool {
        guard (1...120).contains(replacement.count),
              !replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return replacement.unicodeScalars.allSatisfy {
            !CharacterSet.controlCharacters.contains($0) && !CharacterSet.newlines.contains($0) &&
                !CharacterSet.illegalCharacters.contains($0)
        }
    }

    public struct ValidationError: LocalizedError, Equatable, Sendable {
        public enum Section: String, Sendable {
            case ignoredWords = "Ignored words"
            case corrections = "Custom corrections"
        }

        public let section: Section
        public let line: Int
        public let reason: String

        public var errorDescription: String? {
            "\(section.rawValue), line \(line): \(reason)"
        }
    }

    private static func lines(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
    }

    private static func isWord(_ word: String, length: ClosedRange<Int>) -> Bool {
        guard length.contains(word.count), word.first?.isLetter == true,
              word.last?.isLetter == true else { return false }
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
