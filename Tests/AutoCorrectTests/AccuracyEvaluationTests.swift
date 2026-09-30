import XCTest
@testable import AutoCorrect

/// Held-out evaluation over the pinned public corpus in `evaluation/`. It runs the same
/// completed-word assessment the keyboard path uses, against the host's actual
/// NSSpellChecker, and writes `evaluation/latest-report.md`. Skipped unless
/// AUTOCORRECT_EVALUATION=1 so the ordinary suite stays fast and deterministic.
/// The counts describe one corpus on one host; they are not English accuracy.
final class AccuracyEvaluationTests: XCTestCase {
    private struct Entry {
        let typed: String
        let targets: [String]
        let heldOut: Bool
    }
    private struct Native {
        var queried = false
        var misspelled = false
        var correction: String?
        var guesses: [String] = []
    }
    private enum Outcome: String, CaseIterable {
        case correct, correctCaseOnly = "correct (case differs)", variant = "en_US variant of expected"
        case missed, falseCorrection = "false correction"
        case ambiguousAbstained = "ambiguous: abstained", ambiguousChoseListed = "ambiguous: chose a listed correction"
        case ambiguousWrong = "ambiguous: false correction"
    }
    private enum MissReason: String, CaseIterable {
        case accepted = "dictionary accepts the misspelling"
        case noRecommendation = "flagged, no native automatic recommendation"
        case declinedTop = "policy declined; expected word is the top native guess"
        case declinedRanked = "policy declined; expected word is ranked 2-5"
        case declinedAbsent = "policy declined; expected word absent from top-5 guesses"
    }
    private struct Observation {
        let entry: Entry
        let context: String
        let result: String?
        let outcome: Outcome
        let reason: MissReason?
        let native: Native
    }

    func testWikipediaCommonMisspellingsReport() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["AUTOCORRECT_EVALUATION"] == "1" else {
            throw XCTSkip("Set AUTOCORRECT_EVALUATION=1 to run the held-out evaluation (about a minute).")
        }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let corpusURL = root.appendingPathComponent("evaluation/wikipedia-common-misspellings.txt")
        let corpus = try String(contentsOf: corpusURL, encoding: .utf8)

        var entries: [Entry] = []
        var skipped = 0
        for line in corpus.components(separatedBy: "\n") {
            guard let arrow = line.range(of: "->") else { continue }
            let typed = line[..<arrow.lowerBound].trimmingCharacters(in: .whitespaces)
            let targets = line[arrow.upperBound...].components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard Self.isToken(typed), !targets.isEmpty,
                  !targets.contains(where: { $0.caseInsensitiveCompare(typed) == .orderedSame }) else { skipped += 1; continue }
            entries.append(Entry(typed: typed, targets: targets, heldOut: entries.count % 2 == 1))
        }
        XCTAssertGreaterThan(entries.count, 3000, "corpus parsed")

        let suite = "AccuracyEvaluation.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)
        preferences.language = "en_US"
        let engine = CorrectionEngine(preferences: preferences)
        var native = Native()
        engine.nativeAssessmentObserver = { _, misspelled, correction, guesses in
            native.queried = true
            native.misspelled = misspelled
            if correction != nil || !guesses.isEmpty { native.correction = correction; native.guesses = guesses }
        }
        func assess(_ text: String) -> (String?, Native) {
            native = Native()
            let result = engine.suggestion(in: text)
            return (result, native)
        }

        let contexts = ["", "please check "]
        var observations: [Observation] = []
        for entry in entries {
            for context in contexts {
                let (result, signal) = assess(context + entry.typed + " ")
                let outcome: Outcome
                var reason: MissReason?
                let listed = entry.targets.contains { $0 == result }
                let listedCase = result.map { r in entry.targets.contains { $0.lowercased() == r.lowercased() } } ?? false
                if entry.targets.count == 1 {
                    if result == nil {
                        outcome = .missed
                        reason = Self.reason(for: entry.targets[0], native: signal)
                    } else if listed { outcome = .correct }
                    else if listedCase { outcome = .correctCaseOnly }
                    else if Self.variantKey(result!) == Self.variantKey(entry.targets[0]) { outcome = .variant }
                    else { outcome = .falseCorrection }
                } else {
                    if result == nil { outcome = .ambiguousAbstained }
                    else if listed || listedCase { outcome = .ambiguousChoseListed }
                    else { outcome = .ambiguousWrong }
                }
                observations.append(Observation(entry: entry, context: context, result: result,
                                                outcome: outcome, reason: reason, native: signal))
            }
        }

        // Controls: every distinct single-word correction typed correctly. Any change is a
        // false correction of a valid word (British/archaic spellings are listed separately).
        var controls: [String] = []
        var seen = Set<String>()
        for entry in entries where entry.targets.count == 1 {
            let word = entry.targets[0]
            guard Self.isToken(word), seen.insert(word.lowercased()).inserted else { continue }
            controls.append(word)
        }
        var controlChanges: [(String, String, Bool)] = []
        for word in controls {
            let (result, signal) = assess("please check " + word + " ")
            if let result { controlChanges.append((word, result, signal.misspelled)) }
        }

        // Machine-readable signals for offline policy simulation (ignored by git).
        let dump: [[String: Any]] = observations.map { o in
            ["typed": o.entry.typed, "targets": o.entry.targets, "heldOut": o.entry.heldOut, "context": o.context,
             "result": o.result as Any, "outcome": o.outcome.rawValue, "queried": o.native.queried,
             "misspelled": o.native.misspelled, "correction": o.native.correction as Any, "guesses": o.native.guesses]
        }
        let json = try JSONSerialization.data(withJSONObject: dump, options: [.prettyPrinted, .sortedKeys])
        try json.write(to: root.appendingPathComponent("evaluation/observations.json"))

        let report = Self.render(observations: observations, contexts: contexts, entries: entries.count, skipped: skipped,
                                 controls: controls.count, controlChanges: controlChanges)
        let output = environment["AUTOCORRECT_EVALUATION_REPORT"].map { URL(fileURLWithPath: $0) }
            ?? root.appendingPathComponent("evaluation/latest-report.md")
        try report.write(to: output, atomically: true, encoding: .utf8)
        print(report.components(separatedBy: "\n## Lists")[0])
        print("Report written to \(output.path)")
    }

    private static func isToken(_ word: String) -> Bool {
        guard (2...32).contains(word.count), word.first?.isLetter == true, word.last?.isLetter == true,
              !word.dropFirst().contains(where: \.isUppercase) else { return false }
        return word.allSatisfy { $0.isLetter || $0 == "'" }
    }

    /// Collapses common British/American spelling differences so an en_US repair of a
    /// British target (endeavour → endeavor) is reported as a variant, not a false correction.
    private static func variantKey(_ word: String) -> String {
        var key = word.lowercased()
        for (british, american) in [("our", "or"), ("ae", "e"), ("oe", "e"), ("is", "iz"), ("ys", "yz"), ("ll", "l"), ("re", "er")] {
            key = key.replacingOccurrences(of: british, with: american)
        }
        return key
    }

    private static func reason(for target: String, native: Native) -> MissReason {
        guard native.misspelled else { return .accepted }
        guard native.correction != nil || !native.guesses.isEmpty else { return .noRecommendation }
        if native.correction == nil, native.guesses.isEmpty { return .noRecommendation }
        let key = target.lowercased()
        if let first = native.guesses.first, first.lowercased() == key { return .declinedTop }
        if native.guesses.prefix(5).contains(where: { $0.lowercased() == key }) { return .declinedRanked }
        return .declinedAbsent
    }

    private static func render(observations: [Observation], contexts: [String], entries: Int, skipped: Int,
                               controls: Int, controlChanges: [(String, String, Bool)]) -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let formatter = ISO8601DateFormatter()
        var lines: [String] = []
        lines.append("# Held-out accuracy evaluation report")
        lines.append("")
        lines.append("- Generated: \(formatter.string(from: Date()))")
        lines.append("- Host: macOS \(os)")
        lines.append("- Corpus: Wikipedia common misspellings, revision 1199637275 (CC BY-SA 4.0); \(entries) usable entries, \(skipped) skipped (multi-token, non-letter, or identical)")
        lines.append("- Contexts: isolated word; after `please check`")
        lines.append("- Path: `CorrectionEngine.suggestion(in:)`, the same completed-word assessment the keyboard uses; no events or Accessibility")
        lines.append("")
        for partition in [false, true] {
            lines.append("## \(partition ? "Held-out" : "Development") half")
            lines.append("")
            lines.append("| Outcome | " + contexts.map { $0.isEmpty ? "isolated" : "`\($0.trimmingCharacters(in: .whitespaces))`" }.joined(separator: " | ") + " |")
            lines.append("| --- | " + contexts.map { _ in "---:" }.joined(separator: " | ") + " |")
            for outcome in Outcome.allCases {
                let counts = contexts.map { context in
                    observations.filter { $0.entry.heldOut == partition && $0.context == context && $0.outcome == outcome }.count
                }
                lines.append("| \(outcome.rawValue) | " + counts.map(String.init).joined(separator: " | ") + " |")
            }
            lines.append("")
            lines.append("Misses by native signal:")
            lines.append("")
            lines.append("| Reason | " + contexts.map { $0.isEmpty ? "isolated" : "in sentence" }.joined(separator: " | ") + " |")
            lines.append("| --- | " + contexts.map { _ in "---:" }.joined(separator: " | ") + " |")
            for reason in MissReason.allCases {
                let counts = contexts.map { context in
                    observations.filter { $0.entry.heldOut == partition && $0.context == context && $0.reason == reason }.count
                }
                lines.append("| \(reason.rawValue) | " + counts.map(String.init).joined(separator: " | ") + " |")
            }
            lines.append("")
        }
        lines.append("## Controls")
        lines.append("")
        let flagged = controlChanges.filter { $0.2 }
        lines.append("- \(controls) distinct correct spellings typed after `please check`; \(controlChanges.count) changed (\(flagged.count) of those are words the native dictionary itself flags, typically British or archaic spellings).")
        lines.append("")
        lines.append("## Lists")
        lines.append("")
        lines.append("### False corrections (single-target entries)")
        lines.append("")
        for o in observations where o.outcome == .falseCorrection || o.outcome == .ambiguousWrong {
            lines.append("- `\(o.entry.typed)` → `\(o.result ?? "")` (expected \(o.entry.targets.map { "`\($0)`" }.joined(separator: ", "))) [\(o.context.isEmpty ? "isolated" : "sentence")] native: \(o.native.correction ?? "nil") \(o.native.guesses.prefix(5))")
        }
        lines.append("")
        lines.append("### Valid words changed (controls)")
        lines.append("")
        for (word, result, misspelled) in controlChanges {
            lines.append("- `\(word)` → `\(result)`\(misspelled ? " (native flags the word)" : "")")
        }
        lines.append("")
        lines.append("### Misses (isolated context) by reason")
        lines.append("")
        for reason in MissReason.allCases {
            let misses = observations.filter { $0.context.isEmpty && $0.reason == reason }
            lines.append("#### \(reason.rawValue) (\(misses.count))")
            lines.append("")
            for o in misses {
                lines.append("- `\(o.entry.typed)` → expected `\(o.entry.targets[0])`; native: \(o.native.correction ?? "nil") \(o.native.guesses.prefix(5))")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}
