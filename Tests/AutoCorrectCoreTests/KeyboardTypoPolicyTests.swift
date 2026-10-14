import XCTest
@testable import AutoCorrectCore

final class KeyboardTypoPolicyTests: XCTestCase {
    func testNearbyKeysAndBoundedCost() {
        XCTAssertTrue(KeyboardTypoPolicy.neighbors("d", "s"))
        XCTAssertTrue(KeyboardTypoPolicy.neighbors("c", "x"))
        XCTAssertFalse(KeyboardTypoPolicy.neighbors("q", "p"))
        XCTAssertFalse(KeyboardTypoPolicy.neighbors("é", "e"))
        XCTAssertLessThan(KeyboardTypoPolicy.cost("mistaked", "mistakes", proximity: true), KeyboardTypoPolicy.cost("mistaked", "mistake", proximity: true))
        XCTAssertEqual(KeyboardTypoPolicy.cost(String(repeating: "a", count: 40), "a", proximity: true), .infinity)
    }
    func testNativeAgreementAndSeparationRequired() {
        XCTAssertEqual(KeyboardTypoPolicy.replacement(for: "ecaple", native: "example", guesses: ["equal", "equable"], proximity: true), "example")
        XCTAssertNil(KeyboardTypoPolicy.replacement(for: "mistaked", native: "mistakes", guesses: ["mistakes", "mistake", "mistaken"], proximity: true))
        XCTAssertEqual(KeyboardTypoPolicy.pluralReplacement(for: "mistaked", native: "mistakes", guesses: ["mistakes", "mistake", "mistaker"], prefix: "several ", proximity: true), "mistakes")
        XCTAssertNil(KeyboardTypoPolicy.pluralReplacement(for: "mistaked", native: "mistakes", guesses: ["mistakes", "mistake"], prefix: "he ", proximity: true))
        for (word, native, other) in [("amoung", "amount", "among"), ("reacing", "reading", "reaching"), ("gardai", "garcia", "guard"), ("Palistian", "Pakistan", "Palestine")] {
            XCTAssertNil(KeyboardTypoPolicy.replacement(for: word, native: native, guesses: [native, other], proximity: true))
        }
        XCTAssertNil(KeyboardTypoPolicy.replacement(for: "ecaple", native: "example", guesses: ["equal"], proximity: false))
        XCTAssertNil(KeyboardTypoPolicy.replacement(for: "ecaple", native: nil, guesses: ["example"], proximity: true))
        XCTAssertNil(KeyboardTypoPolicy.replacement(for: "ECAPLE", native: "example", guesses: ["equal"], proximity: true))
        XCTAssertNil(KeyboardTypoPolicy.replacement(for: "higer", native: "tiger", guesses: ["tiger", "higher"], proximity: true))
        XCTAssertNil(KeyboardTypoPolicy.replacement(for: "test.name", native: "testname", guesses: ["testname"], proximity: true))
    }
    func testContextualOmissionsAndValidWordControls() {
        for (text, result) in [("wit that ", "with"), ("I agree wit this ", "with"), ("work wit them ", "with"),
                               ("she wats to ", "wants"), ("the user wats a ", "wants"),
                               ("the men bar ", "menu"), ("open the file men ", "menu"), ("os ", "so")] {
            XCTAssertEqual(ContextualOmissionRules.candidate(in: text)?.replacement, result, text)
        }
        for text in ["wit ", "his wit ", "a wit that ", "wit and wisdom ", "two men ", "men bar the door ",
                     "OS ", "macOS ", "import os ", "from os import ", "os.path ", "/os ",
                     "she wats", "wats to ", "the men work ", "the men  bar ", "their wits "] {
            XCTAssertNil(ContextualOmissionRules.candidate(in: text), text)
        }
        XCTAssertNil(ContextualOmissionRules.candidate(in: String(repeating: "x", count: 257) + " wit that "))
    }
}
