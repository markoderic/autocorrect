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
