import XCTest
@testable import AutoCorrectCore

final class CompoundSpellingPolicyTests: XCTestCase {
    func testPreferredSpacingOfSameLettersPreventsDifferentWordSubstitution() {
        XCTAssertTrue(CompoundSpellingPolicy.prefersUnchangedLetters(for: "homebrew", guesses: ["home brew", "homebred", "home-brew"]))
        XCTAssertTrue(CompoundSpellingPolicy.prefersUnchangedLetters(for: "emailclient", guesses: ["email client", "email clients"]))
        XCTAssertTrue(CompoundSpellingPolicy.prefersUnchangedLetters(for: "Homebrew", guesses: ["Home-brew", "Homebred"]))
    }
    func testUnrelatedOrLowerRankedSpacingDoesNotOverrideNativeCorrection() {
        XCTAssertFalse(CompoundSpellingPolicy.prefersUnchangedLetters(for: "homebrew", guesses: ["homebred", "home brew"]))
        XCTAssertFalse(CompoundSpellingPolicy.prefersUnchangedLetters(for: "capitazed", guesses: ["capitalized", "capita zed"]))
        XCTAssertFalse(CompoundSpellingPolicy.prefersUnchangedLetters(for: "speling", guesses: ["spell ing"]))
        XCTAssertFalse(CompoundSpellingPolicy.prefersUnchangedLetters(for: "alot", guesses: ["a lot"]))
        XCTAssertFalse(CompoundSpellingPolicy.prefersUnchangedLetters(for: "homebrew", guesses: []))
    }
}

extension CompoundSpellingPolicyTests {
    func testProseSplitAmongTopGuessesIsRecognizedWithTheLongestFunctionWordStart() {
        // macOS recommends swell/unto/infant for these, while its ranked guesses show the
        // typed letters are two ordinary words.
        XCTAssertEqual(CompoundSpellingPolicy.prosePhrase(for: "aswell",
            guesses: ["swell", "a swell", "as-well", "a-swell", "as well"]), "as well")
        XCTAssertEqual(CompoundSpellingPolicy.prosePhrase(for: "upto", guesses: ["up to", "unto", "up-to", "updo"]), "up to")
        XCTAssertEqual(CompoundSpellingPolicy.prosePhrase(for: "infront",
            guesses: ["infant", "inferno", "informant", "in-front", "infract"]), "in front")
        XCTAssertEqual(CompoundSpellingPolicy.prosePhrase(for: "abit", guesses: ["bit", "bait", "a-bit", "qbit", "abut"]), "a bit")
        XCTAssertEqual(CompoundSpellingPolicy.prosePhrase(for: "Upto", guesses: ["unto", "Up to"]), "Up to")
    }

    func testUncommonLowerRankedOrOutOfRangeSplitsAreNotProsePhrases() {
        XCTAssertNil(CompoundSpellingPolicy.prosePhrase(for: "capitazed", guesses: ["capitalized", "capita zed"]))
        XCTAssertNil(CompoundSpellingPolicy.prosePhrase(for: "homebrew", guesses: ["homebred", "home brew"]))
        XCTAssertNil(CompoundSpellingPolicy.prosePhrase(for: "upto", guesses: ["unto", "updo", "onto", "up-do", "uptown", "up to"]))
        XCTAssertNil(CompoundSpellingPolicy.prosePhrase(for: "unto", guesses: ["un to"]))
        XCTAssertNil(CompoundSpellingPolicy.prosePhrase(for: "ago", guesses: ["a go"]))
        XCTAssertNil(CompoundSpellingPolicy.prosePhrase(for: "speling", guesses: ["spell ing"]))
    }

    func testInsertionOnlyRepairsKeepTypedLettersButDeletionsAndSubstitutionsDoNot() {
        XCTAssertTrue(CompoundSpellingPolicy.preservesTypedLetters(of: "adress", in: "address"))
        XCTAssertTrue(CompoundSpellingPolicy.preservesTypedLetters(of: "becase", in: "because"))
        XCTAssertTrue(CompoundSpellingPolicy.preservesTypedLetters(of: "Someting", in: "Something"))
        XCTAssertFalse(CompoundSpellingPolicy.preservesTypedLetters(of: "abit", in: "bit"))
        XCTAssertFalse(CompoundSpellingPolicy.preservesTypedLetters(of: "aswell", in: "swell"))
        XCTAssertFalse(CompoundSpellingPolicy.preservesTypedLetters(of: "upto", in: "unto"))
        XCTAssertFalse(CompoundSpellingPolicy.preservesTypedLetters(of: "sofar", in: "solar"))
        XCTAssertFalse(CompoundSpellingPolicy.preservesTypedLetters(of: "infront", in: "infant"))
    }
}
