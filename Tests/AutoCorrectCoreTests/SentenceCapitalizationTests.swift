import Foundation
import XCTest
@testable import AutoCorrectCore

final class SentenceCapitalizationTests: XCTestCase {
    private func candidate(_ text: String) -> CorrectionCandidate? {
        SentenceCapitalization.candidate(in: text, caret: text.utf16.count)
    }

    func testCompletedWordAfterPeriod() {
        XCTAssertEqual(candidate("Hello. next "), CorrectionCandidate(original: "next", range: NSRange(location: 7, length: 4)))
        XCTAssertEqual(candidate("Hello. next,")?.original, "next")
        XCTAssertEqual(candidate("Hello.\nnext ")?.original, "next")
        XCTAssertEqual(candidate("Hello.  next ")?.original, "next")
        XCTAssertEqual(SentenceCapitalization.replacement(for: "next"), "Next")
    }

    func testSingleLetterWordsAreIndependentOfSpellingCandidateMinimum() {
        XCTAssertEqual(candidate("Hello. i ")?.original, "i")
        XCTAssertEqual(candidate("Hello. a ")?.original, "a")
        XCTAssertEqual(SentenceCapitalization.replacement(for: "i"), "I")
    }

    func testOptionalOpeningAndClosingQuotesAndBrackets() {
        for text in ["Hello. \"next ", "Hello. (next ", "Hello. “next ", "Hello. 'next ",
                     "\"Hello.\" next ", "(Hello.) next ", "Hello. [next "] {
            XCTAssertEqual(candidate(text)?.original, "next", text)
        }
    }

    func testRejectsAmbiguousAbbreviationsInitialsEllipsesAndStructuredTokens() {
        for text in ["Dr. marko ", "MR. marko ", "etc. next ", "e.g. next ", "i.e. next ", "U.S. next ",
                     "A. next ", "Hello... next ", "Hello… next ", "3. next ", "3.14. next ",
                     "example.com. next ", "https://example.com. next ", "/tmp/file. next ",
                     "Hello. example.com ", "Hello. abc123 ", "Hello. @marko "] {
            XCTAssertNil(candidate(text), text)
        }
    }

    func testRequiresExactPeriodWhitespaceAndCompletedLowercaseWord() {
        for text in ["next ", "Hello next ", "Hello.next ", "Hello! next ", "Hello? next ",
                     "Hello. next", "Hello. Next ", "Hello. NEXT ", "Hello. next\n", "Hello. next\t", "Hello. next  "] {
            XCTAssertNil(candidate(text), text)
        }
    }

    func testUnicodeRangeAndCasePreservation() {
        XCTAssertEqual(candidate("🙂 café. élève ")?.range, NSRange(location: 9, length: 5))
        XCTAssertEqual(candidate("Hello. e\u{301}lan ")?.range, NSRange(location: 7, length: 5))
        XCTAssertNil(candidate("Hello. iPhone "))
        XCTAssertNil(candidate("Hello. eBay "))
        XCTAssertEqual(SentenceCapitalization.replacement(for: "iPhone"), "IPhone")
        XCTAssertEqual(SentenceCapitalization.replacement(for: "élève"), "Élève")
        XCTAssertEqual(SentenceCapitalization.replacement(for: "don't"), "Don't")
        XCTAssertNil(SentenceCapitalization.replacement(for: "ChatGPT"))
        XCTAssertNil(SentenceCapitalization.replacement(for: ""))
    }

    func testInvalidCaretAndCaretBeforeRemainingText() {
        for caret in [-1, 0, 99, Int.max] {
            XCTAssertNil(SentenceCapitalization.candidate(in: "Hello. next ", caret: caret))
        }
        XCTAssertNil(SentenceCapitalization.candidate(in: "🙂 ", caret: 1))
        XCTAssertEqual(SentenceCapitalization.candidate(in: "Hello. next later", caret: 12)?.original, "next")
    }
}
