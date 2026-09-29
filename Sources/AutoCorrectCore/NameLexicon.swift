import Foundation

/// Offline recognition is broader than automatic replacement. A dictionary entry alone
/// is not evidence that a common noun, acronym, filename, or nearby typo should change.
public enum NameLexicon {
    private static let names = Dictionary(uniqueKeysWithValues:
        BundledLexicon.canonicalNames.map { ($0.lowercased(), $0) })
    private static let terms = Set(BundledLexicon.recognizedTerms)
    public static var recognizedTermCount: Int { terms.count }
    public static var canonicalNameCount: Int { names.count }

    public static func recognizes(_ word: String) -> Bool { terms.contains(word.lowercased()) }
    public static func isCanonicalName(_ word: String) -> Bool {
        names[word.lowercased()] == word || BuiltInReplacements.casing[word.lowercased()] == word
    }

    public static func canonicalReplacement(for word: String, nativeMisspelled: Bool) -> String? {
        guard word == word.lowercased(), let name = names[word], name != word else { return nil }
        let mixedCase = !name.allSatisfy(\.isUppercase) && name.dropFirst().contains(where: \.isUppercase)
        return nativeMisspelled || mixedCase ? name : nil
    }

    /// Index only names long enough to disambiguate. Symmetric single-deletion keys
    /// find insertion/deletion/substitution/transposition candidates without scanning
    /// the full dictionary for every word. Exact edit distance verifies the matches.
    private static let repairNames: [String: String] = {
        var result = names.filter { $0.key.count >= 5 }
        for (key, name) in BuiltInReplacements.casing where key.count >= 5 { result[key] = name }
        return result
    }()
    private static let deletionIndex: [String: Set<String>] = {
        var result: [String: Set<String>] = [:]
        for key in repairNames.keys {
            for signature in deletionKeys(key) { result[signature, default: []].insert(key) }
        }
        return result
    }()

    private static func deletionKeys(_ word: String) -> Set<String> {
        let chars = Array(word)
        var keys: Set<String> = [word]
        for index in chars.indices {
            var shortened = chars
            shortened.remove(at: index)
            keys.insert(String(shortened))
        }
        return keys
    }

    /// Only call after native misspelling detection. Uncertain or equally close ordinary
    /// dictionary words block the name guess. Two edits require native top-guess agreement.
    public static func typoReplacement(for word: String, systemCorrection: String?, guesses: [String]) -> String? {
        guard (4...32).contains(word.count), word.allSatisfy({ $0.asciiValue != nil && $0.isLetter }),
              !word.dropFirst().contains(where: \.isUppercase) else { return nil }
        let source = word.lowercased()
        var keys: Set<String> = []
        for signature in deletionKeys(source) { keys.formUnion(deletionIndex[signature] ?? []) }
        // Longer, more damaged names must also be supplied by the native checker.
        if let first = guesses.first?.lowercased(), repairNames[first] != nil { keys.insert(first) }
        let chars = Array(source)
        let ranked = keys.compactMap { key -> (String, Int)? in
            let distance = CorrectionPolicy.editDistance(chars, Array(key))
            if distance == 1 { return (key, distance) }
            if distance == 2, source.count >= 8, key.count >= 8,
               source.first == key.first, source.last == key.last,
               guesses.first?.lowercased() == key, systemCorrection?.lowercased() == key { return (key, distance) }
            return nil
        }.sorted { $0.1 < $1.1 }
        guard let best = ranked.first, ranked.dropFirst().allSatisfy({ $0.1 > best.1 }) else { return nil }
        for other in Array(guesses.prefix(5)) + (systemCorrection.map { [$0] } ?? []) {
            let normalized = other.lowercased()
            if normalized != best.0, CorrectionPolicy.editDistance(chars, Array(normalized)) <= best.1 { return nil }
        }
        return repairNames[best.0]
    }
}
