import XCTest
@testable import AutoCorrectCore

final class EnglishWritingRulesTests: XCTestCase {
    func testPronounAndCapitalizedContractions() {
        for (source, expected) in ["i": "I", "im": "I'm", "Im": "I'm", "ive": "I've",
                                   "i'm": "I'm", "i’ve": "I’ve", "i'll": "I'll", "i’d": "I’d"] {
            XCTAssertEqual(EnglishWritingRules.replacement(for: source, language: "en_US"), expected)
        }
    }

    func testCommonMissingApostrophesAndShortTransposition() {
        for (source, expected) in ["doesnt": "doesn't", "Doesnt": "Doesn't", "dont": "don't",
            "didnt": "didn't", "isnt": "isn't", "arent": "aren't", "wasnt": "wasn't", "werent": "weren't",
            "hasnt": "hasn't", "havent": "haven't", "hadnt": "hadn't", "cant": "can't", "couldnt": "couldn't",
            "wont": "won't", "wouldnt": "wouldn't", "shouldnt": "shouldn't", "mustnt": "mustn't", "neednt": "needn't",
            "youre": "you're", "youve": "you've", "youll": "you'll", "theyre": "they're", "theyve": "they've",
            "theyll": "they'll", "weve": "we've", "thats": "that's", "theres": "there's", "whats": "what's",
            "whos": "who's", "heres": "here's", "ti": "it", "Ti": "It"] {
            XCTAssertEqual(EnglishWritingRules.replacement(for: source, language: "en_US"), expected, source)
        }
    }

    func testLanguageCaseAndAmbiguousWordsRemainUntouched() {
        for language in ["de_DE", "fr", "es-ES", "english", ""] {
            XCTAssertNil(EnglishWritingRules.replacement(for: "im", language: language))
        }
        XCTAssertEqual(EnglishWritingRules.replacement(for: "im", language: "en-GB"), "I'm")
        for word in ["I", "I'm", "I’m", "IM", "TI", "DOESNT", "iPhone", "ill", "well", "were", "its", "id", "wed", "hell", "shell", "shed", "lets", "word"] {
            XCTAssertNil(EnglishWritingRules.replacement(for: word, language: "en_US"), word)
        }
    }

    func testCandidateToEditPlanPreservesNextWord() throws {
        for (source, replacement) in ["i": "I", "im": "I'm", "doesnt": "doesn't", "ti": "it"] {
            let text = "🙂 said \(source) "
            let candidate = try XCTUnwrap(CorrectionPolicy.candidate(in: text, caret: text.utf16.count))
            XCTAssertEqual(candidate.original, source)
            let correction = try XCTUnwrap(EnglishWritingRules.replacement(for: candidate.original, language: "en_US"))
            let plan = try XCTUnwrap(KeyboardReplacementPlan.make(text: text, wordRange: candidate.range, replacement: correction))
            XCTAssertEqual(String(text.dropLast(plan.deleteCount)) + plan.insertion + "next", "🙂 said \(replacement) next")
        }
    }

    func testPronounCandidateRespectsTokenBoundaries() {
        for text in ["i ", "(i). ", "say i, "] {
            XCTAssertEqual(CorrectionPolicy.candidate(in: text, caret: text.utf16.count)?.original, "i")
        }
        for text in ["@i ", "obj.i ", "/i ", "hi ", "i\n", "i\t"] {
            XCTAssertNotEqual(CorrectionPolicy.candidate(in: text, caret: text.utf16.count)?.original, "i")
        }
    }
}
