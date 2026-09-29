import XCTest
@testable import AutoCorrectCore

/// Hand-labeled regression fixtures, not a held-out accuracy benchmark. Guesses here are
/// deterministic inputs to our acceptance policy, not recorded NSSpellChecker results.
/// Native ordering varies by OS, language, and context; the app must supply real guesses.
final class RankedSpellingCorpusTests: XCTestCase {
    func testLabeledOneAndTwoEditTypoCorpus() {
        let examples: [(label: String, typed: String, expected: String)] = [
            ("single omission", "speling", "spelling"),
            ("double omission user report", "capitazed", "capitalized"),
            ("double omission published example", "inconvient", "inconvenient"),
            ("double consonant omission", "acomodation", "accommodation"),
            ("nonadjacent omissions", "accomodtion", "accommodation"),
            ("vowel omissions", "probblity", "probability"),
            ("two internal omissions", "considrble", "considerable"),
            ("double consonant omissions", "profesionaly", "professionally"),
            ("internal omissions", "corespondnce", "correspondence"),
            ("two missing vowels", "documnttion", "documentation"),
            ("repeated missing vowel", "refrncing", "referencing"),
            ("substitution plus omission", "seperatly", "separately"),
            ("single internal omission", "enviroment", "environment"),
            ("single doubled consonant", "recomendation", "recommendation"),
            ("single vowel omission", "consderation", "consideration"),
            ("vowel substitution", "independant", "independent"),
            ("another vowel substitution", "definately", "definitely"),
            ("trailing internal omission", "simultaneusly", "simultaneously"),
            ("application omission", "applicaton", "application"),
            ("adjacent swap", "recieve", "receive"),
            ("adjacent swap near beginning", "freind", "friend"),
            ("extra consonant", "helllo", "hello"),
            ("extra interior consonant", "commmittee", "committee"),
            ("beginning swap", "becuase", "because"),
            ("vowel omission in uncommon word", "quintesential", "quintessential"),
            ("initial capitalization", "Capitazed", "Capitalized"),
            ("initial capitalization single omission", "Enviroment", "Environment")
        ]
        for example in examples {
            XCTAssertEqual(CorrectionPolicy.preferredAutomaticReplacement(for: example.typed, systemCorrection: nil,
                                                                          guesses: [example.expected]), example.expected, example.label)
        }
    }

    func testLabeledFalsePositiveAndAmbiguityCorpus() {
        let examples: [(label: String, typed: String, guesses: [String])] = [
            ("one edit ambiguity", "commn", ["common", "comma"]),
            ("swap versus substitution", "recieve", ["receive", "relieve"]),
            ("do not search lower ranks", "speling", ["ordinary", "spelling"]),
            ("unchanged top guess", "hello", ["hello", "hallo"]),
            ("two letter token", "tp", ["to"]),
            ("short substitution", "teh", ["tea"]),
            ("short deletion", "too", ["to"]),
            ("four letter ambiguity", "helo", ["hello", "help"]),
            ("two edits too short", "adress", ["addressed"]),
            ("two edit changed first letter", "xapitalzed", ["capitalized"]),
            ("two edit changed last letter", "capitalzeq", ["capitalized"]),
            ("unrelated long word", "abcdefghij", ["capitalized"]),
            ("all capitals", "CAPITAZED", ["capitalized"]),
            ("mixed capitals", "capitAzed", ["capitalized"]),
            ("proper name guess", "capitazed", ["Capitalized"]),
            ("phrase guess", "capitazed", ["capitalized text"]),
            ("punctuation guess", "capitazed", ["capitalized!"]),
            ("url source", "site.capitazed", ["capitalized"]),
            ("email source", "a@capitazed", ["capitalized"]),
            ("numeric source", "capitaz3d", ["capitalized"]),
            ("underscored code", "capit_azed", ["capitalized"]),
            ("newline in guess", "capitazed", ["capitalized\n"]),
            ("caps in guess", "capitazed", ["CAPITALIZED"])
        ]
        for example in examples {
            XCTAssertNil(CorrectionPolicy.preferredAutomaticReplacement(for: example.typed, systemCorrection: nil,
                                                                        guesses: example.guesses), example.label)
        }
    }

    func testRankAndDistanceMarginWithNativeRecommendation() {
        XCTAssertEqual(CorrectionPolicy.preferredAutomaticReplacement(for: "capitazed", systemCorrection: "capitalized",
                                                                      guesses: ["capitalized", "capitalised"]), "capitalized")
        XCTAssertNil(CorrectionPolicy.preferredAutomaticReplacement(for: "capitazed", systemCorrection: "capitalized",
                                                                    guesses: ["unrelated", "another", "different", "capitalized"]))
        // A missing doubled consonant now outranks unrelated single-letter substitutions.
        XCTAssertEqual(CorrectionPolicy.preferredAutomaticReplacement(for: "speling", systemCorrection: nil,
                                                                    guesses: ["spelling", "ordinary", "something", "anything", "spewing"]), "spelling")
        XCTAssertEqual(CorrectionPolicy.preferredAutomaticReplacement(for: "speling", systemCorrection: nil,
                                                                      guesses: ["spelling", "spelling", "spelling"]), "spelling")
        // The native one-edit automatic recommendation retains precedence over guess ranking.
        XCTAssertEqual(CorrectionPolicy.preferredAutomaticReplacement(for: "speling", systemCorrection: "spelling",
                                                                      guesses: ["spewing", "spelling"]), "spelling")
    }

    func testNativeTwoEditRecommendationCanOutrankFartherGuesses() {
        // Native en_US results for an isolated word on macOS: context changes guess order.
        XCTAssertEqual(CorrectionPolicy.preferredAutomaticReplacement(for: "capitazed", systemCorrection: "capitalized",
                                                                      guesses: ["captioned", "capitalized", "capita zed", "capita-zed"]), "capitalized")
        // General two-omission case: native agreement and edit separation, no typo lookup.
        XCTAssertEqual(CorrectionPolicy.preferredAutomaticReplacement(for: "acomodation", systemCorrection: "accommodation",
                                                                      guesses: ["accommodations", "accommodation"]), "accommodation")
        XCTAssertNil(CorrectionPolicy.preferredAutomaticReplacement(for: "capitazed", systemCorrection: nil,
                                                                    guesses: ["captioned", "capitalized"]))
        XCTAssertNil(CorrectionPolicy.preferredAutomaticReplacement(for: "acomodation", systemCorrection: "accommodation",
                                                                    guesses: ["accomodation", "accommodation"]))
    }
}
