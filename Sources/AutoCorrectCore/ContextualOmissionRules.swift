import Foundation

/// Tiny grammatical frames for omitted letters that happen to form dictionary words.
/// Wait for a completed neighbor; never predict unfinished text or rewrite every valid noun.
public enum ContextualOmissionRules {
    private static let pattern = try! NSRegularExpression(pattern: "[A-Za-z]+(?:['’][A-Za-z]+)?")
    private static let objects: Set<String> = ["this", "that", "the", "a", "an", "my", "your", "his", "her", "our", "their", "me", "you", "him", "it", "them", "us"]
    private static let withVerbs: Set<String> = ["agree", "agrees", "agreed", "help", "helps", "helped", "work", "works", "worked", "working", "deal", "deals", "dealing", "go", "goes", "went", "come", "comes", "came", "start", "starts", "started", "done", "happy", "fine", "okay", "ok", "wrong", "talk", "talking", "speak", "speaking"]
    private static let subjects: Set<String> = ["he", "she", "it", "user", "person", "customer", "client", "someone", "anyone", "everyone", "nobody", "somebody", "everybody"]
    private static let menuKinds: Set<String> = ["file", "edit", "view", "help", "format", "tools", "window", "context", "application", "dropdown"]

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
            if word == "os", ns.substring(from: NSMaxRange(range)).hasPrefix(" "), !["import", "from", "module", "called", "named"].contains(before) {
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
