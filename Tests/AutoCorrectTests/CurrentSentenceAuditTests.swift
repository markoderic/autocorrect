import XCTest
import Foundation
import AutoCorrectCore
@testable import AutoCorrect

final class CurrentSentenceAuditTests: XCTestCase {
 func testCaptureCurrentSentenceSuggestions() async throws {
  let env = ProcessInfo.processInfo.environment
  guard let corpus = env["AUDIT_CORPUS"], let output = env["AUDIT_OUTPUT"] else { throw XCTSkip("Audit paths required") }
  let analyzer = SentenceAnalyzers.preferred()
  let url = URL(fileURLWithPath: output)
  FileManager.default.createFile(atPath: url.path, contents: nil)
  let handle = try FileHandle(forWritingTo: url)
  defer { try? handle.close() }
  var count = 0
  for task in ["grammar", "punctuation", "leave_alone"] {
   let data = try String(contentsOfFile: corpus + "/" + task + ".jsonl", encoding: .utf8)
   for line in data.split(separator: "\n") {
    let item = try JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]
    let text = item["text"] as! String
    var row: [String: Any] = ["candidate": "production_sentence", "version": "0.3.15", "item": item["id"]!, "task": task, "corrected": text, "analyzer": analyzer.availability.summary, "cold": count == 0]
    let start = Date()
    if let unit = SuggestionValidator.analysisUnit(in: text, allowUnterminated: true), unit.sentence == text.trimmingCharacters(in: .whitespacesAndNewlines) {
     do {
      let raw = try await analyzer.analyze(sentence: unit.sentence)
      let suggestions = SuggestionValidator.validate(sentence: unit.sentence, edits: raw)
      row["raw_edits"] = raw.map { ["original": $0.original, "replacement": $0.replacement, "category": $0.category] }
      row["accepted_edits"] = suggestions.map { ["original": $0.original, "replacement": $0.replacement, "category": $0.category.rawValue] }
      var fixed = text as NSString
      for edit in suggestions.reversed() {
       let r = NSRange(location: unit.range.location + edit.range.location, length: edit.range.length)
       fixed = fixed.replacingCharacters(in: r, with: edit.replacement) as NSString
      }
      row["corrected"] = fixed as String
     } catch { row["error"] = String(describing: error) }
    } else { row["skipped"] = "not one whole eligible sentence or paused clause" }
    row["latency_ms"] = Date().timeIntervalSince(start) * 1000
    var serialized = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]);serialized.append(10)
    try handle.write(contentsOf: serialized)
    count += 1
   }
  }
  print("CURRENT-SENTENCE-AUDIT \(count) items: \(analyzer.availability.summary)")
 }
}
