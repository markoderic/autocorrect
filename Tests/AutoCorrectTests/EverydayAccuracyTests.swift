import XCTest
import AutoCorrectCore
@testable import AutoCorrect

final class EverydayAccuracyTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private var preferences: Preferences!
    private var engine: CorrectionEngine!
    override func setUp() {
        suite = "EverydayAccuracy.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        preferences = Preferences(defaults: defaults)
        preferences.language = "en_US"
        engine = CorrectionEngine(preferences: preferences)
    }
    override func tearDown() {
        engine = nil
        defaults.removePersistentDomain(forName: suite)
    }

    func testReportedExamplesThroughFullTyping() {
        for (source, expected) in ["leets see if this is right ": "let's see if this is right ",
            "are you kiding me? ": "are you kidding me? ", "Leets see ": "Let's see ",
            "okay, leets fix this ": "okay, let's fix this ", "Done! leets see ": "Done! Let's see ",
            "leets see if you are kiding ": "let's see if you are kidding "] {
            XCTAssertEqual(engine.previewText(in: source), expected, source)
        }
    }

    func testMissingAndExtraConsonantsAcrossFamilies() {
        for (source, expected) in ["kiding": "kidding", "runing": "running", "begining": "beginning",
            "geting": "getting", "speling": "spelling", "acident": "accident", "adress": "address",
            "writting": "writing", "comming": "coming", "helllo": "hello", "spining": "spinning",
            "swiming": "swimming", "droped": "dropped", "shoping": "shopping", "ocurred": "occurred"] {
            XCTAssertEqual(engine.suggestion(source), expected, source)
        }
    }

    func testValidWordsNamesAndStructuredTokensArePreserved() {
        for source in ["riding", "hiding", "siting", "planing", "hoping", "pining", "desert", "later",
                       "homebrew", "leets", "kiding.txt", "kiding_thing", "@kiding", "https://kiding.com"] {
            XCTAssertNil(engine.suggestion(in: source + " "), source)
        }
        for text in ["the leets held court ", "she lets go ", "the app lets users work "] {
            XCTAssertNil(engine.previewText(in: text), text)
        }
    }

    func testOverridesAndContextToggleRemainAuthoritative() {
        preferences.ignoredWords = ["kiding", "leets"]
        XCTAssertNil(engine.previewText(in: "leets see "))
        XCTAssertNil(engine.suggestion("kiding"))
        preferences.ignoredWords = []
        preferences.customCorrections = ["kiding": "kiding", "leets": "leets"]
        XCTAssertNil(engine.previewText(in: "leets see "))
        XCTAssertNil(engine.suggestion("kiding"))
        preferences.customCorrections = [:]
        preferences.checksContext = false
        XCTAssertNil(engine.previewText(in: "leets see "))
    }

    func testReportedCorrectionsPreserveFollowingTextAndUndo() throws {
        let text = "are you kiding me? next"
        let range = (text as NSString).range(of: "kiding")
        let plan = try XCTUnwrap(KeyboardReplacementPlan.make(text: text, wordRange: range, replacement: "kidding"))
        XCTAssertEqual(plan.expectedText, "are you kidding me? next")
        let undo = try XCTUnwrap(KeyboardReplacementPlan.make(text: plan.expectedText,
            wordRange: NSRange(location: range.location, length: 7), replacement: "kiding"))
        XCTAssertEqual(undo.expectedText, text)
    }
}
