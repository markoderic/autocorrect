import XCTest
@testable import AutoCorrectCore

final class JoinedWordPolicyTests: XCTestCase {
    private let isWord: (String) -> Bool = { ["every", "time", "a", "lot", "each", "other", "up", "work", "in", "front", "never", "mind"].contains($0) }

    func testNativeSplitRecommendationWithCommonFirstWordIsAccepted() {
        XCTAssertEqual(JoinedWordPolicy.replacement(for: "everytime", language: "en_US", systemCorrection: "every time",
            guesses: ["every time", "overtime", "every-time"], isWord: isWord), "every time")
        XCTAssertEqual(JoinedWordPolicy.replacement(for: "eachother", language: "en_US", systemCorrection: "each other",
            guesses: ["each other", "each-other"], isWord: isWord), "each other")
        XCTAssertEqual(JoinedWordPolicy.replacement(for: "nevermind", language: "en_US", systemCorrection: "never mind",
            guesses: ["never mind", "never-mind"], isWord: isWord), "never mind")
        XCTAssertEqual(JoinedWordPolicy.replacement(for: "Everytime", language: "en_US", systemCorrection: "Every time",
            guesses: ["Every time"], isWord: isWord), "Every time")
    }

    func testMissingNativeRecommendationUsesTopRankedSplitOnly() {
        // macOS 14 can omit the automatic recommendation while ranking the split first.
        XCTAssertEqual(JoinedWordPolicy.replacement(for: "alot", language: "en_US", systemCorrection: nil,
            guesses: ["a lot", "slot", "lot"], isWord: isWord), "a lot")
        XCTAssertNil(JoinedWordPolicy.replacement(for: "alot", language: "en_US", systemCorrection: nil,
            guesses: ["slot", "a lot"], isWord: isWord))
    }

    func testDifferentWordRecommendationOrUnknownFirstPartNeverSplits() {
        // A single-word recommendation (unto, swell, infant) is not a split; the policy
        // must not invent one from a lower-ranked guess.
        XCTAssertNil(JoinedWordPolicy.replacement(for: "upto", language: "en_US", systemCorrection: "unto",
            guesses: ["up to", "unto"], isWord: isWord))
        XCTAssertNil(JoinedWordPolicy.replacement(for: "infront", language: "en_US", systemCorrection: "infant",
            guesses: ["infant", "in-front"], isWord: isWord))
        // Names and compounds whose first part is not a common prose word stay whole.
        XCTAssertNil(JoinedWordPolicy.replacement(for: "instacart", language: "en_US", systemCorrection: "insta cart",
            guesses: ["insta cart"], isWord: { _ in true }))
        XCTAssertNil(JoinedWordPolicy.replacement(for: "homebrew", language: "en_US", systemCorrection: "home brew",
            guesses: ["home brew"], isWord: { _ in true }))
    }
}
