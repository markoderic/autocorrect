import Foundation

/// A contextual suggestion, never an instruction to silently replace text.
/// `range` uses UTF-16 offsets into the supplied completed text.
public struct ContextualWritingCandidate: Equatable, Sendable {
    public let range: NSRange
    public let original: String
    public let replacement: String
    public let explanation: String
}

/// Small English prose heuristics. Callers must require approval and independently
/// revalidate the focused editor, text, caret, and edit plan before applying one.
public enum ContextualWritingRules {
    private static let words = try! NSRegularExpression(pattern: "[A-Za-z]+(?:['’][A-Za-z]+)?")
    private static let invitationVerbs: Set<String> = [
        "build", "go", "make", "try", "start", "talk", "look", "write", "read",
        "begin", "continue", "discuss", "create", "work", "meet", "eat", "see"
    ]
    private static let possessionNouns: Set<String> = [
        "color", "colour", "size", "shape", "name", "owner", "price", "surface",
        "battery", "screen", "weight", "height", "width", "length"
    ]
    private static let possessionCues: Set<String> = [
        "about", "with", "without", "of", "check", "checked", "change", "changed",
        "compare", "compared", "inspect", "inspected"
    ]

    /// Looks back at most three completed words. Ordinary spaces must separate the
    /// relevant words; punctuation, structured text, and incomplete words stop a match.
    public static func candidate(in completedText: String) -> ContextualWritingCandidate? {
        let length = completedText.utf16.count
        guard length > 0, length <= 256,
              let last = completedText.last, CorrectionPolicy.isDelimiter(last),
              !completedText.hasSuffix("  ") else { return nil }
        let text = completedText as NSString
        let matches = words.matches(in: completedText, range: NSRange(location: 0, length: length))
        guard matches.count >= 2, let final = matches.last else { return nil }
        let tail = text.substring(from: NSMaxRange(final.range))
        guard !tail.isEmpty, tail.utf16.count <= 8,
              tail.allSatisfy(CorrectionPolicy.isDelimiter) else { return nil }

        for index in stride(from: matches.count - 2, through: max(0, matches.count - 4), by: -1) {
            let range = matches[index].range
            let original = text.substring(with: range)
            let normalized = original.lowercased().replacingOccurrences(of: "’", with: "'")
            guard ["its", "it's", "lets"].contains(normalized),
                  !original.dropFirst().contains(where: { $0.isUppercase }),
                  isWordBoundary(before: range.location, in: completedText) else { continue }
            let following = Array(matches[(index + 1)...])
            var previousEnd = NSMaxRange(range)
            guard following.allSatisfy({ match in
                let gap = text.substring(with: NSRange(location: previousEnd, length: match.range.location - previousEnd))
                previousEnd = NSMaxRange(match.range)
                return !gap.isEmpty && gap.allSatisfy { $0 == " " }
            }) else { continue }
            let after = following.map { text.substring(with: $0.range).lowercased() }
            var replacement: String?
            var explanation = ""
            if normalized == "its" {
                if ["a", "an", "been", "not"].contains(after[0]) || after.starts(with: ["going", "to"]) {
                    replacement = "it's"
                    explanation = "This context may mean ‘it is’ or ‘it has’; use ‘it's’ for that contraction."
                }
            } else if normalized == "it's", possessionNouns.contains(after[0]) {
                let hasPredicate = after.count >= 2 && ["is", "was"].contains(after[1])
                var hasCue = false
                if index > 0 {
                    let preceding = matches[index - 1].range
                    let gap = text.substring(with: NSRange(location: NSMaxRange(preceding), length: range.location - NSMaxRange(preceding)))
                    hasCue = !gap.isEmpty && gap.allSatisfy { $0 == " " }
                        && possessionCues.contains(text.substring(with: preceding).lowercased())
                }
                if hasPredicate || hasCue {
                    replacement = "its"
                    explanation = "This context may describe something belonging to it; possessive ‘its’ has no apostrophe."
                }
            } else if normalized == "lets", startsClause(at: range.location, in: text) {
                let verb = after[0] == "all" && after.count >= 2 ? after[1] : after[0]
                if invitationVerbs.contains(verb) {
                    replacement = "let's"
                    explanation = "This may be an invitation meaning ‘let us’; use ‘let's’ for that contraction."
                }
            }
            if let replacement {
                let styled = original.first?.isUppercase == true
                    ? replacement.prefix(1).uppercased() + replacement.dropFirst() : replacement
                return ContextualWritingCandidate(range: range, original: original,
                    replacement: styled, explanation: explanation)
            }
        }
        return nil
    }

    private static func isWordBoundary(before offset: Int, in text: String) -> Bool {
        guard offset > 0 else { return true }
        guard let range = Range(NSRange(location: offset, length: 0), in: text) else { return false }
        let previous = text[text.index(before: range.lowerBound)]
        return previous == " " || "([\"“«{\n".contains(previous)
    }

    private static func startsClause(at offset: Int, in text: NSString) -> Bool {
        let prefix = text.substring(to: offset).trimmingCharacters(in: CharacterSet(charactersIn: " ([\"“«{"))
        return prefix.isEmpty || prefix.last.map { ".!?\n".contains($0) } == true
    }
}
