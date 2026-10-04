import Foundation
import XCTest
@testable import AutoCorrectCore

/// Field-start capitalization policy: the in-progress first word of an otherwise empty
/// prose field (immediate timing) and the completed first word (fallback timing). The
/// caller supplies the field-start evidence; these rules only inspect the text.
final class FieldStartCapitalizationTests: XCTestCase {
    private func immediate(_ text: String) -> CorrectionCandidate? {
        SentenceCapitalization.fieldStartCandidate(in: text)
    }
    private func completed(_ text: String, atFieldStart: Bool = true) -> CorrectionCandidate? {
        SentenceCapitalization.candidate(in: text, caret: text.utf16.count, atFieldStart: atFieldStart)
    }

    func testFirstTypedLetterOfAnEmptyFieldIsTheCandidate() {
        XCTAssertEqual(immediate("h"), CorrectionCandidate(original: "h", range: NSRange(location: 0, length: 1)))
        XCTAssertEqual(immediate("he"), CorrectionCandidate(original: "he", range: NSRange(location: 0, length: 2)))
        XCTAssertEqual(immediate("hello"), CorrectionCandidate(original: "hello", range: NSRange(location: 0, length: 5)))
        XCTAssertEqual(immediate("odnt")?.original, "odnt")
        XCTAssertEqual(immediate("don't")?.original, "don't")
        XCTAssertEqual(SentenceCapitalization.replacement(for: "h"), "H")
    }

    func testLeadingSpacesQuotesAndBracketsAreSupported() {
        XCTAssertEqual(immediate(" h"), CorrectionCandidate(original: "h", range: NSRange(location: 1, length: 1)))
        XCTAssertEqual(immediate("  hi"), CorrectionCandidate(original: "hi", range: NSRange(location: 2, length: 2)))
        XCTAssertEqual(immediate("\"h"), CorrectionCandidate(original: "h", range: NSRange(location: 1, length: 1)))
        XCTAssertEqual(immediate("“h"), CorrectionCandidate(original: "h", range: NSRange(location: 1, length: 1)))
        XCTAssertEqual(immediate("(h"), CorrectionCandidate(original: "h", range: NSRange(location: 1, length: 1)))
        XCTAssertEqual(immediate("[\"h"), CorrectionCandidate(original: "h", range: NSRange(location: 2, length: 1)))
        XCTAssertEqual(immediate("'h"), CorrectionCandidate(original: "h", range: NSRange(location: 1, length: 1)))
        XCTAssertEqual(immediate("\nh"), CorrectionCandidate(original: "h", range: NSRange(location: 1, length: 1)))
    }

    func testNoImmediateCandidateOnceAWordIsCompleteCapitalizedOrNotProse() {
        // Completed words belong to the delimiter path; capitals, emoji prefixes, code,
        // paths, URLs, digits, identifiers and mid-field text are never eligible.
        for text in ["", " ", "h ", "hello ", "H", "Hello", "hE", "🙂 h", "🙂h", "`h", "```", "#h", "@h", "/h", "~h",
                     "1h", "h1", "-h", "*h", "http:", "a.b", "foo h", "x y", "h\n", "héllo", "é", "ñ", "_h", "h_",
                     String(repeating: "h", count: 25)] {
            XCTAssertNil(immediate(text), text.debugDescription)
        }
        XCTAssertNotNil(immediate(String(repeating: "h", count: 24)))
    }

    func testCompletedFirstWordNeedsFieldStartEvidenceFromTheCaller() {
        XCTAssertEqual(completed("hello "), CorrectionCandidate(original: "hello", range: NSRange(location: 0, length: 5)))
        XCTAssertEqual(completed("hello,")?.original, "hello")
        XCTAssertEqual(completed(" hello ")?.range, NSRange(location: 1, length: 5))
        XCTAssertEqual(completed("\"hello ")?.range, NSRange(location: 1, length: 5))
        XCTAssertEqual(completed("odnt ")?.original, "odnt")
        XCTAssertEqual(completed("i ")?.original, "i")
        for text in ["hello ", " hello ", "\"hello "] {
            XCTAssertNil(completed(text, atFieldStart: false), text)
        }
        // Existing sentence-ending behavior is unchanged either way.
        XCTAssertEqual(completed("Hello. next ", atFieldStart: false)?.original, "next")
        XCTAssertEqual(completed("Hello. next ", atFieldStart: true)?.original, "next")
    }

    func testCompletedFirstWordRejectsCapitalsStructuredTokensAndLaterWords() {
        for text in ["Hello ", "iPhone ", "eBay ", "NASA ", "🙂 hello ", "hello world ", "readme.txt ", "https://x.y ",
                     "foo/bar ", "@marko ", "hello  ", "hello\n", "`code ", "x1 "] {
            XCTAssertNil(completed(text), text.debugDescription)
        }
    }
}
