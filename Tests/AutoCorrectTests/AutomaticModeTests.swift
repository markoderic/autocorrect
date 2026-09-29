import XCTest
import AppKit
import AutoCorrectCore
@testable import AutoCorrect

final class AutomaticModeTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private var preferences: Preferences!
    private var engine: CorrectionEngine!

    override func setUp() {
        suite = UUID().uuidString
        defaults = UserDefaults(suiteName: suite)!
        preferences = Preferences(defaults: defaults)
        preferences.showsSpellingIndicators = false
        engine = CorrectionEngine(preferences: preferences)
    }
    override func tearDown() {
        engine = nil
        defaults.removePersistentDomain(forName: suite)
    }

    func testSentenceEndingsAcrossFullTypingPreviewAndToggle() {
        for (source, target) in ["Really? hello ": "Really? Hello ", "Great! hello ": "Great! Hello ",
            "Really?! hello ": "Really?! Hello ", "Great! teh ": "Great! The ",
            "Really? a ": "Really? A ", "Great! myfriend ": "Great! My friend ",
            "Really? iphone ": "Really? iPhone ", "Great! dont ": "Great! Don't "] {
            XCTAssertEqual(engine.previewText(in: source), target, source)
        }
        preferences.capitalizesAfterPeriod = false
        XCTAssertNil(engine.previewText(in: "Really? hello "))
        XCTAssertNil(engine.previewText(in: "Great! hello "))
        preferences.capitalizesAfterPeriod = true
        preferences.ignoredWords = ["hello"]
        XCTAssertNil(engine.previewText(in: "Great! hello "))
        preferences.customCorrections = ["teh": "the"]
        XCTAssertEqual(engine.suggestion(in: "Really? teh "), "the")
    }

    func testMoreNativeCorrectionsApplyAutomatically() {
        for (word, replacement) in ["finnaly": "finally", "probly": "probably", "beutifl": "beautiful",
                                    "tomoroww": "tomorrow", "buisnes": "business", "necesry": "necessary"] {
            let checker = NSSpellChecker.shared
            let range = NSRange(location: 0, length: word.utf16.count)
            let native = checker.correction(forWordRange: range, in: word, language: "en_US", inSpellDocumentWithTag: 0)
            let guesses = checker.guesses(forWordRange: range, in: word, language: "en_US", inSpellDocumentWithTag: 0)
            XCTAssertEqual(engine.suggestion(word), replacement, "\(word); native=\(native ?? "nil"); guesses=\(guesses ?? [])")
        }
        XCTAssertNil(engine.suggestion("homebrew"))
        XCTAssertNil(engine.suggestion("har"))
    }

    func testUncertainSuggestionDoesNotCreateApprovalInAutomaticMode() {
        // No host-app access or keyboard events: exercise the actual menu-state path.
        let snapshot = AccessibilityText.Snapshot(element: AXUIElementCreateApplication(getpid()), pid: getpid(),
            text: "uncertain ", windowStart: 0, caret: 10, physicalKeyCount: 0)
        let proposal = CorrectionEngine.Proposal(snapshot: snapshot, range: NSRange(location: 0, length: 9),
            original: "uncertain", replacement: "alternative", created: Date())
        engine.showSuggestion(proposal)
        XCTAssertNil(engine.pending)
        XCTAssertEqual(engine.flaggedWord, "uncertain")
        XCTAssertFalse(engine.status.contains("Suggestion ready"))
        preferences.asksBeforeCorrecting = true
        engine.showSuggestion(proposal)
        XCTAssertEqual(engine.pending?.replacement, "alternative")
        preferences.asksBeforeCorrecting = false
        engine.showSuggestion(proposal)
        XCTAssertNil(engine.pending)
        XCTAssertNil(engine.previewText(in: "check it's screen "))
    }

    func testBroaderFallbackStillRejectsAmbiguousOrUnsupportedGuesses() {
        XCTAssertNil(CorrectionPolicy.preferredAutomaticReplacement(for: "abcde", systemCorrection: "abxyz", guesses: ["abxyz"]))
        XCTAssertNil(CorrectionPolicy.preferredAutomaticReplacement(for: "finnaly", systemCorrection: "finally", guesses: ["finely", "finally"]))
        XCTAssertNil(CorrectionPolicy.preferredAutomaticReplacement(for: "buisnes", systemCorrection: "Business", guesses: ["Business"]))
    }
}
