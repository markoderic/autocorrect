import XCTest
@testable import AutoCorrect

/// Pure placement rules for the Undo popup, with injected geometry in Quartz coordinates
/// (top-left origin). No Accessibility, no windows: these establish the decisions, not that
/// a given editor exposes word positions.
final class CorrectionPopupPlacementTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    private let size = CGSize(width: 180, height: CorrectionPopup.capsuleHeight)
    /// A line of 13-point text: each character 8 points wide, 16 points tall, starting at x = 100.
    private func charRect(_ index: Int, line: Int = 0) -> CGRect { CGRect(x: 100 + 8 * CGFloat(index), y: 300 + 20 * CGFloat(line), width: 8, height: 16) }
    private func span(_ from: Int, _ to: Int, line: Int = 0) -> CGRect { charRect(from, line: line).union(charRect(to, line: line)) }

    // MARK: Capsule

    func testCapsuleSitsBelowTheWordByDefault() throws {
        let word = CGRect(x: 300, y: 400, width: 40, height: 16)
        let frame = try XCTUnwrap(CorrectionPopup.capsuleFrame(word: word, caret: nil, visible: nil, size: size, screens: [screen]))
        XCTAssertEqual(frame.minX, 300)
        XCTAssertEqual(frame.minY, word.maxY + CorrectionPopup.gap)
        XCTAssertEqual(frame.size, size)
    }

    func testCapsuleMovesAboveWhenThereIsNoRoomBelow() throws {
        let word = CGRect(x: 300, y: 880, width: 40, height: 16)
        let frame = try XCTUnwrap(CorrectionPopup.capsuleFrame(word: word, caret: nil, visible: nil, size: size, screens: [screen]))
        XCTAssertEqual(frame.maxY, word.minY - CorrectionPopup.gap)
    }

    func testCapsuleIsClampedToTheScreenHorizontally() throws {
        let word = CGRect(x: 1400, y: 400, width: 30, height: 16)
        let frame = try XCTUnwrap(CorrectionPopup.capsuleFrame(word: word, caret: nil, visible: nil, size: size, screens: [screen]))
        XCTAssertLessThanOrEqual(frame.maxX, screen.maxX - 4)
    }

    func testCapsuleAvoidsTheCaretRectangle() throws {
        let word = CGRect(x: 300, y: 400, width: 40, height: 16)
        let caret = CGRect(x: 300, y: word.maxY + CorrectionPopup.gap + 2, width: 2, height: 16)
        let frame = try XCTUnwrap(CorrectionPopup.capsuleFrame(word: word, caret: caret, visible: nil, size: size, screens: [screen]))
        XCTAssertEqual(frame.maxY, word.minY - CorrectionPopup.gap, "placed above instead of covering the caret")
    }

    func testNoPlacementWhenBothSidesWouldCoverTheCaretOrLeaveTheScreen() {
        let word = CGRect(x: 300, y: 10, width: 40, height: 16)
        let caret = CGRect(x: 300, y: word.maxY + CorrectionPopup.gap, width: 200, height: 40)
        XCTAssertNil(CorrectionPopup.capsuleFrame(word: word, caret: caret, visible: nil, size: size, screens: [screen]))
    }

    func testWordOutsideTheVisibleEditorAreaIsNotAnnotated() {
        let word = CGRect(x: 300, y: 400, width: 40, height: 16)
        let visible = CGRect(x: 0, y: 500, width: 1440, height: 300)
        XCTAssertNil(CorrectionPopup.capsuleFrame(word: word, caret: nil, visible: visible, size: size, screens: [screen]))
    }

    func testWordOnAnotherScreenUsesThatScreen() throws {
        let second = CGRect(x: 1440, y: -200, width: 1920, height: 1080)
        let word = CGRect(x: 3300, y: 300, width: 40, height: 16)
        let frame = try XCTUnwrap(CorrectionPopup.capsuleFrame(word: word, caret: nil, visible: nil, size: size, screens: [screen, second]))
        XCTAssertTrue(second.contains(frame))
        XCTAssertNil(CorrectionPopup.capsuleFrame(word: CGRect(x: 5000, y: 300, width: 40, height: 16), caret: nil, visible: nil, size: size, screens: [screen, second]))
    }

    // MARK: Single-line verification

    func testUntrustworthyGeometryIsRejected() {
        let good = CGRect(x: 100, y: 300, width: 24, height: 16)
        for word in [CGRect.zero, CGRect(x: 0, y: 982, width: 0, height: 0), CGRect(x: 10, y: 10, width: 5000, height: 16),
                     CGRect(x: CGFloat.nan, y: 10, width: 40, height: 16), CGRect(x: 10, y: 10, width: 40, height: 2)] {
            XCTAssertNil(CorrectionPopup.verifiedWord(word: word, first: charRect(0), last: charRect(2)), "\(word)")
            XCTAssertNil(CorrectionPopup.capsuleFrame(word: word, caret: nil, visible: nil, size: size, screens: [screen]), "\(word)")
            XCTAssertNil(CorrectionPopup.dotFrame(lineEnd: word, caret: nil, visible: nil, screens: [screen]), "\(word)")
        }
        XCTAssertNil(CorrectionPopup.verifiedWord(word: good, first: nil, last: charRect(2)), "missing first-character rectangle")
        XCTAssertNil(CorrectionPopup.verifiedWord(word: good, first: charRect(0), last: nil), "missing last-character rectangle")
        XCTAssertNil(CorrectionPopup.verifiedWord(word: nil, first: nil, last: nil))
    }

    func testWrappedWordIsNotAnnotated() {
        // "the" starts at the end of line 0 and ends on line 1: a tall union rectangle, well under 100 points.
        let first = charRect(70, line: 0), last = charRect(1, line: 1)
        XCTAssertNil(CorrectionPopup.verifiedWord(word: first.union(last), first: first, last: last))
    }

    func testSingleLineWordPasses() throws {
        let word = try XCTUnwrap(CorrectionPopup.verifiedWord(word: span(4, 6), first: charRect(4), last: charRect(6)))
        XCTAssertEqual(word, span(4, 6))
    }

    // MARK: Dot

    func testDotSitsAfterTheEndOfTheLineNotAfterTheWord() throws {
        // "the next word": the corrected word is "the" (0...2); the line ends at index 12.
        let lineEnd = charRect(12)
        let dot = try XCTUnwrap(CorrectionPopup.dotFrame(lineEnd: lineEnd, caret: nil, visible: nil, screens: [screen]))
        XCTAssertEqual(dot.minX, lineEnd.maxX + 3)
        XCTAssertEqual(dot.midY, lineEnd.midY, accuracy: 0.01)
        for index in 0...12 { XCTAssertFalse(dot.intersects(charRect(index)), "dot covers character \(index)") }
    }

    func testDotNeverLandsInTheNarrowSpaceBetweenWords() throws {
        // Even a 4-point space after "the" is irrelevant: the dot follows the line end, not the span.
        let lineEnd = charRect(12)
        let nextWord = span(4, 7)
        let dot = try XCTUnwrap(CorrectionPopup.dotFrame(lineEnd: lineEnd, caret: nil, visible: nil, screens: [screen]))
        XCTAssertFalse(dot.intersects(nextWord))
        XCTAssertGreaterThan(dot.minX, nextWord.maxX)
    }

    func testDotMovesPastTheCaretWhenTypingContinuesAtTheLineEnd() throws {
        let lineEnd = charRect(12)
        let caret = CGRect(x: charRect(13).minX, y: 300, width: 2, height: 16)   // caret right after the last character
        let dot = try XCTUnwrap(CorrectionPopup.dotFrame(lineEnd: lineEnd, caret: caret, visible: nil, screens: [screen]))
        XCTAssertGreaterThanOrEqual(dot.minX, caret.maxX + 3)
        XCTAssertFalse(dot.insetBy(dx: -1, dy: -1).intersects(caret))
    }

    func testFirstLetterCapitalizationWithLettersAppendedAfterTheSpan() throws {
        // "Hello world" where the record covers only "H" (index 0); letters 1...10 follow on the same line.
        let lineEnd = charRect(10)
        let dot = try XCTUnwrap(CorrectionPopup.dotFrame(lineEnd: lineEnd, caret: nil, visible: nil, screens: [screen]))
        for index in 0...10 { XCTAssertFalse(dot.intersects(charRect(index)), "dot covers appended letter \(index)") }
    }

    func testDotIsNotDrawnWhenItWouldLeaveTheVisibleAreaOrTheScreen() {
        let lineEnd = charRect(12)
        let visible = CGRect(x: 0, y: 290, width: lineEnd.maxX + 4, height: 40)   // too narrow for the dot
        XCTAssertNil(CorrectionPopup.dotFrame(lineEnd: lineEnd, caret: nil, visible: visible, screens: [screen]))
        let farRight = CGRect(x: screen.maxX - 6, y: 300, width: 5, height: 16)
        XCTAssertNil(CorrectionPopup.dotFrame(lineEnd: farRight, caret: nil, visible: nil, screens: [screen]))
        let scrolledOut = CGRect(x: 0, y: 500, width: 1440, height: 300)
        XCTAssertNil(CorrectionPopup.dotFrame(lineEnd: lineEnd, caret: nil, visible: scrolledOut, screens: [screen]))
    }

    func testDotHidesWhenTheCaretWouldStillOverlap() {
        let lineEnd = charRect(12)
        let wideCaret = CGRect(x: lineEnd.maxX, y: 296, width: 60, height: 24) // a selection-like rectangle covering the gap
        // The dot moves past the caret's right edge, so it must not intersect; verify the rule holds.
        if let dot = CorrectionPopup.dotFrame(lineEnd: lineEnd, caret: wideCaret, visible: nil, screens: [screen]) {
            XCTAssertFalse(dot.insetBy(dx: -1, dy: -1).intersects(wideCaret))
        }
    }
}
