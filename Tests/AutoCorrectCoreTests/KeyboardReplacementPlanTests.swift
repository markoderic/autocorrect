import Foundation
import XCTest
@testable import AutoCorrectCore

final class KeyboardReplacementPlanTests: XCTestCase {
    private func plan(_ text: String, word: String, replacement: String) -> KeyboardReplacementPlan? {
        KeyboardReplacementPlan.make(text: text, wordRange: (text as NSString).range(of: word), replacement: replacement)
    }

    func testPreservesWordDelimiterAndImmediatelyFollowingTyping() throws {
        let text = "I typed teh "
        let edit = try XCTUnwrap(plan(text, word: "teh", replacement: "the"))
        XCTAssertEqual(edit.deleteCount, 4)
        XCTAssertEqual(edit.insertion, "the ")
        let afterEvents = String(text.dropLast(edit.deleteCount)) + edit.insertion
        XCTAssertEqual(afterEvents, edit.expectedText)
        XCTAssertEqual(afterEvents + "next", "I typed the next")
        XCTAssertEqual(edit.expectedCaret, afterEvents.utf16.count)
    }

    func testPreservesExactPunctuationSuffixAndUnicodePrefix() throws {
        let text = "🙂 café (teh). "
        let edit = try XCTUnwrap(plan(text, word: "teh", replacement: "the"))
        XCTAssertEqual(edit.deleteCount, 6)
        XCTAssertEqual(edit.insertion, "the). ")
        XCTAssertEqual(edit.expectedText, "🙂 café (the). ")
        XCTAssertEqual(edit.expectedCaret, (edit.expectedText as NSString).length)
    }

    func testLengthChangingReplacementAndUnicodeInsertion() throws {
        let edit = try XCTUnwrap(plan("A cafe ", word: "cafe", replacement: "café"))
        XCTAssertEqual(edit.deleteCount, 5)
        XCTAssertEqual(edit.expectedText, "A café ")
        XCTAssertEqual(edit.expectedCaret, 7)
        let shorter = try XCTUnwrap(plan("helllo, ", word: "helllo", replacement: "hello"))
        XCTAssertEqual(shorter.deleteCount, 8)
        XCTAssertEqual(shorter.expectedText, "hello, ")
    }

    func testRejectsUnicodeDeletionIncludingPunctuationAndCombiningMarks() {
        for (text, word) in [("café ", "café"), ("cafe\u{301} ", "cafe\u{301}"),
                             ("don’t ", "don’t"), ("teh” ", "teh"), ("日本語 ", "日本語")] {
            XCTAssertNil(plan(text, word: word, replacement: "hello"), text)
        }
    }

    func testRejectsTrailingTextAndUnsafeDelimiters() {
        for suffix in ["", " next", "x", "\t", "\n", "\r", "\0", "\u{7F}", "\u{00A0}", "/", "@", String(repeating: " ", count: 9)] {
            XCTAssertNil(plan("teh" + suffix, word: "teh", replacement: "the"), suffix.debugDescription)
        }
        XCTAssertNotNil(plan("teh" + String(repeating: " ", count: 8), word: "teh", replacement: "the"))
    }

    func testEmptyOrUnsafeReplacementNeverCreatesDeletionPlan() {
        for replacement in ["", " ", "the next", "the\n", "\tthe", "the\0", "the!", "two-words", "'the", "the’", "a'b'c", String(repeating: "a", count: 65)] {
            XCTAssertNil(plan("teh ", word: "teh", replacement: replacement), replacement.debugDescription)
        }
        XCTAssertNil(plan("teh ", word: "teh", replacement: "teh"))
        XCTAssertNotNil(plan("dont ", word: "dont", replacement: "don't"))
        XCTAssertNotNil(plan("dont ", word: "dont", replacement: "don’t"))
        XCTAssertNotNil(plan("teh ", word: "teh", replacement: String(repeating: "a", count: 64)))
    }

    func testInvalidUTF16RangesFailWithoutOverflow() {
        for range in [NSRange(location: -1, length: 3), NSRange(location: 0, length: -1),
                      NSRange(location: NSNotFound, length: 1), NSRange(location: 1, length: Int.max),
                      NSRange(location: 0, length: 0), NSRange(location: 0, length: 5),
                      NSRange(location: 5, length: 1)] {
            XCTAssertNil(KeyboardReplacementPlan.make(text: "teh ", wordRange: range, replacement: "the"))
        }
        XCTAssertNil(KeyboardReplacementPlan.make(text: "🙂teh ", wordRange: NSRange(location: 1, length: 4), replacement: "the"))
    }

    func testDoesNotDeletePartialWordsOrStructuredTokens() {
        for text in ["notteh ", "obj.teh ", "@teh ", "/teh ", "💻teh "] {
            XCTAssertNil(plan(text, word: "teh", replacement: "the"), text)
        }
        XCTAssertNil(plan("abc123 ", word: "abc123", replacement: "hello"))
        XCTAssertNotNil(plan("don't ", word: "don't", replacement: "doesn't"))
    }

    func testSnapshotAndDeletionBudgets() {
        XCTAssertNotNil(plan(String(repeating: "x", count: 251) + " teh ", word: "teh", replacement: "the"))
        XCTAssertNil(plan(String(repeating: "x", count: 252) + " teh ", word: "teh", replacement: "the"))
        XCTAssertNil(plan(String(repeating: "🙂", count: 126) + " teh ", word: "teh", replacement: "the"))
        let maximumWord = String(repeating: "a", count: 88)
        XCTAssertEqual(plan(maximumWord + String(repeating: " ", count: 8), word: maximumWord, replacement: "word")?.deleteCount, 96)
        let tooLong = String(repeating: "a", count: 89)
        XCTAssertNil(plan(tooLong + String(repeating: " ", count: 8), word: tooLong, replacement: "word"))
    }
}
