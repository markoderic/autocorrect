import XCTest
@testable import AutoCorrect
import AutoCorrectCore

final class JoinedWordsTests: XCTestCase {
    func testReportedApostrophes() {
        let engine = CorrectionEngine(preferences: Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!))
        for word in ["doen'st", "does'nt", "doenst", "doens't"] {
            XCTAssertEqual(engine.suggestion(in: "it \(word) "), "doesn't", word)
        }
    }
}

extension JoinedWordsTests {
    func testJoinedWordsAndOverrides() throws {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = Preferences(defaults: defaults)
        let engine = CorrectionEngine(preferences: prefs)
        for (source, expected) in ["iknow": "I know", "ithink": "I think", "youknow": "you know",
            "thankyou": "thank you", "withyou": "with you", "inthe": "in the", "thisworks": "this works", "myfriend": "my friend", "alot": "a lot"] {
            XCTAssertEqual(engine.suggestion(in: source + " "), expected, source)
        }
        for word in ["homebrew", "everyday", "someone", "software", "therapist", "into", "cannot", "GitHub", "iknow.txt", "you_know", "https://iknow.com"] {
            XCTAssertNil(engine.suggestion(in: word + " "), word)
        }
        prefs.ignoredWords = ["iknow"]
        XCTAssertNil(engine.suggestion("iknow"))
        prefs.ignoredWords = []
        prefs.customCorrections = ["iknow": "I understand"]
        XCTAssertEqual(engine.suggestion("iknow"), "I understand")
        prefs.customCorrections = [:]
        prefs.separatesJoinedWords = false
        XCTAssertNotEqual(engine.suggestion("iknow"), "I know")
        prefs.separatesJoinedWords = true
        prefs.asksBeforeCorrecting = true
        XCTAssertEqual(engine.previewText(in: "iknow "), "I know ")
    }

    func testPleaseNeedsRequestContext() {
        let engine = CorrectionEngine(preferences: Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!))
        XCTAssertEqual(engine.previewText(in: "pleas help "), "please help ")
        XCTAssertEqual(engine.previewText(in: "Pleas fix this "), "Please fix this ")
        for source in ["pleas ", "their pleas were heard ", "the pleas help us understand ", "pleas for help "] {
            XCTAssertNil(engine.previewText(in: source), source)
        }
    }

    func testCurlyApostropheEditAndJoinedWordUndo() throws {
        let engine = CorrectionEngine(preferences: Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!))
        for word in ["doen’st", "does’nt", "doens’t", "doen'st"] {
            let source = "it " + word + " next"
            let range = NSRange(location: 3, length: word.utf16.count)
            let replacement = try XCTUnwrap(engine.suggestion(word))
            XCTAssertEqual(replacement, "doesn't")
            let plan = try XCTUnwrap(KeyboardReplacementPlan.make(text: source, wordRange: range, replacement: replacement))
            XCTAssertEqual(plan.expectedText, "it doesn't next")
        }
        let plan = try XCTUnwrap(KeyboardReplacementPlan.make(text: "iknow next", wordRange: NSRange(location: 0, length: 5), replacement: "I know"))
        XCTAssertEqual(plan.expectedText, "I know next")
        let undo = try XCTUnwrap(KeyboardReplacementPlan.make(text: plan.expectedText, wordRange: NSRange(location: 0, length: 6), replacement: "iknow", reversingExpansion: true))
        XCTAssertEqual(undo.expectedText, "iknow next")
    }

    func testUnderlineGeometryFallbacksAndWrapRejection() {
        let first = CGRect(x: 20, y: 30, width: 8, height: 18)
        let last = CGRect(x: 60, y: 30, width: 8, height: 18)
        let word = first.union(last)
        XCTAssertEqual(UnderlineGeometry.singleLine(word: nil, first: first, last: last), word)
        XCTAssertEqual(UnderlineGeometry.singleLine(word: word, first: nil, last: nil, firstLine: 2, lastLine: 2), word)
        XCTAssertNil(UnderlineGeometry.singleLine(word: word, first: nil, last: nil))
        XCTAssertNil(UnderlineGeometry.singleLine(word: word, first: nil, last: nil, firstLine: 2, lastLine: 3))
        XCTAssertNil(UnderlineGeometry.singleLine(word: word, first: first, last: last.offsetBy(dx: 0, dy: 18)))
        XCTAssertNil(UnderlineGeometry.singleLine(word: .zero, first: nil, last: nil, firstLine: 0, lastLine: 0))
    }
}
