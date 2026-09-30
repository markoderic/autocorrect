import XCTest
@testable import AutoCorrectCore

/// Tokenization for existing-text scans. Detection itself comes from the native checker;
/// these rules decide which tokens may carry a mark at all.
final class SpellingScanTests: XCTestCase {
    private func words(_ text: String, caret: Int? = nil) -> [String] {
        SpellingScan.tokens(in: text, activeCaret: caret).map(\.word)
    }

    func testPlainWordsAreTokensWithExactRanges() {
        let text = "we said aswell abit teh\nnext"
        let tokens = SpellingScan.tokens(in: text, activeCaret: nil)
        XCTAssertEqual(tokens.map(\.word), ["we", "said", "aswell", "abit", "teh", "next"])
        XCTAssertEqual(tokens.map(\.range.location), [0, 3, 8, 15, 20, 24])
        XCTAssertEqual(tokens[2].range.length, 6)
    }

    func testStructuredTokensNamesAndCapsAreNeverEligible() {
        XCTAssertEqual(words("see file.txt and user@host.com or /usr/bin then v2 3rd snake_case dash-word #tag https://x.y"),
                       ["see", "and", "or", "then"])
        XCTAssertEqual(words("NASA camelCase Higgsfield x"), [])
        XCTAssertEqual(words("a " + String(repeating: "z", count: 33) + " ok"), ["ok"])
    }

    func testQuotesBracketsAndPunctuationAreTrimmedNotIncluded() {
        let text = "“speoll” (abit) 'teh', doen'st! dogs' «fin»."
        let tokens = SpellingScan.tokens(in: text, activeCaret: nil)
        XCTAssertEqual(tokens.map(\.word), ["speoll", "abit", "teh", "doen'st", "fin"])
        XCTAssertEqual((text as NSString).substring(with: tokens[0].range), "speoll")
        XCTAssertEqual((text as NSString).substring(with: tokens[3].range), "doen'st")
    }

    func testTheWordBeingTypedAtTheCaretIsExcluded() {
        XCTAssertEqual(words("aswell abi", caret: 10), ["aswell"])
        XCTAssertEqual(words("aswell abi", caret: 3), ["abi"])
        XCTAssertEqual(words("aswell abi ", caret: 11), ["aswell", "abi"])
    }

    func testMarksUseNativeRangesAbsoluteLocationsAndCallerPolicy() {
        let text = "aswell abit Higgsfield next"
        let misspelled = [NSRange(location: 0, length: 6), NSRange(location: 7, length: 4), NSRange(location: 12, length: 10)]
        let marks = SpellingScan.marks(in: text, windowStart: 1000, misspelledRanges: misspelled, activeCaret: nil) { $0 != "abit" }
        XCTAssertEqual(marks, [SpellingMark(location: 1000, word: "aswell")])
        let all = SpellingScan.marks(in: text, windowStart: 0, misspelledRanges: misspelled, activeCaret: nil) { _ in true }
        XCTAssertEqual(all.map(\.word), ["aswell", "abit"])
        // A native range that does not match a whole eligible token is ignored.
        let partial = SpellingScan.marks(in: text, windowStart: 0, misspelledRanges: [NSRange(location: 1, length: 5)], activeCaret: nil) { _ in true }
        XCTAssertTrue(partial.isEmpty)
    }
}
