import Foundation
import XCTest
@testable import AutoCorrectCore

final class CorrectionPolicyTests: XCTestCase {
    private func candidate(_ text: String) -> CorrectionCandidate? {
        CorrectionPolicy.candidate(in: text, caret: text.utf16.count)
    }

    func testCompletedWordAndExactUTF16Range() {
        XCTAssertEqual(candidate("I typed teh "), CorrectionCandidate(original: "teh", range: NSRange(location: 8, length: 3)))
        XCTAssertNil(candidate("I typed teh"))
        XCTAssertNil(candidate("teh  "))
    }

    func testSentencePunctuationAndOpeningBrackets() {
        for text in ["teh,", "teh.", "teh!", "teh?", "(teh) ", "“teh” ", "teh. "] {
            XCTAssertEqual(candidate(text)?.original, "teh", text)
        }
    }

    func testDoesNotCrossSubmitOrFocusBoundaries() {
        for text in ["teh\n", "teh\r", "teh\t", "teh\n ", "teh\t ", " ", "... ", ""] {
            XCTAssertNil(candidate(text), text)
        }
        XCTAssertFalse(CorrectionPolicy.isDelimiter("\n"))
        XCTAssertFalse(CorrectionPolicy.isDelimiter("\t"))
    }

    func testRejectsStructuredTokensAndUnusualCase() {
        for token in ["hello@example.com", "https://exmaple.com", "example.com", "/tmp/teh", "C:\\teh", "@teh", "#teh", "snake_case", "camelCase", "ALLCAPS", "abc123", "two-words", "let=teh", "object.teh", "hello,teh", "teh/", "💻teh"] {
            XCTAssertNil(candidate(token + " "), token)
        }
        XCTAssertEqual(candidate("Teh ")?.original, "Teh")
        XCTAssertEqual(candidate("don't ")?.original, "don't")
    }

    func testUnicodeAndCaretBeforeRemainingText() {
        let text = "🙂 café teh later"
        let caret = ("🙂 café teh " as NSString).length
        XCTAssertEqual(CorrectionPolicy.candidate(in: text, caret: caret),
                       CorrectionCandidate(original: "teh", range: NSRange(location: 8, length: 3)))
        XCTAssertEqual(candidate("🙂 café ")?.range, NSRange(location: 3, length: 4))
        XCTAssertEqual(candidate("cafe\u{301} ")?.range, NSRange(location: 0, length: 5))
        XCTAssertEqual(candidate("日本語 ")?.original, "日本語")
    }

    func testInvalidAndStaleOffsets() {
        for caret in [-1, 0, 5, Int.max] {
            XCTAssertNil(CorrectionPolicy.candidate(in: "teh ", caret: caret))
        }
        XCTAssertNil(CorrectionPolicy.candidate(in: "🙂 ", caret: 1))
        XCTAssertNil(CorrectionPolicy.candidate(in: "", caret: 4))
        XCTAssertNil(candidate(String(repeating: "a", count: 100) + " "))
    }

    func testConservativeCommonCorrections() {
        for pair in [("teh", "the"), ("adn", "and"), ("recieve", "receive"),
                     ("definately", "definitely"), ("helllo", "hello"), ("helo", "hello")] {
            XCTAssertEqual(CorrectionPolicy.confidentReplacement(for: pair.0, suggestion: pair.1), pair.1)
        }
        XCTAssertEqual(CorrectionPolicy.confidentReplacement(for: "Teh", suggestion: "the"), "The")
        XCTAssertEqual(CorrectionPolicy.confidentReplacement(for: "Recieve", suggestion: "receive"), "Receive")
    }

    func testRejectsLowConfidenceAndUnsafeSuggestions() {
        for pair in [("tp", "to"), ("wih", "with"), ("good", "good"), ("teh", "tea"),
                     ("abcde", "world"), ("hellp", "Hello"), ("helo", "hello world"),
                     ("teh", "the!"), ("TEH", "THE"), ("hello", "hello\n"),
                     ("iPhone", "iphone"), ("hello", "h3llo")] {
            XCTAssertNil(CorrectionPolicy.confidentReplacement(for: pair.0, suggestion: pair.1), "\(pair)")
        }
    }

    func testCanonicalEquivalentSpellingIsNotChanged() {
        XCTAssertNil(CorrectionPolicy.confidentReplacement(for: "cafe\u{301}", suggestion: "café"))
    }

    func testExplicitCustomCorrectionsAllowUnusualCase() throws {
        let dictionary = try UserDictionary.parse(ignoredText: "", correctionsText: "chAt -> Chat\nteh -> The\nCAFÉ -> Café")
        let exceptions = Set(dictionary.corrections.keys)
        for word in ["chAt", "TEH", "CAFE\u{301}"] {
            let text = word + " "
            XCTAssertNil(candidate(text))
            let result = CorrectionPolicy.candidate(in: text, caret: text.utf16.count, caseExceptions: exceptions)
            XCTAssertEqual(result?.original, word)
            XCTAssertNotNil(dictionary.corrections[UserDictionary.normalizedKey(result!.original)])
        }
        XCTAssertNil(CorrectionPolicy.candidate(in: "OTHER ", caret: 6, caseExceptions: exceptions))
    }

    func testCaseExceptionsDoNotBypassStructuredTokenOrLengthRules() {
        for word in ["https://EXAMPLE.com", "USER@example.com", "obj.TEH", "snake_CASE", "/tmp/TEH", "TEH123", "A", String(repeating: "A", count: 33)] {
            let text = word + " "
            XCTAssertNil(CorrectionPolicy.candidate(in: text, caret: text.utf16.count,
                                                   caseExceptions: [UserDictionary.normalizedKey(word)]), word)
        }
        XCTAssertNil(CorrectionPolicy.candidate(in: "TEH\n", caret: 4, caseExceptions: ["teh"]))
        XCTAssertNil(CorrectionPolicy.candidate(in: "TEH ", caret: 99, caseExceptions: ["teh"]))
    }

    func testMissingVowelPreferredOverShortSubstitution() {
        XCTAssertEqual(CorrectionPolicy.preferredAutomaticReplacement(for: "ths", systemCorrection: "the",
                                                                      guesses: ["the", "this", "these", "those"]), "this")
        XCTAssertEqual(CorrectionPolicy.preferredAutomaticReplacement(for: "wth", systemCorrection: "why",
                                                                      guesses: ["why", "with", "worth"]), "with")
        XCTAssertEqual(CorrectionPolicy.preferredAutomaticReplacement(for: "frm", systemCorrection: "for",
                                                                      guesses: ["for", "from", "form"]), "from")
        XCTAssertEqual(CorrectionPolicy.preferredAutomaticReplacement(for: "Ths", systemCorrection: "The",
                                                                      guesses: ["The", "This", "These"]), "This")
    }

    func testVowelPreferencePreservesNativeRankingAndEveryTypedLetter() {
        XCTAssertEqual(CorrectionPolicy.preferredAutomaticReplacement(for: "ths", systemCorrection: nil,
                                                                      guesses: ["thus", "this"]), "thus")
        XCTAssertNil(CorrectionPolicy.preferredAutomaticReplacement(for: "ths", systemCorrection: "the",
                                                                    guesses: ["the", "these", "those", "thiss"]))
        XCTAssertNil(CorrectionPolicy.preferredAutomaticReplacement(for: "ths", systemCorrection: nil,
                                                                    guesses: ["THIS", "tHis", "this!", "this word"]))
    }

    func testSystemRecommendationAllowsShortMissingLetterAndFamiliarSwaps() {
        for pair in [("wih", "with"), ("ths", "this"), ("teh", "the"), ("adn", "and"),
                     ("recieve", "receive"), ("definately", "definitely"), ("helllo", "hello"),
                     ("Helo", "hello")] {
            let expected = pair.0.first?.isUppercase == true ? "Hello" : pair.1
            XCTAssertEqual(CorrectionPolicy.preferredAutomaticReplacement(for: pair.0, systemCorrection: pair.1,
                                                                          guesses: []), expected, "\(pair)")
        }
        // Non-vowel insertions in short words need the native automatic recommendation.
        XCTAssertNil(CorrectionPolicy.preferredAutomaticReplacement(for: "wih", systemCorrection: nil, guesses: ["with"]))
        XCTAssertNil(CorrectionPolicy.preferredAutomaticReplacement(for: "helo", systemCorrection: nil, guesses: ["hello"]))
    }

    func testPreferredAutomaticReplacementRetainsSafetyBoundaries() {
        for pair in [("tp", "to"), ("ths", "the"), ("teh", "tea"), ("too", "to"), ("abcde", "world"),
                     ("THS", "this"), ("tHs", "this"), ("ths", "This"), ("hellp", "Hello"),
                     ("teh/", "the"), ("hello", "hello\n"), ("hello", "h3llo"), ("good", "good")] {
            XCTAssertNil(CorrectionPolicy.preferredAutomaticReplacement(for: pair.0, systemCorrection: pair.1,
                                                                        guesses: [pair.1]), "\(pair)")
        }
    }
}
