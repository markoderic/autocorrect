import Foundation

/// A reviewable sentence-level suggestion: one bounded span replacement inside an analyzed
/// sentence, with the sentence it depends on. It never applies itself; the app re-validates the
/// field, the sentence and the span before any edit.
public struct SentenceSuggestion: Equatable, Sendable {
    public enum Category: String, Sendable { case grammar, punctuation }
    public let id: UUID
    public let category: Category
    /// Range of the replaced span inside `sentence` (UTF-16).
    public let range: NSRange
    public let original: String
    public let replacement: String
    public let explanation: String
    /// The exact analyzed sentence. If the sentence changes, the suggestion is void.
    public let sentence: String

    public init(id: UUID = UUID(), category: Category, range: NSRange, original: String, replacement: String, explanation: String, sentence: String) {
        self.id = id; self.category = category; self.range = range; self.original = original
        self.replacement = replacement; self.explanation = explanation; self.sentence = sentence
    }
}

/// An edit as an analyzer reports it: free text, not yet trusted.
public struct ProposedEdit: Equatable, Sendable {
    public let original: String
    public let replacement: String
    public let category: String
    public let explanation: String
    public init(original: String, replacement: String, category: String, explanation: String) {
        self.original = original; self.replacement = replacement; self.category = category; self.explanation = explanation
    }
}

/// Deterministic checks between an analyzer (rules or model) and the writer. Every rule here
/// rejects a proposal; nothing here makes a proposal more trusted than "worth showing".
public enum SuggestionValidator {
    public struct Options: Sendable {
        public var allowGrammar = true
        public var allowPunctuation = true
        public init(allowGrammar: Bool = true, allowPunctuation: Bool = true) {
            self.allowGrammar = allowGrammar; self.allowPunctuation = allowPunctuation
        }
    }

    private static let negation = try! NSRegularExpression(pattern: "\\b(not|no|never|nothing|nobody|none|neither|nor|cannot|without)\\b|n't\\b", options: [.caseInsensitive])
    private static let number = try! NSRegularExpression(pattern: "\\d[\\d,.:]*")
    private static let protected = try! NSRegularExpression(pattern: "`[^`\\n]+`|https?://[^\\s)\\]]+|[\\w.+-]+@[\\w-]+\\.[\\w.-]+|(?:~|\\.)?/[\\w./-]+/[\\w./-]*|\\b[A-Z][A-Z0-9_]+=\\S+|\\b\\w+\\.(?:[a-z]{2,4})\\b")
    private static let word = try! NSRegularExpression(pattern: "[\\p{L}\\p{N}'’]+")

    /// Turns raw edits for `sentence` into suggestions, dropping anything ambiguous or unsafe:
    /// an original that is empty, identical to its replacement, absent or not unique in the
    /// sentence, or not on word boundaries; replacements that add or change numbers, protected
    /// tokens (code, URLs, emails, paths, filenames), capitalized words other than the first, or
    /// the count of negation tokens; replacements much longer than the original; spans or
    /// replacements that do not begin and end with letters (the keyboard edit plan could not
    /// apply them); unknown categories; and categories the user turned off. Overlapping edits
    /// keep the first.
    public static func validate(sentence: String, edits: [ProposedEdit], options: Options = Options()) -> [SentenceSuggestion] {
        let ns = sentence as NSString
        var accepted: [SentenceSuggestion] = []
        for edit in edits {
            let original = edit.original
            let replacement = edit.replacement.replacingOccurrences(of: "\n", with: " ")
            guard !original.isEmpty, original != replacement, replacement.count <= original.count * 2 + 24,
                  UserDictionary.isValidReplacement(replacement),
                  // The guarded keyboard edit plan replaces spans that begin and end with letters;
                  // a span it could not apply must never be offered.
                  original.first?.isLetter == true, original.last?.isLetter == true,
                  replacement.first?.isLetter == true, replacement.last?.isLetter == true else { continue }
            guard let category = SentenceSuggestion.Category(rawValue: edit.category.lowercased()) else { continue }
            if category == .grammar, !options.allowGrammar { continue }
            if category == .punctuation, !options.allowPunctuation { continue }
            // Exactly one occurrence, on word boundaries.
            let first = ns.range(of: original)
            guard first.location != NSNotFound else { continue }
            let second = ns.range(of: original, options: [], range: NSRange(location: NSMaxRange(first), length: ns.length - NSMaxRange(first)))
            guard second.location == NSNotFound else { continue }
            guard isBoundary(ns, at: first.location, before: true), isBoundary(ns, at: NSMaxRange(first), before: false) else { continue }
            if accepted.contains(where: { NSIntersectionRange($0.range, first).length > 0 }) { continue }
            let before = ns.replacingCharacters(in: first, with: "") as String
            let after = ns.replacingCharacters(in: first, with: replacement) as String
            _ = before
            // Semantic guards on the whole sentence, before and after.
            guard matches(number, in: sentence) == matches(number, in: after) else { continue }
            guard Set(matches(protected, in: sentence)).isSubset(of: Set(matches(protected, in: after))) else { continue }
            guard matches(negation, in: sentence).count == matches(negation, in: after).count else { continue }
            guard capitalizedWords(in: sentence, excludingFirst: true).isSubset(of: capitalizedWords(in: after, excludingFirst: false)) else { continue }
            let explanation = edit.explanation.trimmingCharacters(in: .whitespacesAndNewlines)
            accepted.append(SentenceSuggestion(category: category, range: first, original: original, replacement: replacement,
                                               explanation: explanation.isEmpty ? defaultExplanation(category) : String(explanation.prefix(120)),
                                               sentence: sentence))
        }
        return accepted.sorted { $0.range.location < $1.range.location }
    }

    /// The unit to analyze at the end of a bounded text window, with its range in `text`.
    /// A terminated sentence (`.`, `!`, `?`, optionally followed by closing quotes or brackets)
    /// is eligible at a word boundary or a pause. Without a terminator, only a pause may analyze
    /// the trailing clause (`allowUnterminated`), and only when it has at least `minimumClauseWords`
    /// words and begins inside the window: a clause that starts at the window's first character
    /// while the window itself starts mid-document (`windowStart > 0`) may be truncated and is
    /// never treated as a whole sentence. Nothing here adds punctuation.
    public static func analysisUnit(in text: String, windowStart: Int = 0, allowUnterminated: Bool = false,
                                    minimumWords: Int = 3, minimumClauseWords: Int = 4, maximumLength: Int = 512) -> (sentence: String, range: NSRange)? {
        let ns = text as NSString
        var end = ns.length
        func scalar(_ index: Int) -> UnicodeScalar? { index >= 0 && index < ns.length ? UnicodeScalar(ns.character(at: index)) : nil }
        while end > 0, let s = scalar(end - 1), CharacterSet.whitespacesAndNewlines.contains(s) { end -= 1 }
        guard end > 0 else { return nil }
        // Closing quotes and brackets after the terminator belong to the sentence.
        var probe = end
        while probe > 0, let s = scalar(probe - 1), "\"”’')]}".unicodeScalars.contains(s) { probe -= 1 }
        // A UTF-16 window may end with a surrogate pair (for example an emoji).
        let terminated = scalar(probe - 1).map { ".!?".unicodeScalars.contains($0) } ?? false
        if !terminated {
            guard allowUnterminated else { return nil }
            probe = end
        }
        // Walk back to the previous terminator followed by whitespace, or a line break.
        var start = terminated ? probe - 1 : probe
        while start > 0 {
            guard let s = scalar(start - 1) else { start -= 1; continue }
            if s == "\n" || s == "\r" { break }
            if ".!?".unicodeScalars.contains(s), start < end {
                var after = start
                while let closer = scalar(after), "\"”’')]}".unicodeScalars.contains(closer) { after += 1 }
                if let next = scalar(after), CharacterSet.whitespacesAndNewlines.contains(next) { start = after; break }
            }
            start -= 1
        }
        var range = NSRange(location: start, length: end - start)
        while range.length > 0, let s = scalar(range.location), CharacterSet.whitespacesAndNewlines.contains(s) {
            range.location += 1; range.length -= 1
        }
        guard range.length > 0, range.length <= maximumLength else { return nil }
        if start == 0, windowStart > 0 { return nil }   // possibly truncated, even with a final period
        let sentence = ns.substring(with: range)
        let words = matches(word, in: sentence).count
        guard words >= (terminated ? minimumWords : minimumClauseWords) else { return nil }
        return (sentence, range)
    }

    /// The last complete sentence of a bounded text window (terminator required).
    public static func lastCompleteSentence(in text: String, minimumWords: Int = 3, maximumLength: Int = 512) -> (sentence: String, range: NSRange)? {
        analysisUnit(in: text, allowUnterminated: false, minimumWords: minimumWords, maximumLength: maximumLength)
    }

    private static func isBoundary(_ ns: NSString, at index: Int, before: Bool) -> Bool {
        let neighbor = before ? index - 1 : index
        guard neighbor >= 0, neighbor < ns.length else { return true }
        guard let scalar = UnicodeScalar(ns.character(at: neighbor)) else { return false }
        return !(CharacterSet.alphanumerics.contains(scalar) || scalar == "_")
    }

    private static func matches(_ regex: NSRegularExpression, in text: String) -> [String] {
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }

    private static func capitalizedWords(in text: String, excludingFirst: Bool) -> Set<String> {
        var words = matches(word, in: text)
        if excludingFirst, !words.isEmpty { words.removeFirst() }
        return Set(words.filter { $0.first?.isUppercase == true && $0.count > 1 && $0 != $0.uppercased() })
    }

    private static func defaultExplanation(_ category: SentenceSuggestion.Category) -> String {
        category == .grammar ? "Grammar suggestion" : "Punctuation suggestion"
    }
}
