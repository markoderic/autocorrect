import Foundation

/// Conventional English writing corrections that spelling dictionaries may accept as
/// abbreviations or other words. User corrections and ignored words take priority.
public enum EnglishWritingRules {
    private static let contractions: [String: String] = [
        "im": "I'm", "ive": "I've",
        "dont": "don't", "doesnt": "doesn't", "didnt": "didn't",
        "isnt": "isn't", "arent": "aren't", "wasnt": "wasn't", "werent": "weren't",
        "hasnt": "hasn't", "havent": "haven't", "hadnt": "hadn't",
        "cant": "can't", "couldnt": "couldn't", "wont": "won't", "wouldnt": "wouldn't",
        "shouldnt": "shouldn't", "mustnt": "mustn't", "neednt": "needn't",
        "youre": "you're", "youve": "you've", "youll": "you'll",
        "theyre": "they're", "theyve": "they've", "theyll": "they'll",
        "weve": "we've", "thats": "that's", "theres": "there's",
        "whats": "what's", "whos": "who's", "heres": "here's"
    ]

    /// Correct a damaged contraction as one operation: a missing apostrophe plus
    /// a transposition/omission is often rejected by a generic one-edit word gate.
    /// Native misspelling detection must precede this; valid words never enter here.
    public static func typoReplacement(for original: String, language: String,
                                       systemCorrection: String?, guesses: [String]) -> String? {
        guard language.replacingOccurrences(of: "-", with: "_").split(separator: "_").first?.lowercased() == "en",
              (5...16).contains(original.count), !original.dropFirst().contains(where: \.isUppercase),
              original.allSatisfy({ ($0.asciiValue != nil && $0.isLetter) || $0 == "'" || $0 == "’" }) else { return nil }
        let source = original.lowercased().replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "’", with: "")
        let candidates = contractions.filter { key, _ in
            key.count >= 5 && CorrectionPolicy.editDistance(Array(source), Array(key)) == 1
        }
        guard candidates.count == 1, let (key, replacement) = candidates.first,
              source.prefix(2) == key.prefix(2) else { return nil }
        let native = ([systemCorrection].compactMap { $0 } + Array(guesses.prefix(3))).map {
            $0.lowercased().replacingOccurrences(of: "’", with: "'")
        }
        // Native agreement also permits a missing/extra letter. Without it, only a
        // unique adjacent transposition preserving every letter is eligible.
        let preservesLetters = source.count == key.count && source.sorted() == key.sorted()
        guard native.contains(replacement.lowercased()) || preservesLetters else { return nil }
        return original.first?.isUppercase == true
            ? replacement.prefix(1).uppercased() + replacement.dropFirst() : replacement
    }

    public static func replacement(for original: String, language: String) -> String? {
        guard language.replacingOccurrences(of: "-", with: "_").split(separator: "_").first?.lowercased() == "en",
              !original.dropFirst().contains(where: { $0.isUppercase }) else { return nil }
        if original == "i" { return "I" }
        let lower = original.lowercased()
        // Keep the user's apostrophe style when only the pronoun needs capitalization.
        if ["i'm", "i've", "i'll", "i'd", "i’m", "i’ve", "i’ll", "i’d"].contains(lower) {
            let corrected = "I" + original.dropFirst()
            return corrected == original ? nil : corrected
        }
        // This deliberate prose default also overrides the musical-note dictionary entry.
        // Add "ti" to Ignored Words to keep that spelling in specialist writing.
        if lower == "ti" { return original.first?.isUppercase == true ? "It" : "it" }
        // Ambiguous ordinary words (ill, well, were, its, id, lets, etc.) are not rules.
        guard let contraction = contractions[lower] else { return nil }
        if contraction.first == "I" { return contraction }
        return original.first?.isUppercase == true
            ? contraction.prefix(1).uppercased() + contraction.dropFirst() : contraction
    }
}
