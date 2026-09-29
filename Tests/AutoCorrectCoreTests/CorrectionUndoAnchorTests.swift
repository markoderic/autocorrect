import XCTest
@testable import AutoCorrectCore

final class CorrectionUndoAnchorTests: XCTestCase {
    func testContinuedTypingPreservesExactLocation() throws {
        let text = "we corrected this "
        let range = (text as NSString).range(of: "corrected")
        let anchor = try XCTUnwrap(CorrectionUndoAnchor(text: text, windowStart: 100, range: range))
        XCTAssertEqual(anchor.matchingRange(in: text + "and kept typing", windowStart: 100), range)
        // Text following the correction is deliberately outside the saved anchor.
        XCTAssertEqual(anchor.matchingRange(in: "we corrected different text", windowStart: 100), range)
    }

    func testWindowShiftWithFullAnchorPresent() throws {
        let prefix = String(repeating: "a", count: 40) + " "
        let text = prefix + "fixed "
        let anchor = try XCTUnwrap(CorrectionUndoAnchor(text: text, windowStart: 100,
            range: NSRange(location: 41, length: 5)))
        XCTAssertEqual(anchor.matchingRange(in: String(text.dropFirst(9)) + "more", windowStart: 109),
                       NSRange(location: 32, length: 5))
        // One missing unit of the stored prefix invalidates the complete anchor.
        XCTAssertNil(anchor.matchingRange(in: String(text.dropFirst(10)), windowStart: 110))
        XCTAssertEqual(anchor.matchingRange(in: "prior " + text, windowStart: 94), NSRange(location: 47, length: 5))
    }

    func testChangedContextReplacementAndMovedTextFail() throws {
        let text = "we fixed "
        let anchor = try XCTUnwrap(CorrectionUndoAnchor(text: text, windowStart: 0,
            range: NSRange(location: 3, length: 5)))
        for changed in ["he fixed ", "we mixed ", "we  fixed ", "we other fixed ", "we fixe"] {
            XCTAssertNil(anchor.matchingRange(in: changed, windowStart: 0), changed)
        }
        XCTAssertNil(anchor.matchingRange(in: text, windowStart: 1))
        XCTAssertNil(anchor.matchingRange(in: "fixed ", windowStart: 3))
    }

    func testUnicodeContextAndWholeGraphemes() throws {
        let text = "🙂 cafe\u{301} fixed "
        let range = (text as NSString).range(of: "fixed")
        let anchor = try XCTUnwrap(CorrectionUndoAnchor(text: text, windowStart: 50, range: range))
        XCTAssertEqual(anchor.matchingRange(in: text + "next", windowStart: 50), range)
        let composed = "e\u{301} "
        XCTAssertNil(CorrectionUndoAnchor(text: composed, windowStart: 0, range: NSRange(location: 0, length: 1)))
        XCTAssertNil(CorrectionUndoAnchor(text: composed, windowStart: 0, range: NSRange(location: 1, length: 1)))
        XCTAssertNil(CorrectionUndoAnchor(text: "🙂 ", windowStart: 0, range: NSRange(location: 0, length: 1)))
        let full = try XCTUnwrap(CorrectionUndoAnchor(text: composed, windowStart: 0, range: NSRange(location: 0, length: 2)))
        XCTAssertEqual(full.matchingRange(in: composed + "next", windowStart: 0), NSRange(location: 0, length: 2))
        XCTAssertNil(full.matchingRange(in: "e\u{301}\u{323} ", windowStart: 0))
    }

    func testComparisonIsLiteralNotCanonicallyEquivalent() throws {
        let text = "a\u{301}\u{323} fixed "
        let changed = "a\u{323}\u{301} fixed "
        XCTAssertEqual(text, changed) // Swift equality normalizes these sequences.
        let anchor = try XCTUnwrap(CorrectionUndoAnchor(text: text, windowStart: 0,
            range: (text as NSString).range(of: "fixed")))
        XCTAssertNil(anchor.matchingRange(in: changed, windowStart: 0))
    }

    func testPrefixLimitNeverSplitsAnEmoji() throws {
        let text = "🙂" + String(repeating: "a", count: 31) + "fixed "
        let anchor = try XCTUnwrap(CorrectionUndoAnchor(text: text, windowStart: 0,
            range: NSRange(location: 33, length: 5)))
        // Only the 31 ASCII units fit. The two-unit emoji is omitted whole.
        XCTAssertEqual(anchor.matchingRange(in: String(text.dropFirst()), windowStart: 2),
                       NSRange(location: 31, length: 5))
        XCTAssertNil(anchor.matchingRange(in: String(text.dropFirst(2)), windowStart: 3))
    }

    func testInvalidAndOversizedInputsFail() throws {
        for range in [NSRange(location: -1, length: 1), NSRange(location: 0, length: 0),
                      NSRange(location: 0, length: -1), NSRange(location: 4, length: 1),
                      NSRange(location: 1, length: Int.max), NSRange(location: NSNotFound, length: 1)] {
            XCTAssertNil(CorrectionUndoAnchor(text: "word", windowStart: 0, range: range))
        }
        XCTAssertNil(CorrectionUndoAnchor(text: "word", windowStart: -1, range: NSRange(location: 0, length: 4)))
        XCTAssertNil(CorrectionUndoAnchor(text: "word", windowStart: Int.max, range: NSRange(location: 0, length: 4)))
        XCTAssertNil(CorrectionUndoAnchor(text: String(repeating: "a", count: 257), windowStart: 0, range: NSRange(location: 0, length: 1)))
        XCTAssertNil(CorrectionUndoAnchor(text: String(repeating: "a", count: 121), windowStart: 0, range: NSRange(location: 0, length: 121)))
        let anchor = try XCTUnwrap(CorrectionUndoAnchor(text: "word", windowStart: 0, range: NSRange(location: 0, length: 4)))
        XCTAssertNil(anchor.matchingRange(in: "word", windowStart: -1))
        XCTAssertNil(anchor.matchingRange(in: "word", windowStart: Int.max))
        XCTAssertNil(anchor.matchingRange(in: "word" + String(repeating: "a", count: 253), windowStart: 0))
        XCTAssertNil(anchor.matchingRange(in: "", windowStart: 0))
    }
}
