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
                             ("teh\u{200D} ", "teh"), ("日本語 ", "日本語")] {
            XCTAssertNil(plan(text, word: word, replacement: "hello"), text)
        }
    }

    func testRejectsUnsafeDelimitersAndSuffixes() {
        for suffix in ["", "x", "\t", "\n", "\r", "\0", "\u{7F}", "\u{200B}", "/", "@", " next\nline", " next\tword", " café", " next🙂", String(repeating: " ", count: 97)] {
            XCTAssertNil(plan("teh" + suffix, word: "teh", replacement: "the"), suffix.debugDescription)
        }
        XCTAssertNotNil(plan("teh" + String(repeating: " ", count: 96), word: "teh", replacement: "the"))
    }

    func testEmptyOrUnsafeReplacementNeverCreatesDeletionPlan() {
        for replacement in ["", " ", "the\n", "\tthe", "the\0", "the\u{202E}", String(repeating: "a", count: 121)] {
            XCTAssertNil(plan("teh ", word: "teh", replacement: replacement), replacement.debugDescription)
        }
        XCTAssertNil(plan("teh ", word: "teh", replacement: "teh"))
        XCTAssertNotNil(plan("dont ", word: "dont", replacement: "don't"))
        XCTAssertNotNil(plan("dont ", word: "dont", replacement: "don’t"))
        XCTAssertNotNil(plan("teh ", word: "teh", replacement: String(repeating: "a", count: 120)))
        XCTAssertNotNil(plan("teh ", word: "teh", replacement: "The next word!"))
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
        let maximumWord = String(repeating: "a", count: 120)
        XCTAssertEqual(plan(maximumWord + String(repeating: " ", count: 96), word: maximumWord, replacement: "word")?.deleteCount, 216)
        let tooLong = String(repeating: "a", count: 121)
        XCTAssertNil(plan(tooLong + " ", word: tooLong, replacement: "word"))
        XCTAssertNil(plan(maximumWord + String(repeating: " ", count: 97), word: maximumWord, replacement: "word"))
    }
    func testSentenceCapitalizationAfterOpeningSingleQuote() throws {
        for text in ["Done. 'hello ", "Done. ‘hello "] {
            let candidate = try XCTUnwrap(SentenceCapitalization.candidate(in: text, caret: text.utf16.count))
            let edit = try XCTUnwrap(KeyboardReplacementPlan.make(text: text, wordRange: candidate.range, replacement: "Hello"))
            XCTAssertEqual(edit.expectedText, text.replacingOccurrences(of: "hello", with: "Hello"))
        }
    }

    func testPhraseExpansionAndReversalPreserveTrailingTyping() throws {
        let original = "I said idk what happens next"
        let expansion = try XCTUnwrap(plan(original, word: "idk", replacement: "I don't know"))
        XCTAssertEqual(expansion.expectedText, "I said I don't know what happens next")
        XCTAssertEqual(String(original.dropLast(expansion.deleteCount)) + expansion.insertion, expansion.expectedText)
        let undo = try XCTUnwrap(plan(expansion.expectedText, word: "I don't know", replacement: "idk"))
        XCTAssertEqual(undo.expectedText, original)
        XCTAssertEqual(String(expansion.expectedText.dropLast(undo.deleteCount)) + undo.insertion, original)
        XCTAssertEqual(undo.expectedCaret, original.utf16.count)
    }

    func testContextualPreviousWordCorrectionPreservesExactFollowingText() throws {
        let text = "🙂 I found wierd behavior, in v2."
        let edit = try XCTUnwrap(plan(text, word: "wierd", replacement: "weird"))
        XCTAssertEqual(edit.insertion, "weird behavior, in v2.")
        XCTAssertEqual(edit.expectedText, "🙂 I found weird behavior, in v2.")
        XCTAssertEqual(edit.expectedCaret, edit.expectedText.utf16.count)
    }

    func testPhraseReversalRejectsClippedWordsNonletterEdgesAndUnicodeDeletion() {
        for text in ["prefixI don't know next", "@I don't know next", "obj.I don't know next"] {
            XCTAssertNil(plan(text, word: "I don't know", replacement: "idk"), text)
        }
        for phrase in ["I don't know!", "'I don't know", "I don't kn0w0", "I don't\nknow", "I don't\tknow"] {
            XCTAssertNil(plan(phrase + " next", word: phrase, replacement: "idk"), phrase)
        }
        XCTAssertNil(plan("I don't knowmore ", word: "I don't know", replacement: "idk"))
    }

    func testRecordedExpansionReversalAllowsPunctuationNumbersAndSymbols() throws {
        for phrase in ["I don't know!", "42", "@Marko", "$100", "(thanks)"] {
            let original = "I said idk then continued"
            let expansion = try XCTUnwrap(plan(original, word: "idk", replacement: phrase))
            let range = (expansion.expectedText as NSString).range(of: phrase)
            XCTAssertNil(KeyboardReplacementPlan.make(text: expansion.expectedText, wordRange: range, replacement: "idk"), phrase)
            let undo = try XCTUnwrap(KeyboardReplacementPlan.make(text: expansion.expectedText, wordRange: range,
                                                                replacement: "idk", reversingExpansion: true))
            XCTAssertEqual(undo.expectedText, original, phrase)
            XCTAssertEqual(String(expansion.expectedText.dropLast(undo.deleteCount)) + undo.insertion, original, phrase)
        }
    }

    func testExpansionReversalOptInRetainsDeletionAndBoundarySafeguards() {
        for phrase in ["café!", "hello🙂", "hello\nworld", "hello\tworld"] {
            let text = phrase + " next"
            XCTAssertNil(KeyboardReplacementPlan.make(text: text, wordRange: (text as NSString).range(of: phrase),
                                                      replacement: "idk", reversingExpansion: true), phrase)
        }
        XCTAssertNil(KeyboardReplacementPlan.make(text: "prefix42 next", wordRange: NSRange(location: 6, length: 2),
                                                  replacement: "idk", reversingExpansion: true))
        // A UTF-16 range cannot use reversal to delete only part of a composed character.
        XCTAssertNil(KeyboardReplacementPlan.make(text: "e\u{301} ", wordRange: NSRange(location: 0, length: 1),
                                                  replacement: "idk", reversingExpansion: true))
    }

}

extension KeyboardReplacementPlanTests {
    func testCaretEndPlanReplacesOnlyTheWordBeingTyped() throws {
        let plan = try XCTUnwrap(KeyboardReplacementPlan.make(text: "h", wordRange: NSRange(location: 0, length: 1), replacement: "H", atCaret: true))
        XCTAssertEqual(plan.deleteCount, 1)
        XCTAssertEqual(plan.insertion, "H")
        XCTAssertEqual(plan.expectedText, "H")
        XCTAssertEqual(plan.expectedCaret, 1)
        let quoted = try XCTUnwrap(KeyboardReplacementPlan.make(text: " \"he", wordRange: NSRange(location: 2, length: 2), replacement: "He", atCaret: true))
        XCTAssertEqual(quoted.deleteCount, 2)
        XCTAssertEqual(quoted.expectedText, " \"He")
        XCTAssertEqual(quoted.expectedCaret, 4)
        // Without the explicit caret-end request a word must still be followed by a delimiter,
        // and a caret-end plan never reaches past the caret or into a partial token.
        XCTAssertNil(KeyboardReplacementPlan.make(text: "h", wordRange: NSRange(location: 0, length: 1), replacement: "H"))
        XCTAssertNil(KeyboardReplacementPlan.make(text: "he ", wordRange: NSRange(location: 0, length: 2), replacement: "He", atCaret: true))
        XCTAssertNil(KeyboardReplacementPlan.make(text: "xh", wordRange: NSRange(location: 1, length: 1), replacement: "H", atCaret: true))
        XCTAssertNil(KeyboardReplacementPlan.make(text: "é", wordRange: NSRange(location: 0, length: 1), replacement: "É", atCaret: true))
        XCTAssertNil(KeyboardReplacementPlan.make(text: "h", wordRange: NSRange(location: 0, length: 1), replacement: "h", atCaret: true))
    }
}
