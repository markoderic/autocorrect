import Foundation

/// Native dictionaries sometimes prefer spacing a compound while their automatic answer
/// substitutes a different word. Preserve the typed compound instead of that substitution.
public enum CompoundSpellingPolicy {
    public static func prefersUnchangedLetters(for word: String, guesses: [String]) -> Bool {
        guard (6...32).contains(word.count), word.allSatisfy(\.isLetter),
              let first = guesses.first else { return false }
        let parts = first.split(whereSeparator: { $0 == " " || $0 == "-" })
        guard parts.count == 2, parts.allSatisfy({ $0.count >= 2 && $0.allSatisfy(\.isLetter) }) else { return false }
        return UserDictionary.normalizedKey(parts.joined()) == UserDictionary.normalizedKey(word)
    }
}
