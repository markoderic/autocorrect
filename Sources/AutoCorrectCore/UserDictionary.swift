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
    /// Replacement spelling and casing are retained exactly after trimming whitespace.
    public static func parse(ignoredText: String, correctionsText: String) throws -> UserDictionary {
        var ignoredWords = Set<String>()
        for (offset, line) in lines(ignoredText).enumerated() {
            let word = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !word.isEmpty else { continue }
            guard isWord(word, length: 2...32) else {
                throw ValidationError(section: .ignoredWords, line: offset + 1,
                                      reason: "Enter one word of 2–32 letters, with at most one interior apostrophe.")
            }
            ignoredWords.insert(normalizedKey(word))
        }

        var corrections: [String: String] = [:]
        var firstLines: [String: Int] = [:]
        for (offset, line) in lines(correctionsText).enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.replacingOccurrences(of: "→", with: "->").components(separatedBy: "->")
            guard parts.count == 2 else {
                throw ValidationError(section: .corrections, line: offset + 1,
                                      reason: "Use one pair in the form typo -> replacement.")
            }
            let source = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let replacement = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard isWord(source, length: 2...32) else {
                throw ValidationError(section: .corrections, line: offset + 1,
                                      reason: "The typo must be one word of 2–32 letters, with at most one interior apostrophe.")
            }
            guard isWord(replacement, length: 1...64) else {
                throw ValidationError(section: .corrections, line: offset + 1,
                                      reason: "The replacement must be one word of 1–64 letters, with at most one interior apostrophe.")
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
