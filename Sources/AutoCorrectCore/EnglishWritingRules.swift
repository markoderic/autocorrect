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
        "whats": "what's", "whos": "who's", "heres": "here's",
        // Added after native probes: automatic recommendations for several of these are
        // nil on some macOS versions, and a closer competitor (shed, aunt, till) blocks the
        // ranked fallback. Each has one conventional reading; hes/shes follow iOS practice.
        "hes": "he's", "shes": "she's", "itll": "it'll", "itd": "it'd", "youd": "you'd", "theyd": "they'd",
        "thatll": "that'll", "therell": "there'll", "whatll": "what'll", "whod": "who'd",
        "wheres": "where's", "whens": "when's",
        "wouldve": "would've", "couldve": "could've", "shouldve": "should've",
        "mightve": "might've", "mustve": "must've", "aint": "ain't", "yall": "y'all", "oclock": "o'clock"
    ]

    /// Weekdays and the months that are not also ordinary words. "may", "march" and "august"
    /// are left alone: the verb, the verb and the adjective are far more common in prose.
    private static let capitalizedNames: Set<String> = [
        "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
        "january", "february", "april", "june", "july", "september", "october", "november", "december"
    ]

    private static func isEnglish(_ language: String) -> Bool {
        language.replacingOccurrences(of: "-", with: "_").split(separator: "_").first?.lowercased() == "en"
    }

    /// Lowercase letters only: apostrophes of either style are removed, never other characters.
    private static func apostropheFreeKey(_ word: String) -> String {
        word.lowercased().replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "’", with: "")
    }

    /// Keeps a typed curly apostrophe in the repaired contraction; hosts restyle straight ones.
    private static func styled(_ replacement: String, like original: String) -> String {
        original.contains("’") ? replacement.replacingOccurrences(of: "'", with: "’") : replacement
    }

    /// The one contraction key within a single edit of `source`, when that key has at least
    /// `minimumKeyLength` letters and no other key is equally close. Exact keys are excluded:
    /// they belong to `replacement(for:)`.
    private static func nearestKey(to source: String, minimumKeyLength: Int) -> (key: String, replacement: String, preservesLetters: Bool)? {
        let chars = Array(source)
        let candidates = contractions.filter { key, _ in
            key.count >= minimumKeyLength && key != source && CorrectionPolicy.editDistance(chars, Array(key)) <= 1
        }
        guard candidates.count == 1, let (key, replacement) = candidates.first else { return nil }
        // Same length, same letters and one Damerau edit means one adjacent transposition.
        return (key, replacement, source.count == key.count && source.sorted() == key.sorted())
    }

    /// Correct a damaged contraction as one operation: a missing apostrophe plus
    /// a transposition/omission is often rejected by a generic one-edit word gate.
    /// Native misspelling detection must precede this; valid words never enter here.
    /// Evidence scales with risk: an interior transposition of a five-letter-or-longer key
    /// stands alone (doenst → doesn't); any other single edit of such a key needs the native
    /// automatic recommendation (or the top guess when it is absent); a four-letter key
    /// (dont, cant, wont, isnt, aint, …) or a swapped first pair (odnt, odesnt) needs both:
    /// every typed letter preserved and native agreement. Short words are too ambiguous
    /// for less (dent/font/donut are valid words; dotn is natively read as down).
    public static func typoReplacement(for original: String, language: String,
                                       systemCorrection: String?, guesses: [String]) -> String? {
        guard isEnglish(language), (4...16).contains(original.count), !original.dropFirst().contains(where: \.isUppercase),
              original.allSatisfy({ ($0.asciiValue != nil && $0.isLetter) || $0 == "'" || $0 == "’" }) else { return nil }
        let source = apostropheFreeKey(original)
        guard source.count >= 4, let (key, replacement, preservesLetters) = nearestKey(to: source, minimumKeyLength: 4) else { return nil }
        func normalized(_ word: String) -> String { word.lowercased().replacingOccurrences(of: "’", with: "'") }
        let nativeAgrees = systemCorrection.map(normalized) == replacement.lowercased() ||
            (systemCorrection == nil && guesses.first.map(normalized) == replacement.lowercased())
        let leadingSwap = preservesLetters && source.prefix(2) != key.prefix(2)
        if key.count == 4 || leadingSwap {
            guard preservesLetters, nativeAgrees else { return nil }
        } else {
            guard source.prefix(2) == key.prefix(2), nativeAgrees || preservesLetters else { return nil }
        }
        let repaired = styled(replacement, like: original)
        return original.first?.isUppercase == true
            ? repaired.prefix(1).uppercased() + repaired.dropFirst() : repaired
    }

    /// An all-caps damaged or apostrophe-less contraction followed by one space and an
    /// all-caps dictionary word, e.g. `ODNT DO ` → `DON'T DO `. The native checker accepts
    /// almost any all-caps token as an acronym, so this needs context: the following word
    /// shows the writer is typing prose in capitals. An isolated `ODNT ` abstains. Exact
    /// keys (DONT) are deterministic; a four-letter transposition (ODNT) additionally needs
    /// the native correction of its lowercase form to name the contraction, exactly like
    /// the lowercase path. `isWord` and `nativeCorrection` receive lowercase words.
    public static func uppercaseContractionCandidate(in completedText: String, language: String,
                                                     isWord: (String) -> Bool,
                                                     nativeCorrection: (String) -> String?) -> ContextualWritingCandidate? {
        let length = completedText.utf16.count
        guard isEnglish(language), (3...256).contains(length), let last = completedText.last,
              CorrectionPolicy.isDelimiter(last) else { return nil }
        let text = completedText as NSString
        let matches = words.matches(in: completedText, range: NSRange(location: 0, length: length))
        guard matches.count >= 2 else { return nil }
        let following = matches[matches.count - 1]
        let target = matches[matches.count - 2]
        let tail = text.substring(from: NSMaxRange(following.range))
        guard (1...8).contains(tail.utf16.count), tail.allSatisfy(CorrectionPolicy.isDelimiter),
              text.substring(with: NSRange(location: NSMaxRange(target.range),
                                           length: following.range.location - NSMaxRange(target.range))) == " " else { return nil }
        if target.range.location > 0 {
            let before = text.substring(with: NSRange(location: target.range.location - 1, length: 1))
            guard before == " " || "([\"“«{\n".contains(before) else { return nil }
        }
        let original = text.substring(with: target.range)
        let next = text.substring(with: following.range)
        guard original.allSatisfy({ ($0.isASCII && $0.isUppercase) || $0 == "'" || $0 == "’" }),
              next.allSatisfy({ $0.isASCII && $0.isUppercase }), isWord(next.lowercased()) else { return nil }
        let source = apostropheFreeKey(original)
        guard (4...16).contains(source.count) else { return nil }
        var contraction: String?
        if let exact = contractions[source] {
            contraction = exact
        } else if let (_, replacement, preservesLetters) = nearestKey(to: source, minimumKeyLength: 4), preservesLetters,
                  nativeCorrection(source).map({ $0.lowercased().replacingOccurrences(of: "’", with: "'") }) == replacement.lowercased() {
            contraction = replacement
        }
        guard let contraction else { return nil }
        let replacement = styled(contraction.uppercased(), like: original)
        guard replacement != original else { return nil }
        return ContextualWritingCandidate(range: target.range, original: original, replacement: replacement,
            explanation: "This capitalized contraction is missing or misplacing its apostrophe.", automatic: true)
    }

    private static let words = try! NSRegularExpression(pattern: "[A-Za-z]+(?:['’][A-Za-z]+)?")

    public static func replacement(for original: String, language: String) -> String? {
        guard isEnglish(language), !original.dropFirst().contains(where: { $0.isUppercase }) else { return nil }
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
        if capitalizedNames.contains(lower) {
            let capitalized = lower.prefix(1).uppercased() + lower.dropFirst()
            return capitalized == original ? nil : capitalized
        }
        // Ambiguous ordinary words (ill, well, were, its, id, lets, etc.) are not rules.
        guard let contraction = contractions[lower] else { return nil }
        if contraction.first == "I" { return contraction }
        return original.first?.isUppercase == true
            ? contraction.prefix(1).uppercased() + contraction.dropFirst() : contraction
    }
}
