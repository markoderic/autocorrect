import XCTest
import AppKit
import AutoCorrectCore
@testable import AutoCorrect

/// Mark bookkeeping through the actual engine and native checker, without Accessibility
/// or keyboard events. Rendering is suppressed; the model is inspected directly.
final class SpellingMarkEngineTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private var preferences: Preferences!
    private var engine: CorrectionEngine!

    override func setUp() {
        suite = "SpellingMarkEngine.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        preferences = Preferences(defaults: defaults)
        preferences.language = "en_US"
        engine = CorrectionEngine(preferences: preferences)
        engine.suppressesRendering = true
    }
    override func tearDown() {
        engine = nil
        defaults.removePersistentDomain(forName: suite)
    }

    private func snapshot(_ text: String, windowStart: Int = 0) -> AccessibilityText.Snapshot {
        AccessibilityText.Snapshot(element: AXUIElementCreateApplication(getpid()), pid: getpid(), text: text,
                                   windowStart: windowStart, caret: windowStart + text.utf16.count, physicalKeyCount: 0)
    }

    func testExistingTextScanMarksOnlyEligibleMisspelledWordsAndRespectsPolicy() {
        let text = "we said aswell abit teh Higgsfield codespell recieve untill next"
        let marks = engine.scanMarks(text: text, windowStart: 100, caret: 100 + text.utf16.count)
        XCTAssertEqual(marks.map(\.word), ["aswell", "abit", "teh", "codespell", "recieve", "untill"])
        XCTAssertEqual(marks.first?.location, 108)
        // Ignored words, custom rules, recognized technical terms and names stay unmarked.
        preferences.ignoredWords = ["untill", "codespell"]
        preferences.customCorrections = ["teh": "the"]
        XCTAssertEqual(engine.scanMarks(text: text, windowStart: 0, caret: text.utf16.count).map(\.word), ["aswell", "abit", "recieve"])
        XCTAssertTrue(engine.scanMarks(text: "use nginx and kubernetes and iphone ", windowStart: 0, caret: 36).isEmpty)
        // The word at the caret is the one being typed.
        XCTAssertEqual(engine.scanMarks(text: "aswell abi", windowStart: 0, caret: 10).map(\.word), ["aswell"])
        // Turning underlines off disables scanning entirely.
        preferences.showsSpellingIndicators = false
        XCTAssertTrue(engine.scanMarks(text: text, windowStart: 0, caret: text.utf16.count).isEmpty)
    }

    func testTypedBoundariesAccumulateMarksThatSurviveFurtherTypingAndVanishWhenTheWordChanges() {
        engine.debugAppendKeys("aswell abit ")
        engine.processBoundaries(using: snapshot("we said aswell abit "))
        XCTAssertEqual(engine.marks.map(\.word), ["aswell", "abit"])
        XCTAssertEqual(engine.marks.map(\.location), [8, 15])
        // A third, correctly spelled word keeps both marks.
        engine.debugAppendKeys("next ")
        engine.processBoundaries(using: snapshot("we said aswell abit next "))
        XCTAssertEqual(engine.marks.map(\.word), ["aswell", "abit"])
        // The user deleted "abit": the next pass drops that mark only.
        engine.processBoundaries(using: snapshot("we said aswell next "))
        XCTAssertEqual(engine.marks.map(\.word), ["aswell"])
        // A different field starts empty.
        engine.processBoundaries(using: AccessibilityText.Snapshot(element: AXUIElementCreateSystemWide(), pid: getpid(),
                                                                   text: "other ", windowStart: 0, caret: 6, physicalKeyCount: 0))
        XCTAssertTrue(engine.marks.isEmpty)
    }

    func testIgnoringOverridingAndTheToggleRemoveMarks() {
        engine.debugAppendKeys("aswell abit ")
        engine.processBoundaries(using: snapshot("aswell abit "))
        XCTAssertEqual(engine.marks.count, 2)
        engine.ignore(word: "abit")
        XCTAssertEqual(engine.marks.map(\.word), ["aswell"])
        XCTAssertTrue(preferences.ignoredWords.contains("abit"))
        engine.noteOverride(SpellingMark(location: 0, word: "aswell"))
        XCTAssertTrue(engine.marks.isEmpty)
        // An overridden occurrence is not re-marked by a later scan of the same text.
        XCTAssertTrue(engine.scanMarks(text: "aswell abit ", windowStart: 0, caret: 12).isEmpty)
        engine.debugAppendKeys("agre ")
        engine.processBoundaries(using: snapshot("aswell abit agre "))
        XCTAssertEqual(engine.marks.map(\.word), ["agre"])
        preferences.showsSpellingIndicators = false
        engine.refresh()
        XCTAssertTrue(engine.marks.isEmpty)
    }

    func testCorrectedWordsAreNeverMarkedAndAnEditShiftsLaterMarks() {
        engine.debugAppendKeys("abit teh ")
        engine.processBoundaries(using: snapshot("abit teh "))
        // "teh" has a confident repair; the edit cannot be posted in tests, so no mark is
        // created for it while "abit" stays marked.
        XCTAssertEqual(engine.marks.map(\.word), ["abit"])
        engine.noteAppliedEdit(location: 0, length: 4, replacementLength: 5)
        XCTAssertTrue(engine.marks.isEmpty)
        engine.debugAppendKeys("aswell ")
        engine.processBoundaries(using: snapshot("a bit the aswell "))
        XCTAssertEqual(engine.marks, [SpellingMark(location: 10, word: "aswell")])
        engine.noteAppliedEdit(location: 0, length: 1, replacementLength: 3)
        XCTAssertEqual(engine.marks, [SpellingMark(location: 12, word: "aswell")])
    }
}
