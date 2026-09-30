import XCTest
@testable import AutoCorrectCore

final class TypingTypographyTests: XCTestCase {
    func testEditorSpaceSubstitutionsKeepExactBoundariesAndEdits() throws {
        for space in [" ", "\u{00A0}", "\u{202F}"] {
            var backlog = CompletedWordBacklog()
            for character in "speoll next" { backlog.append(String(character)) }
            let observed = "speoll" + space + "next"
            let prefix = try XCTUnwrap(backlog.boundaries.first?.completedPrefix(in: observed))
            let candidate = try XCTUnwrap(CorrectionPolicy.candidate(in: prefix, caret: prefix.utf16.count))
            let edit = try XCTUnwrap(KeyboardReplacementPlan.make(text: observed, wordRange: candidate.range, replacement: "spell"))
            XCTAssertEqual(edit.expectedText, "spell" + space + "next")
            XCTAssertEqual(String(observed.dropLast(edit.deleteCount)) + edit.insertion, edit.expectedText)
            let undo = try XCTUnwrap(KeyboardReplacementPlan.make(text: edit.expectedText,
                wordRange: NSRange(location: 0, length: 5), replacement: "speoll"))
            XCTAssertEqual(undo.expectedText, observed)
            XCTAssertNil(CorrectionPolicy.candidate(in: "speoll" + space + space, caret: 8))
        }
    }

    func testQuotedWordsAndContractionsPreserveQuotesDuringReplacement() throws {
        for (open, close) in [("\"", "\""), ("“", "”"), ("‘", "’"), ("'", "'"), ("«", "»")] {
            for word in ["speoll", "doen'st", "doen’st"] {
                let completed = open + word + close + " "
                let candidate = try XCTUnwrap(CorrectionPolicy.candidate(in: completed, caret: completed.utf16.count), completed)
                XCTAssertEqual(candidate.original, word)
                let observed = completed + "next"
                let replacement = word == "speoll" ? "spell" : "doesn't"
                let edit = try XCTUnwrap(KeyboardReplacementPlan.make(text: observed, wordRange: candidate.range, replacement: replacement))
                XCTAssertEqual(edit.expectedText, open + replacement + close + " next")
                XCTAssertEqual(String(observed.dropLast(edit.deleteCount)) + edit.insertion, edit.expectedText)
            }
        }
        for text in ["dogs’ ", "dogs' ", "don't' ", "'a@teh.com' ", "‘teh.txt’ "] {
            XCTAssertNil(CorrectionPolicy.candidate(in: text, caret: text.utf16.count), text)
        }
    }

    func testQuoteSubstitutionAndSmartQuoteKeystrokesKeepTheQueue() throws {
        var backlog = CompletedWordBacklog()
        for character in "\"speoll\"" { backlog.append(String(character)) }
        XCTAssertEqual(backlog.boundaries.last?.completedPrefix(in: "“speoll”"), "“speoll”")
        backlog.reset()
        for character in "“speoll” next" { backlog.append(String(character)) }
        XCTAssertEqual(backlog.boundaries.first?.completedPrefix(in: "“speoll” next"), "“speoll”")
    }

    func testUnsafeUnicodeAndControlsStillCancelPendingWork() {
        for input in ["🙂", "e\u{301}", "é", "\u{200D}", "\u{202E}", "\u{200B}", "\n", "\t", "\u{7F}", "ab"] {
            var backlog = CompletedWordBacklog()
            for character in "teh " { backlog.append(String(character)) }
            backlog.append(input)
            XCTAssertTrue(backlog.boundaries.isEmpty, input.debugDescription)
            XCTAssertFalse(TypingTypography.isSupportedKeystroke(input))
        }
    }
}

extension TypingTypographyTests {
    func testHostSmartPunctuationSubstitutionIsEquivalentForVerification() {
        // Rich hosts turn an inserted straight apostrophe or quote into a curly one and
        // an ordinary space into a nonbreaking one. Verification must accept those.
        XCTAssertTrue(TypingTypography.equivalent(observed: "it don’t next", typed: "it don't next"))
        XCTAssertTrue(TypingTypography.equivalent(observed: "“spell” next", typed: "\"spell\" next"))
        XCTAssertTrue(TypingTypography.equivalent(observed: "«spell» next", typed: "\"spell\" next"))
        XCTAssertTrue(TypingTypography.equivalent(observed: "spell\u{00A0}next", typed: "spell next"))
        XCTAssertTrue(TypingTypography.equivalent(observed: "‘spell’ next", typed: "'spell' next"))
        XCTAssertTrue(TypingTypography.equivalent(observed: "same", typed: "same"))
        // Letters, case, length and unrelated punctuation must still match exactly.
        XCTAssertFalse(TypingTypography.equivalent(observed: "it dont next", typed: "it don't next"))
        XCTAssertFalse(TypingTypography.equivalent(observed: "it Don't next", typed: "it don't next"))
        XCTAssertFalse(TypingTypography.equivalent(observed: "it don't nex", typed: "it don't next"))
        XCTAssertFalse(TypingTypography.equivalent(observed: "it don't next ", typed: "it don't next"))
        XCTAssertFalse(TypingTypography.equivalent(observed: "it don—t next", typed: "it don't next"))
        XCTAssertFalse(TypingTypography.equivalent(observed: "it don't next", typed: "it don’t next"))
    }
}
