import XCTest
import AutoCorrectCore
@testable import AutoCorrect

/// Actual NSSpellChecker integration on the test host, not manufactured dictionary ranks.
/// OS dictionaries can vary; this is regression coverage, not a general accuracy score.
final class AccuracyRegressionTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private var preferences: Preferences!
    private var engine: CorrectionEngine!
    override func setUp() {
        suite = "AutoCorrectAccuracyTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        preferences = Preferences(defaults: defaults)
        preferences.language = "en_US"
        engine = CorrectionEngine(preferences: preferences)
    }
    override func tearDown() {
        engine = nil
        defaults.removePersistentDomain(forName: suite)
    }

    func testReportedProductTyposAndCanonicalCase() {
        for (source, expected) in ["iphoen": "iPhone", "iphne": "iPhone", "iphnoe": "iPhone",
                                    "github": "GitHub", "githbu": "GitHub", "githb": "GitHub",
                                    "chatgpt": "ChatGPT", "linkedin": "LinkedIn"] {
            XCTAssertEqual(engine.suggestion(in: "my \(source) "), expected, source)
        }
        XCTAssertEqual(engine.suggestion(in: "Done. iphoen "), "iPhone")
        XCTAssertEqual(engine.suggestion(in: "Done. iphne "), "iPhone")
        for word in ["phone", "siphon", "hub", "GitHub", "iPhone", "IPHONE", "@github", "github.com"] {
            XCTAssertNil(engine.suggestion(in: "my \(word) "), word)
        }
    }

    func testNativeMissingLetterAndScreenshotExamplesAcrossContexts() {
        for source in ["screensht", "screnshot", "screeshot", "screeenshot", "screesnhot"] {
            for prefix in ["", "send a ", "please take a ", "I attached the "] {
                XCTAssertEqual(engine.suggestion(in: prefix + source + " "), "screenshot", prefix + source)
            }
        }
        for word in ["screenshot", "screenshots", "homebrew", "har", "that", "her", "hat"] {
            XCTAssertNil(engine.suggestion(in: word + " "), word)
        }
        for (source, expected) in ["tht": "that", "wih": "with", "ths": "this", "speling": "spelling", "capitazed": "capitalized"] {
            XCTAssertEqual(engine.suggestion(in: source + " "), expected, source)
        }
    }

    func testContextWaitsForMeaningAndThenCorrectsAutomatically() {
        for (source, expected) in [
            "lets improve it ": "let's improve it ", "okay, lets fix this ": "okay, let's fix this ",
            "lets not go ": "let's not go ", "its a screenshot ": "it's a screenshot ",
            "its ready. ": "it's ready. ", "its working now ": "it's working now ",
            "its really good. ": "it's really good. ", "I think its going to work ": "I think it's going to work ",
            "it's screen is broken ": "its screen is broken ", "its a screensht ": "it's a screenshot "
        ] {
            XCTAssertEqual(engine.previewText(in: source), expected, source)
        }
        for text in ["lets ", "its ", "its good ", "its ready ", "its good looks ", "its working parts ",
                     "its screen is broken ", "she lets go ", "the app lets users type ", "she then lets go ",
                     "despite its not working ", "its going rate ", "its ready meals "] {
            XCTAssertNil(engine.previewText(in: text), text)
        }
    }

    func testContextApprovalToggleAndOverrides() {
        preferences.asksBeforeCorrecting = true
        XCTAssertEqual(engine.previewText(in: "lets fix "), "let's fix  (approval required)")
        XCTAssertEqual(engine.previewText(in: "its a "), "it's a  (approval required)")
        preferences.asksBeforeCorrecting = false
        XCTAssertEqual(engine.contextualCandidate(in: "check it's screen ")?.automatic, false)
        preferences.ignoredWords = ["lets", "its", "iphoen"]
        XCTAssertNil(engine.previewText(in: "lets fix "))
        XCTAssertNil(engine.previewText(in: "its a "))
        XCTAssertNil(engine.suggestion("iphoen"))
        preferences.ignoredWords = []
        preferences.customCorrections = ["lets": "lets", "iphoen": "my phone"]
        XCTAssertNil(engine.contextualCandidate(in: "lets fix "))
        XCTAssertEqual(engine.suggestion("iphoen"), "my phone")
        preferences.checksContext = false
        XCTAssertNil(engine.contextualCandidate(in: "its a "))
        preferences.normalizesProductNames = false
        XCTAssertNotEqual(engine.suggestion("githbu"), "GitHub")
    }

    func testFastFollowingTextCanKeepContextAndUndoAnchor() throws {
        // Exercise the exact completed-prefix + shared context policy used by the queue.
        var backlog = CompletedWordBacklog()
        let text = "lets improve next"
        for char in text { backlog.append(String(char)) }
        let prefix = try XCTUnwrap(backlog.boundaries.last?.completedPrefix(in: text))
        let context = try XCTUnwrap(engine.contextualCandidate(in: prefix))
        XCTAssertTrue(context.automatic)
        let plan = try XCTUnwrap(KeyboardReplacementPlan.make(text: text, wordRange: context.range, replacement: context.replacement))
        XCTAssertEqual(plan.expectedText, "let's improve next")
        let range = NSRange(location: 0, length: 5)
        let anchor = try XCTUnwrap(CorrectionUndoAnchor(text: plan.expectedText, windowStart: 0, range: range))
        let continued = plan.expectedText + " word"
        let undoRange = try XCTUnwrap(anchor.matchingRange(in: continued, windowStart: 0))
        let undo = try XCTUnwrap(KeyboardReplacementPlan.make(text: continued, wordRange: undoRange, replacement: "lets"))
        XCTAssertEqual(undo.expectedText, "lets improve next word")
    }

    func testManualRevertAlsoSuppressesContextCorrection() throws {
        let field = UUID()
        let original = "lets improve "
        let contextual = try XCTUnwrap(engine.contextualCandidate(in: original))
        var protection = ManualRewriteProtection()
        protection.recordPostedCorrection(field: field, text: original, windowStart: 0, range: contextual.range,
                                           replacement: contextual.replacement, now: 0)
        protection.noteManualEdit(now: 1)
        XCTAssertTrue(protection.suppresses(field: field,
            candidate: CorrectionCandidate(original: contextual.original, range: contextual.range),
            text: original + "next ", windowStart: 0, now: 2))
    }
}
