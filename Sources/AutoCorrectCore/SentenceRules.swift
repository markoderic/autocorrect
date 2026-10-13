import Foundation

/// Small, auditable grammar rules run before the optional model. These remain suggestions,
/// use the same validator as model output, and never broaden the keyboard edit transport.
public enum SentenceRules {
    private struct Rule {
        let regex: NSRegularExpression
        let replacement: String
        let category: String
        init(_ pattern: String, _ replacement: String, _ category: String = "grammar") {
            regex = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            self.replacement = replacement; self.category = category
        }
    }

    private static let rules: [Rule] = [
        Rule(#"\b(the|a|an|to|of|in|on|for|with)\s+\1\b"#, "$1"),
        Rule(#"\b(could|should|would|might|must) of\b"#, "$1 have"),
        Rule(#"\b(he|she|it) don['’]t\b"#, "$1 doesn't"),
        Rule(#"\b(we|you|they) was\b"#, "$1 were"),
        Rule(#"\bmore (better|worse)\b"#, "$1"),
        Rule(#"\bmost (best|worst)\b"#, "$1"),
        Rule(#"\b(has|have|had) went\b"#, "$1 gone"),
        Rule(#"\bbetween you and I\b"#, "between you and me"),
        Rule(#"\b(Each|Every one) of (the|these|those|my|your|our|their) ([\p{L}]+) have\b"#, "$1 of $2 $3 has"),
        Rule(#"\b(Each|Every one) of (the|these|those|my|your|our|their) ([\p{L}]+) (need|require|want|include|contain)\b"#, "$1 of $2 $3 $4s"),
        Rule(#"\bYour going to\b"#, "you're going to"),
        Rule(#"\bThere going to\b"#, "they're going to"),
        Rule(#"\b(thanks|thank you) for you['’]re\b"#, "$1 for your"),
        // Fix spacing only at an interior punctuation boundary; the following word is
        // an unchanged anchor so the resulting span still begins and ends with letters.
        Rule(#"\b([\p{L}]+) +([,;:]) *(?=[\p{L}])([\p{L}]+)\b"#, "$1$2 $3", "punctuation"),
        Rule(#"\b([\p{L}]+)([,;:])(?=[\p{L}])([\p{L}]+)\b"#, "$1$2 $3", "punctuation"),
        Rule(#"\b(can|don|isn|wasn|aren|weren|couldn|shouldn|wouldn|hasn|haven|hadn)['’] +t\b"#, "$1't", "punctuation")
    ]

    public static func proposals(in sentence: String) -> [ProposedEdit] {
        guard sentence.utf16.count <= 512 else { return [] }
        let ns = sentence as NSString
        var result: [ProposedEdit] = []
        for rule in rules {
            for match in rule.regex.matches(in: sentence, range: NSRange(location: 0, length: ns.length)) {
                let original = ns.substring(with: match.range)
                var replacement = rule.regex.replacementString(for: match, in: sentence, offset: 0, template: rule.replacement)
                if original.first?.isUppercase == true {
                    replacement = replacement.prefix(1).uppercased() + replacement.dropFirst()
                }
                result.append(ProposedEdit(original: original, replacement: replacement, category: rule.category,
                                           explanation: rule.category == "grammar" ? "Grammar agreement or word form" : "Punctuation spacing"))
            }
        }
        let words = try! NSRegularExpression(pattern: #"\b[\p{L}]+\b"#)
        for match in words.matches(in: sentence, range: NSRange(location: 0, length: ns.length)) {
            let original = ns.substring(with: match.range)
            if let replacement = EnglishWritingRules.replacement(for: original, language: "en_US"),
               replacement.contains("'"), original.lowercased() == replacement.lowercased().replacingOccurrences(of: "'", with: "") {
                result.append(ProposedEdit(original: original, replacement: replacement, category: "punctuation",
                                          explanation: "Missing contraction apostrophe"))
            }
        }
        return result
    }
}
