import XCTest
import AutoCorrectCore
@testable import AutoCorrect

final class EnglishWritingIntegrationTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private var preferences: Preferences!

    override func setUp() {
        suite = "AutoCorrectTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        preferences = Preferences(defaults: defaults)
        preferences.language = "en_US"
    }
    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testEngineAppliesEnglishRulesBeforeDictionaryAcceptance() {
        let engine = CorrectionEngine(preferences: preferences)
        for (source, expected) in ["i": "I", "im": "I'm", "doesnt": "doesn't", "ti": "it", "cant": "can't"] {
            XCTAssertEqual(engine.suggestion(source), expected)
        }
    }

    func testUserDictionaryAlwaysWins() throws {
        let engine = CorrectionEngine(preferences: preferences)
        let dictionary = try UserDictionary.parse(ignoredText: "I\nim\nti\ndoesnt",
                                                   correctionsText: "im -> Imogen\nti -> TI\ndoesnt -> doesnot\ni -> aye")
        preferences.customCorrections = dictionary.corrections
        XCTAssertEqual(engine.suggestion("im"), "Imogen")
        XCTAssertEqual(engine.suggestion("ti"), "TI")
        XCTAssertEqual(engine.suggestion("doesnt"), "doesnot")
        XCTAssertEqual(engine.suggestion("i"), "aye")
        preferences.ignoredWords = dictionary.ignoredWords
        for word in ["im", "ti", "doesnt", "i"] { XCTAssertNil(engine.suggestion(word)) }
    }
    func testSentenceCapitalizationToggleAndSpellingCombination() {
        let engine = CorrectionEngine(preferences: preferences)
        XCTAssertEqual(engine.suggestion(in: "Done. hello "), "Hello")
        XCTAssertEqual(engine.suggestion(in: "Done. a "), "A")
        XCTAssertEqual(engine.suggestion(in: "Done. teh "), "The")
        XCTAssertEqual(engine.suggestion(in: "Done. doesnt "), "Doesn't")
        XCTAssertNil(engine.suggestion(in: "Talk to Dr. smith "))
        preferences.capitalizesAfterPeriod = false
        XCTAssertNil(engine.suggestion(in: "Done. hello "))
        XCTAssertNil(engine.suggestion(in: "Done. a "))
        XCTAssertEqual(engine.suggestion(in: "Done. teh "), "the")
        XCTAssertEqual(engine.suggestion(in: "Done. doesnt "), "doesn't")
    }

    func testCapitalizationPreservesExplicitUserSpellingAndIgnoredWords() {
        let engine = CorrectionEngine(preferences: preferences)
        preferences.customCorrections = ["helo": "hello", "brand": "eBay", "hello": "hello"]
        XCTAssertEqual(engine.suggestion(in: "Done. helo "), "hello")
        XCTAssertEqual(engine.suggestion(in: "Done. brand "), "eBay")
        XCTAssertNil(engine.suggestion(in: "Done. hello "))
        preferences.ignoredWords = ["word", "i", "doesnt"]
        for word in ["word", "i", "doesnt"] {
            XCTAssertNil(engine.suggestion(in: "Done. \(word) "))
        }
    }

}
