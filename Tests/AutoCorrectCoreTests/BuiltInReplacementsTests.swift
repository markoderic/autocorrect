import XCTest
@testable import AutoCorrectCore

final class BuiltInReplacementsTests: XCTestCase {
    func testEnglishExpansionExamples() {
        let examples = [("idk", "I don't know"), ("omw", "On my way"), ("brb", "Be right back"),
                        ("imo", "in my opinion"), ("fyi", "for your information")]
        for (input, expected) in examples {
            XCTAssertEqual(BuiltInReplacements.replacement(for: input, language: "en-GB", includeExpansions: true, includeCasing: false), expected)
        }
    }

    func testIndependentTogglesAndLanguageGate() {
        XCTAssertNil(BuiltInReplacements.replacement(for: "idk", language: "en_US", includeExpansions: false, includeCasing: true))
        XCTAssertNil(BuiltInReplacements.replacement(for: "iphone", language: "en_US", includeExpansions: true, includeCasing: false))
        XCTAssertNil(BuiltInReplacements.replacement(for: "idk", language: "fr_FR", includeExpansions: true, includeCasing: true))
        XCTAssertEqual(BuiltInReplacements.replacement(for: "iphone", language: "fr_FR", includeExpansions: false, includeCasing: true), "iPhone")
        XCTAssertEqual(BuiltInReplacements.replacement(for: "ui", language: "en_US", includeExpansions: false, includeCasing: true), "UI")
        XCTAssertEqual(BuiltInReplacements.replacement(for: "api", language: "en_US", includeExpansions: false, includeCasing: true), "API")
        XCTAssertEqual(BuiltInReplacements.replacement(for: "ux", language: "en_US", includeExpansions: false, includeCasing: true), "UX")
        XCTAssertEqual(BuiltInReplacements.replacement(for: "macos", language: "en_US", includeExpansions: false, includeCasing: true), "macOS")
    }

    func testDeliberateCaseAndNonWholeWordsArePreserved() {
        for word in ["IDK", "Idk", "iDk", "iPhone", "IPHONE", "Iphone", "UI", "API", "macOS", "idk!", "@idk", "idk@example.com", "idk/", "hello", "idk now"] {
            XCTAssertNil(BuiltInReplacements.replacement(for: word, language: "en_US", includeExpansions: true, includeCasing: true), word)
        }
    }

    func testOutputsAreCompatibleWithCustomPhraseValidation() {
        for output in Array(BuiltInReplacements.expansions.values) + Array(BuiltInReplacements.casing.values) {
            XCTAssertTrue(UserDictionary.isValidReplacement(output), output)
        }
    }
}
