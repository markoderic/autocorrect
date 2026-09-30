import XCTest
import AutoCorrectCore
@testable import AutoCorrect

/// Overlay placement without Accessibility: geometry providers are injected. Rects use
/// Quartz screen coordinates (top-left origin) as AXBoundsForRange reports them.
final class UnderlinePlacementTests: XCTestCase {
    private let line1 = CGRect(x: 100, y: 200, width: 0, height: 14)

    private func wordRect(_ x: CGFloat, _ width: CGFloat, line: Int = 0) -> CGRect {
        CGRect(x: x, y: 200 + CGFloat(line) * 14, width: width, height: 14)
    }

    func testEachMarkGetsAWaveUnderItsWordAndThePanelCoversAllOfThem() {
        let marks = [SpellingMark(location: 8, word: "aswell"), SpellingMark(location: 15, word: "abit")]
        // Whole-word bounds plus first/last character bounds, all on one line.
        let rects: [String: CGRect] = ["8:6": wordRect(140, 40), "15:4": wordRect(190, 24),
                                       "8:1": wordRect(140, 6), "13:1": wordRect(174, 6),
                                       "15:1": wordRect(190, 6), "18:1": wordRect(208, 6)]
        let result = SpellingIndicator.placements(for: marks, visible: CGRect(x: 0, y: 0, width: 800, height: 600),
            bounds: { range in rects["\(range.location):\(range.length)"] }, line: { _ in 0 })
        XCTAssertEqual(result.placed.map(\.mark.word), ["aswell", "abit"])
        XCTAssertEqual(result.placed[0].rect, wordRect(140, 40))
        XCTAssertEqual(result.failed, 0)
        XCTAssertEqual(result.hidden, 0)
        XCTAssertEqual(SpellingIndicator.panelFrame(for: result.placed.map(\.rect)), CGRect(x: 140, y: 200, width: 74, height: 14))
    }

    func testWrappedWordsCountAsGeometryFailuresAndOffscreenWordsAsHidden() {
        let marks = [SpellingMark(location: 0, word: "wrapped"), SpellingMark(location: 20, word: "below"), SpellingMark(location: 40, word: "fine")]
        let result = SpellingIndicator.placements(for: marks, visible: CGRect(x: 0, y: 0, width: 800, height: 230),
            bounds: { range in
                switch range.location {
                case 0 where range.length == 7: return CGRect(x: 100, y: 200, width: 500, height: 28)   // union of two lines
                case 0: return wordRect(700, 6)                                                       // first char, line 1
                case 6: return wordRect(100, 6, line: 1)                                             // last char, line 2
                case 20 where range.length == 5: return wordRect(100, 30, line: 3)                    // beyond the visible bottom
                case 20, 24: return wordRect(100, 6, line: 3)
                case 40 where range.length == 4: return wordRect(300, 24)
                case 40, 43: return wordRect(300, 6)
                default: return nil
                }
            }, line: { index in index < 6 ? 0 : 1 })
        XCTAssertEqual(result.placed.map(\.mark.word), ["fine"])
        XCTAssertEqual(result.failed, 1)
        XCTAssertEqual(result.hidden, 1)
    }

    func testMissingBoundsIsAFailureNotAHiddenMarkAndAnEmptyListDrawsNothing() {
        let marks = [SpellingMark(location: 3, word: "teh")]
        let result = SpellingIndicator.placements(for: marks, visible: nil, bounds: { _ in nil }, line: { _ in nil })
        XCTAssertTrue(result.placed.isEmpty)
        XCTAssertEqual(result.failed, 1)
        XCTAssertNil(SpellingIndicator.panelFrame(for: []))
    }

    func testClippingKeepsMarksInsideTheVisibleEditorOnly() {
        let visible = CGRect(x: 100, y: 100, width: 400, height: 300)
        XCTAssertEqual(UnderlineGeometry.clipped(CGRect(x: 120, y: 150, width: 40, height: 14), to: visible), CGRect(x: 120, y: 150, width: 40, height: 14))
        XCTAssertEqual(UnderlineGeometry.clipped(CGRect(x: 480, y: 150, width: 40, height: 14), to: visible), CGRect(x: 480, y: 150, width: 20, height: 14))
        XCTAssertNil(UnderlineGeometry.clipped(CGRect(x: 120, y: 395, width: 40, height: 14), to: visible))
        XCTAssertNil(UnderlineGeometry.clipped(CGRect(x: 600, y: 150, width: 40, height: 14), to: visible))
        XCTAssertEqual(UnderlineGeometry.clipped(CGRect(x: 120, y: 150, width: 40, height: 14), to: nil), CGRect(x: 120, y: 150, width: 40, height: 14))
    }
}
