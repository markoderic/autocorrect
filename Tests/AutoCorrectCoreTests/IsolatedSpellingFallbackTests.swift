import XCTest
@testable import AutoCorrectCore

final class IsolatedSpellingFallbackTests: XCTestCase {
    func testMissingContextRecommendationCanUseCorroboratedWordCorrection() {
        for (word, target) in ["recieve": "receive", "wierd": "weird", "chek": "check", "frend": "friend",
                              "speoll": "spell", "agan": "again", "teh": "the"] {
            XCTAssertEqual(CorrectionPolicy.isolatedFallback(for: word, contextualCorrection: nil,
                contextualGuesses: [target], isolatedCorrection: target), target)
        }
        XCTAssertEqual(CorrectionPolicy.isolatedFallback(for: "teh", contextualCorrection: nil,
            contextualGuesses: ["The", "tea"], isolatedCorrection: "the"), "the")
        XCTAssertEqual(CorrectionPolicy.isolatedFallback(for: "frend", contextualCorrection: nil,
            contextualGuesses: ["Fred", "friend", "trend"], isolatedCorrection: "friend"), "friend")
        XCTAssertEqual(CorrectionPolicy.isolatedFallback(for: "capitazed", contextualCorrection: nil,
            contextualGuesses: ["captioned", "capitalized"], isolatedCorrection: "capitalized"), "capitalized")
    }

    func testDisagreementUnsupportedRanksAndUnsafeEditsStillRefuse() {
        XCTAssertNil(CorrectionPolicy.isolatedFallback(for: "recieve", contextualCorrection: "relieve",
            contextualGuesses: ["relieve", "receive"], isolatedCorrection: "receive"))
        XCTAssertNil(CorrectionPolicy.isolatedFallback(for: "recieve", contextualCorrection: nil,
            contextualGuesses: ["relieve"], isolatedCorrection: "receive"))
        XCTAssertNil(CorrectionPolicy.isolatedFallback(for: "recieve", contextualCorrection: nil,
            contextualGuesses: ["relieve", "recipe", "recede", "receive"], isolatedCorrection: "receive"))
        XCTAssertNil(CorrectionPolicy.isolatedFallback(for: "recieve", contextualCorrection: nil,
            contextualGuesses: ["recieve", "receive"], isolatedCorrection: "receive"))
        for (word, target) in ["har": "that", "tp": "to", "TEH": "the", "thier": "Their",
                              "teh.txt": "the", "abcd": "capitalized", "teh": "the\n"] {
            XCTAssertNil(CorrectionPolicy.isolatedFallback(for: word, contextualCorrection: nil,
                contextualGuesses: [target], isolatedCorrection: target))
        }
        XCTAssertNil(CorrectionPolicy.isolatedFallback(for: "teh", contextualCorrection: nil,
            contextualGuesses: ["the"], isolatedCorrection: nil))
    }
}
