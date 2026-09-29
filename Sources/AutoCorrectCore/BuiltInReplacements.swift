import Foundation

/// Small, inspectable opt-in writing conveniences. Ignored words and user corrections
/// should be resolved first. Only an exact lowercase trigger is expanded or recased.
public enum BuiltInReplacements {
    public static let expansions: [String: String] = [
        "idk": "I don't know", "omw": "On my way", "brb": "Be right back",
        "imo": "in my opinion", "fyi": "for your information"
    ]

    public static let casing: [String: String] = [
        "iphone": "iPhone", "ipad": "iPad", "macbook": "MacBook", "airpods": "AirPods",
        "github": "GitHub", "chatgpt": "ChatGPT", "linkedin": "LinkedIn", "youtube": "YouTube",
        "ui": "UI", "ux": "UX", "api": "API", "macos": "macOS"
    ]

    /// Call only after the dictionary marks the source as misspelled. A unique one-edit
    /// match to a longer product name is safe to recase; never fuzzy-match short acronyms.
    public static func productTypoReplacement(for original: String) -> String? {
        guard (4...32).contains(original.count), original.allSatisfy({ $0.asciiValue != nil && $0.isLetter }),
              !original.dropFirst().contains(where: { $0.isUppercase }) else { return nil }
        let matches = casing.filter { key, _ in
            key.count >= 5 && CorrectionPolicy.editDistance(Array(original.lowercased()), Array(key)) == 1
        }
        return matches.count == 1 ? matches.first?.value : nil
    }

    /// English abbreviations are language-gated. Product/acronym casing is language-neutral.
    /// ALLCAPS, Initialcase, and mixed-case input are preserved as deliberate user choices.
    public static func replacement(for original: String, language: String,
                                   includeExpansions: Bool, includeCasing: Bool) -> String? {
        guard original == original.lowercased() else { return nil }
        if includeCasing, let replacement = casing[original] { return replacement }
        let isEnglish = language.replacingOccurrences(of: "-", with: "_").split(separator: "_").first?.lowercased() == "en"
        if includeExpansions, isEnglish { return expansions[original] }
        return nil
    }
}
