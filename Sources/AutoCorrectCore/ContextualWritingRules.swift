import Foundation

/// A bounded contextual correction with explicit automatic-versus-review eligibility.
/// `range` uses UTF-16 offsets into the supplied completed text.
public struct ContextualWritingCandidate: Equatable, Sendable {
    public let range: NSRange
    public let original: String
    public let replacement: String
    public let explanation: String
    public let automatic: Bool
}

/// Small English prose heuristics, not a general grammar model. Callers must honor
/// `automatic` and independently revalidate focus, text, caret, and the edit plan.
public enum ContextualWritingRules {
    private static let words = try! NSRegularExpression(pattern: "[A-Za-z]+(?:['’][A-Za-z]+)?")
    private static let invitationVerbs: Set<String> = [
        "build", "go", "make", "try", "start", "talk", "look", "write", "read",
        "begin", "continue", "discuss", "create", "work", "meet", "eat", "see",
        "fix", "improve", "update", "add", "check", "test", "use", "do", "get",
        "keep", "take", "send", "run", "open", "close", "move", "count", "stop",
        "change", "finish", "review", "download", "install", "publish", "say"
    ]
    private static let possessionNouns: Set<String> = [
        "color", "colour", "size", "shape", "name", "owner", "price", "surface",
        "battery", "screen", "weight", "height", "width", "length"
    ]
    private static let possessionCues: Set<String> = [
        "about", "with", "without", "of", "check", "checked", "change", "changed",
        "compare", "compared", "inspect", "inspected"
    ]

    private static let predicateWords: Set<String> = [
        "ready", "good", "great", "fine", "okay", "ok", "true", "false", "wrong", "correct",
        "working", "raining", "snowing", "broken", "missing", "late", "early", "done",
        "easy", "hard", "possible", "impossible", "important", "useful", "available",
        "clear", "obvious", "safe", "better", "worse", "hot", "cold", "nice"
    ]
    private static let predicateComplements: Set<String> = ["to", "for", "that", "because", "if", "when", "now", "today", "already", "again", "enough"]
    private static let degreeAdverbs: Set<String> = ["really", "very", "quite", "pretty", "so", "too", "already", "still", "almost"]

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
            guard ["its", "it's", "lets", "pleas"].contains(normalized),
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
            var automatic = false
            if normalized == "pleas", startsClause(at: range.location, in: text),
               invitationVerbs.union(["help", "let", "tell", "explain", "confirm", "reply", "respond", "remember", "leave", "wait"]).contains(after[0]) {
                replacement = "please"
                explanation = "This request uses ‘please’. The plural noun ‘pleas’ is preserved in other contexts."
                automatic = true
            } else if normalized == "its", isSubjectPosition(at: range.location, in: text) {
                let predicateIndex = degreeAdverbs.contains(after[0]) ? 1 : 0
                let hasPredicate = after.count > predicateIndex && predicateWords.contains(after[predicateIndex])
                // Wait beyond an adjective: "its good looks" and "its working parts"
                // must not be changed at the intermediate "its good " boundary.
                let completedPredicate = hasPredicate && (
                    (after.count == predicateIndex + 1 && tail.contains(where: { ".!?;:".contains($0) })) ||
                    (after.count > predicateIndex + 1 && predicateComplements.contains(after[predicateIndex + 1])))
                if ["a", "an", "been", "not"].contains(after[0]) || after.starts(with: ["going", "to"]) || completedPredicate {
                    replacement = "it's"
                    explanation = "This context means ‘it is’ or ‘it has’; use ‘it's’ for that contraction."
                    automatic = true
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
                    automatic = hasPredicate
                    explanation = "This context may describe something belonging to it; possessive ‘its’ has no apostrophe."
                }
            } else if normalized == "lets", startsClause(at: range.location, in: text) {
                let verb = ["all", "just", "not", "also"].contains(after[0]) && after.count >= 2 ? after[1] : after[0]
                if invitationVerbs.contains(verb) {
                    replacement = "let's"
                    automatic = true
                    explanation = "This may be an invitation meaning ‘let us’; use ‘let's’ for that contraction."
                }
            }
            if let replacement {
                let styled = original.first?.isUppercase == true
                    ? replacement.prefix(1).uppercased() + replacement.dropFirst() : replacement
                return ContextualWritingCandidate(range: range, original: original,
                    replacement: styled, explanation: explanation, automatic: automatic)
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

    private static func isSubjectPosition(at offset: Int, in text: NSString) -> Bool {
        if startsClause(at: offset, in: text) { return true }
        let prefix = text.substring(to: offset)
        guard let last = words.matches(in: prefix, range: NSRange(location: 0, length: prefix.utf16.count)).last,
              (prefix as NSString).substring(from: NSMaxRange(last.range)).allSatisfy({ $0 == " " }) else { return false }
        let previous = (prefix as NSString).substring(with: last.range).lowercased()
        // Avoid possessive gerunds such as "despite its not working".
        return ["think", "thought", "know", "knew", "hope", "believe", "sure", "said", "says",
                "because", "if", "when", "while", "although", "since", "and", "but", "that",
                "whether", "unless", "until", "so", "is"].contains(previous)
    }

    private static func startsClause(at offset: Int, in text: NSString) -> Bool {
        let prefix = text.substring(to: offset).trimmingCharacters(in: CharacterSet(charactersIn: " ([\"“«{"))
        if prefix.isEmpty || prefix.last.map({ ".!?\n".contains($0) }) == true { return true }
        // Short discourse openers only: do not treat "she then lets go" as an invitation.
        let clause = prefix.components(separatedBy: CharacterSet(charactersIn: ".!?\n")).last ?? prefix
        let opener = clause.trimmingCharacters(in: .whitespaces).lowercased()
        return ["ok", "ok,", "okay", "okay,", "well", "well,", "so", "so,", "now", "now,",
                "then", "and", "and then", "but", "please", "alright", "alright,"].contains(opener)
    }
}
