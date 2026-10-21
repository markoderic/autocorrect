import XCTest
import AppKit
import AutoCorrectCore
@testable import AutoCorrect

final class ReportedTypingTests: XCTestCase {
    func testCombinedRunOnSentenceFromPhysicalReport() {
        let name = "CombinedTyping.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = Preferences(defaults: defaults)
        let engine = CorrectionEngine(preferences: preferences)
        engine.suppressesRendering = true
        let text = "It's a problem lets fix this it woks it doest work and helo "
        XCTAssertEqual(engine.previewText(in: text), "It's a problem let's fix this it works it doesn't work and hello ")
    }

    func testReportedWordsAndPhrases() {
        let name = "ReportedTyping.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = Preferences(defaults: defaults)
        preferences.capitalizesAfterPeriod = false
        let engine = CorrectionEngine(preferences: preferences)
        engine.suppressesRendering = true
        XCTAssertEqual(engine.suggestion("helo"), "hello")
        XCTAssertEqual(engine.previewText(in: "its a problem "), "it's a problem ")
        XCTAssertEqual(engine.previewText(in: "lets fix this "), "let's fix this ")
        for (text, expected) in [("it woks ", "it works "), ("the app woks ", "the app works "),
                                 ("this wrks ", "this works "), ("the keyboard woks ", "the keyboard works "),
                                 ("it doest work ", "it doesn't work "), ("the app doest open ", "the app doesn't open "),
                                 ("its working now ", "it's working now "), ("lets also fix this ", "let's also fix this ")] {
            XCTAssertEqual(engine.previewText(in: text), expected, text)
        }
        for text in ["two woks ", "the woks are hot ", "thou doest work ",
                     "they call it woks ", "they called this app woks ", "I cook with this woks ", "she lets work pile up ", "the app lets users type ",
                     "she takes the rope and lets go ", "I heard it work ", "doest ", "its screen ",
                     "its working parts ", "she lets me ", "watch it work ", "HELO ", "woks.txt "] {
            XCTAssertNil(engine.previewText(in: text), text)
        }
        preferences.ignoredWords = ["helo", "woks", "doest", "lets", "its"]
        for text in ["helo ", "it woks ", "it doest work ", "lets fix this ", "its a problem "] {
            XCTAssertNil(engine.previewText(in: text), text)
        }
    }
}
