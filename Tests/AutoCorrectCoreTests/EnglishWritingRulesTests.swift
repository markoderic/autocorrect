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

extension EnglishWritingRulesTests {
    func testAdditionalUnambiguousContractionsAreDeterministic() {
        // Native automatic recommendations for several of these are nil on some macOS
        // versions, and a closer competitor (shed, aunt, till) blocks the ranked fallback.
        for (source, expected) in ["shes": "she's", "hes": "he's", "itll": "it'll", "itd": "it'd",
            "youd": "you'd", "theyd": "they'd", "thatll": "that'll", "therell": "there'll", "whatll": "what'll",
            "whod": "who'd", "wheres": "where's", "whens": "when's",
            "wouldve": "would've", "couldve": "could've", "shouldve": "should've",
            "mightve": "might've", "mustve": "must've", "aint": "ain't", "yall": "y'all", "oclock": "o'clock",
            "Shes": "She's", "Aint": "Ain't", "Wouldve": "Would've"] {
            XCTAssertEqual(EnglishWritingRules.replacement(for: source, language: "en_US"), expected, source)
        }
    }

    func testAmbiguousShortFormsAndRealWordsStayOutOfTheContractionTable() {
        // hed/wed/well/shell/hell/ill/id can be other words or typos of other words;
        // hows/whys appear in "the hows and whys"; wholl/whove are more often other typos.
        for word in ["hed", "wed", "well", "shell", "hell", "ill", "id", "hows", "whys", "wholl", "whove",
                     "SHES", "sheS", "she's", "ain't", "y'all"] {
            XCTAssertNil(EnglishWritingRules.replacement(for: word, language: "en_US"), word)
        }
    }

    func testDamagedFormsOfNewContractionsRepairWithNativeAgreementOrPreservedLetters() {
        XCTAssertEqual(EnglishWritingRules.typoReplacement(for: "shoudlve", language: "en_US",
            systemCorrection: nil, guesses: []), "should've")
        XCTAssertEqual(EnglishWritingRules.typoReplacement(for: "wouldv", language: "en_US",
            systemCorrection: "would've", guesses: []), "would've")
        XCTAssertNil(EnglishWritingRules.typoReplacement(for: "wouldv", language: "en_US",
            systemCorrection: nil, guesses: ["would", "wouldn't"]))
    }
}

extension EnglishWritingRulesTests {
    func testDamagedContractionRepairNeedsTheNativeRecommendationUnlessLettersArePreserved() {
        // Evaluation false corrections: heros → here's, whants → what's, wheras → where's.
        // A lower-ranked guess is not agreement; only the automatic recommendation (or the
        // top guess when that recommendation is absent) may license a non-transposition.
        XCTAssertNil(EnglishWritingRules.typoReplacement(for: "heros", language: "en_US",
            systemCorrection: "heres", guesses: ["here's", "heres", "hers", "hero", "heroes"]))
        XCTAssertNil(EnglishWritingRules.typoReplacement(for: "whants", language: "en_US",
            systemCorrection: "whats", guesses: ["what's", "whats", "wants"]))
        XCTAssertNil(EnglishWritingRules.typoReplacement(for: "wheras", language: "en_US",
            systemCorrection: "wheres", guesses: ["wheres", "where's", "whereas"]))
        XCTAssertEqual(EnglishWritingRules.typoReplacement(for: "doesn", language: "en_US",
            systemCorrection: "doesn't", guesses: ["doesn't"]), "doesn't")
        XCTAssertEqual(EnglishWritingRules.typoReplacement(for: "doesn", language: "en_US",
            systemCorrection: nil, guesses: ["doesn't", "does"]), "doesn't")
        XCTAssertNil(EnglishWritingRules.typoReplacement(for: "doesn", language: "en_US",
            systemCorrection: nil, guesses: ["does", "doesn't"]))
        XCTAssertEqual(EnglishWritingRules.typoReplacement(for: "doenst", language: "en_US",
            systemCorrection: nil, guesses: []), "doesn't")
    }
}
