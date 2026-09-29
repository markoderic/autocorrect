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
