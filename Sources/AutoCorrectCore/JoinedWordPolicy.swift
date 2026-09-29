import Foundation

/// Two-word segmentation, bounded to 32 ASCII letters. The caller must first rule
/// out valid dictionary words, recognized names, and user overrides.
public enum JoinedWordPolicy {
    private static let proseStarts: Set<String> = [
        "a", "the", "my", "your", "our", "their", "this", "that", "these", "those",
        "you", "we", "they", "he", "she", "it", "in", "on", "at", "to", "of",
        "for", "with", "from", "and", "but", "not", "is", "are", "was", "were",
        "be", "can", "will", "would", "could", "should", "please", "thank", "hello"
    ]
    private static let firstPersonVerbs: Set<String> = [
        "know", "think", "want", "need", "like", "love", "hope", "wish", "have",
        "am", "was", "will", "would", "can", "could", "should", "feel", "see",
        "saw", "say", "said", "mean", "meant", "agree", "believe", "understand",
        "remember", "forgot", "forget", "work", "worked", "use", "used", "tried",
        "try", "went", "go", "got", "get", "made", "make", "found", "find",
        "sent", "send", "wrote", "write", "read", "heard", "hear", "did", "do"
    ]

    public static func replacement(for word: String, language: String,
                                   systemCorrection: String?, guesses: [String],
                                   isWord: (String) -> Bool) -> String? {
        guard language.lowercased().hasPrefix("en"), (4...32).contains(word.count),
              word.allSatisfy({ $0.asciiValue != nil && $0.isLetter }),
              !word.dropFirst().contains(where: \.isUppercase) else { return nil }
        let source = word.lowercased()
        // Native rankings frequently delete the pronoun in "iknow" and "ithink".
        // A productive pronoun + verb rule preserves it instead.
        if source.first == "i", firstPersonVerbs.contains(String(source.dropFirst())) {
            return "I " + source.dropFirst()
        }
        // Agreement with the native automatic correction is required. Merely finding
        // two dictionary substrings would split compounds and names far too often.
        guard let proposed = systemCorrection?.lowercased(), proposed.contains(" ") else { return nil }
        let parts = proposed.split(separator: " ").map(String.init)
        guard parts.count == 2, parts.joined() == source,
              proseStarts.contains(parts[0]), parts[1].count >= 2,
              parts.allSatisfy(isWord),
              guesses.prefix(5).contains(where: { $0.lowercased().replacingOccurrences(of: "-", with: " ") == proposed }) else { return nil }
        let result = parts.joined(separator: " ")
        return word.first?.isUppercase == true ? result.prefix(1).uppercased() + result.dropFirst() : result
    }
}
