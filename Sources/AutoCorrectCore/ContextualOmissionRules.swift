import Foundation

/// Tiny grammatical frames for omitted letters that happen to form dictionary words.
/// Wait for a completed neighbor; never predict unfinished text or rewrite every valid noun.
public enum ContextualOmissionRules {
    private static let pattern = try! NSRegularExpression(pattern: "[A-Za-z]+(?:['’][A-Za-z]+)?")
    private static let objects: Set<String> = ["this", "that", "the", "a", "an", "my", "your", "his", "her", "our", "their", "me", "you", "him", "it", "them", "us"]
    private static let withVerbs: Set<String> = ["agree", "agrees", "agreed", "help", "helps", "helped", "work", "works", "worked", "working", "deal", "deals", "dealing", "go", "goes", "went", "come", "comes", "came", "start", "starts", "started", "done", "happy", "fine", "okay", "ok", "wrong", "talk", "talking", "speak", "speaking"]
    private static let subjects: Set<String> = ["he", "she", "it", "user", "person", "customer", "client", "someone", "anyone", "everyone", "nobody", "somebody", "everybody"]
    private static let menuKinds: Set<String> = ["file", "edit", "view", "help", "format", "tools", "window", "context", "application", "dropdown"]
    private static let singularThings: Set<String> = ["app", "application", "program", "tool", "feature", "button", "keyboard", "computer", "device", "code", "script", "website", "site", "system", "fix", "test", "plan"]
    private static let bareVerbs: Set<String> = ["work", "help", "start", "stop", "open", "close", "run", "load", "save", "show", "change", "fix", "make", "look", "seem", "feel", "want", "need", "have", "get", "do", "support", "correct", "respond"]

    /// A complete third-person singular subject, not a noun elsewhere in a sentence
    /// ("watch it work", "the app's woks", "two woks", archaic "thou doest").
    private static func singularSubject(_ prefix: String) -> Bool {
        let clause = prefix.components(separatedBy: CharacterSet(charactersIn: ".!?\n")).last ?? prefix
        let text = clause.trimmingCharacters(in: .whitespaces).lowercased()
        let words = text.split(separator: " ").map(String.init)
        guard let last = words.last else { return false }
        let preceding = words.dropLast().last ?? ""
        // A local subject may follow an earlier clause without punctuation in chat.
        // Keep object/quoted-name frames out ("watch it work", "call it woks").
        let objectFrames: Set<String> = ["watch", "watched", "see", "saw", "hear", "heard", "feel", "felt",
            "let", "lets", "make", "makes", "made", "help", "helps", "have", "had", "call", "called", "calls",
            "name", "named", "label", "labeled", "labelled", "dub", "dubbed", "does", "did", "can", "could", "would", "should", "will", "may", "might", "must", "to",
            "with", "without", "in", "on", "at", "for", "of", "about", "from", "by", "over", "under", "near", "beside"]
        if ["it", "he", "she", "this", "that"].contains(last) { return !objectFrames.contains(preceding) }
        return singularThings.contains(last) && ["the", "this", "that", "my", "your", "our"].contains(preceding)
            && !objectFrames.contains(words.dropLast(2).last ?? "")
    }

    private static func omission(_ source: String, of target: String) -> Bool {
        guard source.count + 1 == target.count else { return false }
        return target.indices.contains { index in var copy = target; copy.remove(at: index); return copy == source }
    }

    public static func candidate(in text: String) -> ContextualWritingCandidate? {
        guard text.utf16.count <= 256, text.last.map(CorrectionPolicy.isDelimiter) == true, !text.hasSuffix("  ") else { return nil }
        let ns = text as NSString
        let matches = pattern.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return nil }
        let tokens = matches.map { ns.substring(with: $0.range) }
        func plainGap(_ left: Int, _ right: Int) -> Bool {
            let gap = ns.substring(with: NSRange(location: NSMaxRange(matches[left].range), length: matches[right].range.location - NSMaxRange(matches[left].range)))
            return gap == " "
        }
        for i in stride(from: matches.count - 1, through: max(0, matches.count - 3), by: -1) {
            let original = tokens[i], word = original.lowercased(), range = matches[i].range
            guard !original.dropFirst().contains(where: \.isUppercase) else { continue }
            let prefix = ns.substring(to: range.location)
            guard prefix.isEmpty || prefix.last == " " || prefix.last == "\n" else { continue }
            let suffix = ns.substring(from: NSMaxRange(matches.last!.range))
            guard !suffix.isEmpty, suffix.allSatisfy(CorrectionPolicy.isDelimiter) else { continue }
            let before = i > 0 && plainGap(i-1, i) ? tokens[i-1].lowercased() : ""
            let after = i + 1 < tokens.count && plainGap(i, i+1) ? tokens[i+1].lowercased() : ""
            var replacement: String?
            if word == "doest", singularSubject(prefix), bareVerbs.contains(after) {
                // The reported omitted-n contraction needs a modern subject + base verb;
                // never insert negation into a standalone dictionary word or archaic prose.
                replacement = "doesn't"
            } else if word != "work", omission(word, of: "works"), singularSubject(prefix) {
                replacement = "works"
            } else if word == "os", ns.substring(from: NSMaxRange(range)).hasPrefix(" "), !["import", "from", "module", "called", "named"].contains(before) {
                replacement = "so"
            } else if omission(word, of: "with"), objects.contains(after),
                      prefix.isEmpty || withVerbs.contains(before) {
                replacement = "with"
            } else if omission(word, of: "wants"), subjects.contains(before),
                      after == "to" || objects.contains(after) {
                replacement = "wants"
            } else if omission("this", of: word),
                      ["in", "with", "on", "at", "for", "from", "of", "about"].contains(before),
                      ["prompt", "sentence", "word", "app", "computer", "file", "example", "text", "message", "button", "menu", "screen", "issue", "problem"].contains(after) {
                replacement = "this"
            } else if omission(word, of: "menu"), menuKinds.contains(before) ||
                        (before == "the" && after == "bar") || prefix.lowercased().hasSuffix("drop down ") {
                replacement = "menu"
            }
            if let replacement {
                let styled = original.first?.isUppercase == true ? replacement.prefix(1).uppercased() + replacement.dropFirst() : replacement
                return ContextualWritingCandidate(range: range, original: original, replacement: styled,
                    explanation: "The completed neighboring words support a missing-letter or transposition repair.", automatic: true)
            }
        }
        return nil
    }
}
