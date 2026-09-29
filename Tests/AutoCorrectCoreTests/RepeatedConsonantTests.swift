import XCTest
@testable import AutoCorrectCore

final class RepeatedConsonantTests: XCTestCase {
    func testMissingDoubleBeatsUnrelatedNativeSubstitution() {
        XCTAssertEqual(CorrectionPolicy.preferredAutomaticReplacement(for: "kiding", systemCorrection: "riding",
            guesses: ["riding", "hiding", "siding", "kidding", "kiting"]), "kidding")
        XCTAssertEqual(CorrectionPolicy.repeatedConsonantReplacement(for: "acomodation", guesses: ["accommodation"]), "accommodation")
        XCTAssertEqual(CorrectionPolicy.repeatedConsonantReplacement(for: "Kiding", guesses: ["kidding"]), "Kidding")
    }
    func testAmbiguityAndUnsupportedChangesAreRejected() {
        XCTAssertNil(CorrectionPolicy.repeatedConsonantReplacement(for: "abacad", guesses: ["abbacad", "abaccad"]))
        for (source, guess) in [("kiding", "riding"), ("kiding", "Kidding"), ("kiding.txt", "kidding"),
                                ("KIDING", "kidding"), ("kiding", "ki ding"), ("boook", "book"), ("hmmmmm", "hm")] {
            XCTAssertNil(CorrectionPolicy.repeatedConsonantReplacement(for: source, guesses: [guess]), source)
        }
    }
    func testRankedFallbackWhenNativeAutomaticRecommendationIsMissing() {
        for (source, target) in [("buisnes", "business"), ("finnaly", "finally"), ("beutifl", "beautiful"), ("necesry", "necessary")] {
            XCTAssertEqual(CorrectionPolicy.preferredAutomaticReplacement(for: source, systemCorrection: nil, guesses: [target]), target)
        }
        XCTAssertEqual(CorrectionPolicy.preferredAutomaticReplacement(for: "probly", systemCorrection: nil, guesses: ["probably", "portly"]), "probably")
        XCTAssertNil(CorrectionPolicy.preferredAutomaticReplacement(for: "finnaly", systemCorrection: nil, guesses: ["finally", "finely"]))
        XCTAssertNil(CorrectionPolicy.preferredAutomaticReplacement(for: "xapitalzed", systemCorrection: nil, guesses: ["capitalized"]))
    }

    func testInvitationVariantsUseContextRatherThanGlobalReplacement() {
        for source in ["leets", "letts", "leats", "ltes", "lets"] {
            XCTAssertEqual(ContextualWritingRules.candidate(in: source + " see ")?.replacement, "let's")
            XCTAssertNil(ContextualWritingRules.candidate(in: "the " + source + " court "))
        }
    }
}
