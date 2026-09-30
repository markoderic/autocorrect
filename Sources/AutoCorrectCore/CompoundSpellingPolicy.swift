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

    /// A top-five guess that spells the typed letters as a prose phrase (as well, up to,
    /// a bit, in front, so far). macOS recommends swell/unto/bit/infant/solar for those:
    /// a different single word that drops or changes typed letters. Callers block such
    /// repairs but may keep one that only adds letters (adress → address, becase →
    /// because), since a phrase reading does not contradict a missing letter.
    /// Among several splits the longest function-word start wins (as well over a swell).
    public static func prosePhrase(for word: String, guesses: [String]) -> String? {
        guard (4...32).contains(word.count), word.allSatisfy(\.isLetter) else { return nil }
        let key = UserDictionary.normalizedKey(word)
        var best: (phrase: String, startLength: Int)?
        for guess in guesses.prefix(5) {
            let parts = guess.split(whereSeparator: { $0 == " " || $0 == "-" })
            guard parts.count == 2, parts.allSatisfy({ $0.allSatisfy(\.isLetter) }), parts[1].count >= 2,
                  UserDictionary.normalizedKey(parts.joined()) == key,
                  JoinedWordPolicy.proseStarts.contains(String(parts[0]).lowercased()) else { continue }
            if best == nil || parts[0].count > best!.startLength {
                best = (parts.joined(separator: " "), parts[0].count)
            }
        }
        return best?.phrase
    }

    /// True when every typed letter appears, in order, in the repair (a pure insertion).
    public static func preservesTypedLetters(of word: String, in repair: String) -> Bool {
        let source = Array(UserDictionary.normalizedKey(word))
        var matched = 0
        for character in UserDictionary.normalizedKey(repair) where matched < source.count {
            if character == source[matched] { matched += 1 }
        }
        return matched == source.count
    }
}
