import XCTest
@testable import AutoCorrectCore

/// The shared, bounded model of unresolved misspellings in the focused field.
/// Locations are absolute UTF-16 offsets in the field; the set never stores other text.
final class SpellingMarkSetTests: XCTestCase {
    private func mark(_ word: String, at location: Int) -> SpellingMark { SpellingMark(location: location, word: word) }

    func testInsertKeepsMarksSortedDedupesByLocationAndCapsCountNearestTheCaret() {
        var set = SpellingMarkSet()
        set.insert(mark("abit", at: 7), near: 12)
        set.insert(mark("aswell", at: 0), near: 12)
        set.insert(mark("abut", at: 7), near: 12)
        XCTAssertEqual(set.marks, [mark("aswell", at: 0), mark("abut", at: 7)])
        for index in 0..<(SpellingMarkSet.limit + 10) {
            set.insert(mark("teh", at: 100 + index * 4), near: 100 + index * 4)
        }
        XCTAssertEqual(set.marks.count, SpellingMarkSet.limit)
        // The farthest marks from the caret are evicted first.
        XCTAssertFalse(set.marks.contains(mark("aswell", at: 0)))
        XCTAssertTrue(set.marks.contains(mark("teh", at: 100 + (SpellingMarkSet.limit + 9) * 4)))
    }

    func testRemoveByLocationAndByWordIgnoringCase() {
        var set = SpellingMarkSet()
        set.insert(mark("aswell", at: 0), near: 0)
        set.insert(mark("abit", at: 7), near: 0)
        set.insert(mark("Abit", at: 20), near: 0)
        set.remove(at: 0)
        XCTAssertEqual(set.marks.map(\.location), [7, 20])
        set.remove(word: "abit")
        XCTAssertTrue(set.marks.isEmpty)
    }

    func testEditsShiftLaterMarksAndDropOverlappingOnes() {
        var set = SpellingMarkSet()
        set.insert(mark("aswell", at: 0), near: 0)
        set.insert(mark("abit", at: 7), near: 0)
        set.insert(mark("teh", at: 12), near: 0)
        // "abit" (7..<11) replaced by "a bit" (5 units): later marks shift by +1.
        set.applyEdit(at: 7, length: 4, replacementLength: 5)
        XCTAssertEqual(set.marks, [mark("aswell", at: 0), mark("teh", at: 13)])
        // Typing three characters before everything shifts all marks.
        set.applyEdit(at: 0, length: 0, replacementLength: 3)
        XCTAssertEqual(set.marks.map(\.location), [3, 16])
        // Deleting a span that covers a mark removes it; a deletion after a mark leaves it.
        set.applyEdit(at: 2, length: 8, replacementLength: 0)
        XCTAssertEqual(set.marks, [mark("teh", at: 8)])
        set.applyEdit(at: 30, length: 5, replacementLength: 0)
        XCTAssertEqual(set.marks, [mark("teh", at: 8)])
    }

    func testReconcileKeepsOnlyMarksWhoseWordIsStillAtItsLocationInsideTheWindow() {
        var set = SpellingMarkSet()
        set.insert(mark("aswell", at: 100), near: 100)
        set.insert(mark("abit", at: 107), near: 100)
        set.insert(mark("teh", at: 112), near: 100)
        set.insert(mark("far", at: 900), near: 100)
        // The user changed "abit" to "habit" and "teh" was corrected to "the".
        set.reconcile(text: "aswell habit the", windowStart: 100)
        XCTAssertEqual(set.marks, [mark("aswell", at: 100), mark("far", at: 900)])
        // A mark whose word continues past its range is gone (abit → abital).
        set.insert(mark("abit", at: 107), near: 100)
        set.reconcile(text: "aswell abital", windowStart: 100)
        XCTAssertEqual(set.marks.map(\.location), [100, 900])
        // Marks outside the window are never judged by it.
        set.reconcile(text: "zzz", windowStart: 500)
        XCTAssertEqual(set.marks.map(\.location), [100, 900])
    }

    func testReplaceRegionSwapsMarksInsideItOnly() {
        var set = SpellingMarkSet()
        set.insert(mark("early", at: 5), near: 5)
        set.insert(mark("aswell", at: 100), near: 5)
        set.insert(mark("late", at: 900), near: 5)
        set.replace(in: NSRange(location: 90, length: 200), with: [mark("abit", at: 120), mark("teh", at: 200)], near: 150)
        XCTAssertEqual(set.marks, [mark("early", at: 5), mark("abit", at: 120), mark("teh", at: 200), mark("late", at: 900)])
        set.removeAll()
        XCTAssertTrue(set.marks.isEmpty)
    }
}

extension SpellingMarkSetTests {
    func testTruncateDropsMarksAtOrBeyondTheFieldEnd() {
        // Observed live: deleting the end of a document left a mark past the new end with no geometry.
        var set = SpellingMarkSet()
        set.insert(SpellingMark(location: 10, word: "aswell"), near: 0)
        set.insert(SpellingMark(location: 20, word: "abit"), near: 0)
        set.insert(SpellingMark(location: 30, word: "teh"), near: 0)
        set.truncate(to: 24)
        XCTAssertEqual(set.marks.map(\.location), [10, 20])
        set.truncate(to: 20)
        XCTAssertEqual(set.marks.map(\.location), [10])
    }
}
