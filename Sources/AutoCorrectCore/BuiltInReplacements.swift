import Foundation

/// Small, inspectable opt-in writing conveniences. Ignored words and user corrections
/// should be resolved first. Only an exact lowercase trigger is expanded or recased.
public enum BuiltInReplacements {
    public static let expansions: [String: String] = [
        "idk": "I don't know", "omw": "On my way", "brb": "Be right back",
        "imo": "in my opinion", "fyi": "for your information"
    ]

    public static let casing: [String: String] = [
        "iphone": "iPhone", "ui": "UI", "ux": "UX", "api": "API", "macos": "macOS"
    ]

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
