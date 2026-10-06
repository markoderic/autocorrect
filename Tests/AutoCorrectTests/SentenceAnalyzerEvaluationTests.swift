import XCTest
import CryptoKit
import AutoCorrectCore
@testable import AutoCorrect

/// Real-analyzer evaluation over the authored held-out grammar, punctuation and leave-alone
/// items (evaluation/corpus). Gated: run with `AUTOCORRECT_SENTENCE_EVALUATION=1`. It uses the
/// analyzer the app would use on this Mac (the on-device model when available, otherwise the
/// system grammar check) followed by `SuggestionValidator`, and prints counts. It never asserts
/// accuracy: the numbers are reported in the work log as what they are.
final class SentenceAnalyzerEvaluationTests: XCTestCase {
    struct Item { let id: String; let text: String; let errors: [(original: String, acceptable: [String])]; let heldOut: Bool; let task: String }

    func testReportRealAnalyzerOnHeldOutCorpus() async throws {
        guard ProcessInfo.processInfo.environment["AUTOCORRECT_SENTENCE_EVALUATION"] == "1" else {
            throw XCTSkip("Set AUTOCORRECT_SENTENCE_EVALUATION=1 to run the real analyzer over the authored corpus")
        }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var items: [Item] = []
        for name in ["grammar", "punctuation", "leave_alone"] {
            let url = root.appendingPathComponent("evaluation/corpus/\(name).jsonl")
            guard let data = try? Data(contentsOf: url), let content = String(data: data, encoding: .utf8) else { continue }
            for line in content.split(separator: "\n") {
                guard let object = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      let id = object["id"] as? String, let text = object["text"] as? String, let group = object["group"] as? String else { continue }
                let errors = (object["errors"] as? [[String: Any]] ?? []).compactMap { e -> (String, [String])? in
                    guard let o = e["original"] as? String, let a = e["acceptable"] as? [String] else { return nil }
                    return (o, a)
                }
                // Same split rule as the evaluation harness: sha1(group) mod 5 < 2 is development.
                let digest = Insecure.SHA1.hash(data: Data(group.utf8))
                var remainder = 0
                for byte in digest { remainder = (remainder * 256 + Int(byte)) % 5 }
                items.append(Item(id: id, text: text, errors: errors.map { (original: $0.0, acceptable: $0.1) }, heldOut: remainder >= 2, task: name))
            }
        }
        let held = items.filter(\.heldOut)
        XCTAssertGreaterThan(held.count, 50)
        let analyzer = SentenceAnalyzers.preferred()
        print("SENTENCE-EVAL analyzer: \(analyzer.availability.summary)")
        var correct = 0, incorrect = 0, missed = 0, unnecessary = 0, leaveAloneItems = 0, leaveAloneChanged = 0, labeled = 0, failures = 0
        var latencies: [Double] = []
        for item in held {
            // Only single-sentence items without line breaks match the app's sentence unit.
            guard !item.text.contains("\n"), let (sentence, _) = SuggestionValidator.lastCompleteSentence(in: item.text + " ") else { continue }
            let start = Date()
            let edits: [ProposedEdit]
            do { edits = try await analyzer.analyze(sentence: sentence) } catch { failures += 1; continue }
            latencies.append(Date().timeIntervalSince(start) * 1000)
            let suggestions = SuggestionValidator.validate(sentence: sentence, edits: edits)
            if item.task == "leave_alone" {
                leaveAloneItems += 1
                if !suggestions.isEmpty { leaveAloneChanged += 1; print("SENTENCE-EVAL unnecessary \(item.id): \(suggestions.map { "\($0.original)→\($0.replacement)" })") }
                continue
            }
            labeled += item.errors.count
            var matchedSuggestions = Set<Int>()
            for error in item.errors {
                if let index = suggestions.firstIndex(where: { $0.original.contains(error.original) || error.original.contains($0.original) }) {
                    matchedSuggestions.insert(index)
                    let s = suggestions[index]
                    let fixed = (sentence as NSString).replacingCharacters(in: s.range, with: s.replacement)
                    let expected = error.acceptable.map { (sentence as NSString).replacingOccurrences(of: error.original, with: $0) }
                    if expected.contains(fixed) { correct += 1 } else { incorrect += 1; print("SENTENCE-EVAL incorrect \(item.id): \(s.original)→\(s.replacement)") }
                } else { missed += 1 }
            }
            unnecessary += suggestions.count - matchedSuggestions.count
        }
        latencies.sort()
        let p50 = latencies.isEmpty ? 0 : latencies[latencies.count / 2]
        let p95 = latencies.isEmpty ? 0 : latencies[min(latencies.count - 1, Int(Double(latencies.count) * 0.95))]
        print("SENTENCE-EVAL held-out labeled errors \(labeled): correct \(correct), incorrect \(incorrect), missed \(missed); unnecessary suggestions on error items \(unnecessary); leave-alone items \(leaveAloneItems) with a suggestion \(leaveAloneChanged); analyzer failures \(failures); latency p50 \(Int(p50)) ms p95 \(Int(p95)) ms")
    }
}
