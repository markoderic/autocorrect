import XCTest
@testable import AutoCorrectCore

/// Evidence: evaluation/latest-report.md and simulate-edit-preference.py (rule F).
/// Native en_US often recommends a same-length consonant substitution or a deletion
/// while its own top guesses contain a repair that keeps every typed letter.
final class EditTypePreferenceTests: XCTestCase {
    private func alternatives(_ word: String, _ accepted: String, _ guesses: [String]) -> [String] {
        CorrectionPolicy.letterPreservingAlternatives(for: word, accepted: accepted, guesses: guesses)
    }

    func testInsertionOrTranspositionOutranksConsonantSubstitutionAndDeletion() {
        XCTAssertEqual(alternatives("higer", "tiger", ["tiger", "higher", "hiker", "huger", "hider"]), ["higher"])
        XCTAssertEqual(alternatives("chuch", "couch", ["couch", "church", "chuck", "chichi"]), ["church"])
        XCTAssertEqual(alternatives("caost", "cast", ["cast", "cost", "coast", "canst"]), ["coast"])
        XCTAssertEqual(alternatives("returnd", "returns", ["returns", "return", "returned"]), ["returned"])
        XCTAssertEqual(alternatives("considerd", "consider", ["consider", "considers", "considered"]), ["considered"])
        XCTAssertEqual(alternatives("stong", "song", ["song", "sting", "strong", "stone", "stung"]), ["strong"])
        XCTAssertEqual(alternatives("Higer", "Tiger", ["Tiger", "Higher"]), ["Higher"])
    }

    func testAcceptedRepairKeepsPrecedenceWhenItPreservesLettersOrFixesVowelsOrDoubles() {
        XCTAssertEqual(alternatives("teh", "the", ["the", "tea", "ten"]), [])
        XCTAssertEqual(alternatives("adress", "address", ["dress", "address"]), [])
        XCTAssertEqual(alternatives("carefull", "careful", ["careful", "carefully"]), [])
        XCTAssertEqual(alternatives("andd", "and", ["and", "anded"]), [])
        XCTAssertEqual(alternatives("possable", "posable", ["possible", "passable", "posable"]), [])
        XCTAssertEqual(alternatives("faught", "fought", ["fought", "fraught"]), [])
        XCTAssertEqual(alternatives("analitic", "analytic", ["analytic", "anaclitic"]), [])
        XCTAssertEqual(alternatives("persue", "pursue", ["pursue", "peruse"]), [])
    }

    func testWordInitialInsertionsNeverWinAndSeveralAlternativesAreReturnedUnresolved() {
        XCTAssertEqual(alternatives("tust", "just", ["just", "trust", "test", "otust"]), ["trust"])
        XCTAssertEqual(alternatives("eminated", "geminated", ["geminated", "emanated"]), [])
        XCTAssertEqual(Set(alternatives("agre", "are", ["are", "agree", "age", "acre", "ager"])), ["agree", "ager"])
    }

    func testMultiEditStructuredOrPhraseInputIsOutsideTheRule() {
        XCTAssertEqual(alternatives("capitazed", "capitalized", ["capitalized"]), [])
        XCTAssertEqual(alternatives("teh.txt", "the.txt", ["the.txt"]), [])
        XCTAssertEqual(alternatives("TEH", "THE", ["THE"]), [])
        XCTAssertEqual(alternatives("upto", "unto", ["up to", "unto", "up-to"]), [])
        XCTAssertEqual(alternatives("higer", "tiger", ["tiger", "Higher"]), [])
        XCTAssertEqual(alternatives("higer", "higer", ["higher"]), [])
    }
}
