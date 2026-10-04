import XCTest
import AppKit
import AutoCorrectCore
@testable import AutoCorrect

/// Batch 1 behavior through the real engine and native checker, without Accessibility or
/// keyboard events: field-start capitalization (immediate and completed-word timing), short
/// contraction repairs with their competitors, all-caps contractions, and capitalized typos
/// that stay detectable. Edits cannot post here (no event tap); the proposal handed to the
/// keyboard path is inspected instead.
final class FieldStartEngineTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private var preferences: Preferences!
    private var engine: CorrectionEngine!

    override func setUp() {
        suite = "FieldStartEngine.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        preferences = Preferences(defaults: defaults)
        preferences.language = "en_US"
        engine = CorrectionEngine(preferences: preferences)
        engine.suppressesRendering = true
        engine.fieldStartConfirmation = { _ in true }
    }
    override func tearDown() {
        engine = nil
        defaults.removePersistentDomain(forName: suite)
    }

    private func snapshot(_ text: String, windowStart: Int = 0, isTextArea: Bool = true) -> AccessibilityText.Snapshot {
        AccessibilityText.Snapshot(element: AXUIElementCreateApplication(getpid()), pid: getpid(), text: text,
                                   windowStart: windowStart, caret: windowStart + text.utf16.count, physicalKeyCount: 0, isTextArea: isTextArea)
    }

    /// Types `keys` into a fresh session and runs one read showing `text`; returns the edit.
    private func typed(_ keys: String, showing text: String? = nil, windowStart: Int = 0, isTextArea: Bool = true) -> CorrectionEngine.Proposal? {
        engine.invalidate()
        engine.lastProposal = nil
        engine.debugAppendKeys(keys)
        engine.processBoundaries(using: snapshot(text ?? keys, windowStart: windowStart, isTextArea: isTextArea))
        return engine.lastProposal
    }

    func testFirstLetterIsCapitalizedBeforeAnyDelimiter() {
        let edit = typed("h")
        XCTAssertEqual(edit?.original, "h")
        XCTAssertEqual(edit?.replacement, "H")
        XCTAssertEqual(edit?.range, NSRange(location: 0, length: 1))
        // A fast second letter before the edit landed: the whole short word is recased.
        XCTAssertEqual(typed("he")?.replacement, "He")
        XCTAssertEqual(typed(" \"h")?.range, NSRange(location: 2, length: 1))
        XCTAssertEqual(typed("(hello")?.replacement, "Hello")
        XCTAssertEqual(typed("odnt")?.replacement, "Odnt")
        XCTAssertEqual(typed("i")?.replacement, "I")
    }

    func testImmediateCapitalizationRequiresGenuineFieldStartEvidence() {
        // Existing text before the caret, a window that does not start at the field, a
        // single-line control, failed length evidence, a capital, an ignored word, a
        // non-letter prefix or the feature being off: no edit, and no further reads.
        XCTAssertNil(typed("h", showing: "foo h"))
        XCTAssertNil(typed("h", windowStart: 300))
        XCTAssertNil(typed("h", isTextArea: false))
        XCTAssertNil(typed("H"))
        XCTAssertNil(typed("🙂 h", showing: "🙂 h"))
        XCTAssertNil(typed("`h"))
        XCTAssertNil(typed("h", showing: "hh"))      // more text than was typed this session
        engine.fieldStartConfirmation = { _ in false }
        XCTAssertNil(typed("h"))
        engine.fieldStartConfirmation = { _ in true }
        preferences.ignoredWords = ["h"]
        XCTAssertNil(typed("h"))
        preferences.ignoredWords = []
        preferences.capitalizesAfterPeriod = false
        XCTAssertNil(typed("h"))
        preferences.capitalizesAfterPeriod = true
        XCTAssertNotNil(typed("h"))
        // One session, one decision: a rejected session does not read again for later letters.
        var reads = 0
        engine.fieldStartConfirmation = { _ in reads += 1; return false }
        engine.invalidate()
        engine.lastProposal = nil
        engine.debugAppendKeys("h")
        engine.processBoundaries(using: snapshot("h"))
        engine.debugAppendKeys("e")
        engine.processBoundaries(using: snapshot("he"))
        XCTAssertEqual(reads, 1)
        XCTAssertNil(engine.lastProposal)
    }

    func testCompletedFirstWordFallsBackToDelimiterTimingWithTheSameEvidence() {
        XCTAssertEqual(typed("hello ")?.replacement, "Hello")
        XCTAssertEqual(typed("odnt ")?.replacement, "Don't")
        XCTAssertEqual(typed("teh ")?.replacement, "The")
        XCTAssertEqual(typed("iphone ")?.replacement, "iPhone")   // canonical casing beats the capital
        XCTAssertEqual(typed("github ")?.replacement, "GitHub")
        XCTAssertNil(typed("hello ", showing: "foo hello "))
        XCTAssertNil(typed("hello ", isTextArea: false))
        engine.fieldStartConfirmation = { _ in false }
        XCTAssertNil(typed("hello "))
        XCTAssertEqual(typed("odnt ")?.replacement, "don't")   // the spelling repair does not need field evidence
        engine.fieldStartConfirmation = { _ in true }
        preferences.capitalizesAfterPeriod = false
        XCTAssertNil(typed("hello "))
        XCTAssertEqual(typed("odnt ")?.replacement, "don't")
    }

    func testSuggestionPathMatchesWithExplicitFieldStartFlag() {
        XCTAssertEqual(engine.suggestion(in: "hello ", atFieldStart: true), "Hello")
        XCTAssertNil(engine.suggestion(in: "hello "))
        XCTAssertEqual(engine.suggestion(in: "odnt do ", atFieldStart: true), nil)   // the last word is "do"
        XCTAssertEqual(engine.suggestion(in: "odnt ", atFieldStart: true), "Don't")
        XCTAssertEqual(engine.suggestion(in: "\"odnt ", atFieldStart: true), "Don't")
        XCTAssertEqual(engine.suggestion(in: "Odnt ", atFieldStart: true), "Don't")
        XCTAssertEqual(engine.suggestion(in: "Odnt "), "Don't")
        XCTAssertEqual(engine.suggestion(in: "I odnt "), "don't")
        XCTAssertEqual(engine.suggestion(in: "I dont "), "don't")
        XCTAssertEqual(engine.suggestion(in: "I odn't "), "don't")
        XCTAssertEqual(engine.suggestion(in: "I odn’t "), "don’t")
        XCTAssertEqual(engine.suggestion(in: "I doenst "), "doesn't")
        XCTAssertEqual(engine.suggestion(in: "I dnot "), "don't")
        XCTAssertEqual(engine.suggestion(in: "I cnat "), "can't")
        preferences.capitalizesAfterPeriod = false
        XCTAssertEqual(engine.suggestion(in: "odnt ", atFieldStart: true), "don't")
    }

    func testShortContractionCompetitorsNamesAndUserChoicesAreRespected() {
        for text in ["font ", "I dent ", "donut ", "Marko ", "dont.txt ", "I odnt.txt ", "I odnts "] {
            XCTAssertNil(engine.suggestion(in: text), text)
        }
        // Unchanged baseline behavior, recorded here so a later change is deliberate: `cant`
        // and `wont` are documented prose defaults, and the general one-edit gate still
        // accepts the native reading of `dotn` (down) and `ont` (not).
        XCTAssertEqual(engine.suggestion(in: "cant "), "can't")
        XCTAssertEqual(engine.suggestion(in: "wont "), "won't")
        XCTAssertEqual(engine.suggestion(in: "I dotn "), "down")
        XCTAssertEqual(engine.suggestion(in: "I dnt "), "dint")
        preferences.customCorrections = ["odnt": "ODNT Ltd"]
        XCTAssertEqual(engine.suggestion(in: "I odnt "), "ODNT Ltd")
        XCTAssertEqual(engine.suggestion(in: "odnt ", atFieldStart: true), "ODNT Ltd")
        preferences.customCorrections = [:]
        preferences.ignoredWords = ["odnt"]
        XCTAssertNil(engine.suggestion(in: "I odnt "))
        XCTAssertNil(engine.suggestion(in: "Odnt "))
        XCTAssertNil(typed("odnt "))
    }

    func testAllCapsContractionsNeedAnAllCapsFollowingWord() {
        XCTAssertEqual(engine.previewText(in: "ODNT DO THAT "), "DON'T DO THAT ")
        XCTAssertEqual(engine.previewText(in: "DONT DO THAT "), "DON'T DO THAT ")
        XCTAssertEqual(engine.previewText(in: "I CNAT GO "), "I CAN'T GO ")
        XCTAssertEqual(engine.previewText(in: "ODN’T DO "), "DON’T DO ")
        for text in ["ODNT ", "ODNT XYZ ", "ODNT Do ", "ODST DO ", "ITS A ", "NASA DO ", "I DOTN KNOW "] {
            XCTAssertNil(engine.previewText(in: text), text)
        }
        preferences.ignoredWords = ["odnt"]
        XCTAssertNil(engine.previewText(in: "ODNT DO THAT "))
        preferences.ignoredWords = []
        preferences.checksContext = false
        XCTAssertNil(engine.previewText(in: "ODNT DO THAT "))
    }

    func testCapitalizedTyposStayDetectableWhereSentencesStart() {
        // A capitalized word the native checker rejects is marked where a sentence starts;
        // the same word mid-sentence is treated as a name. (Higgsfield is not in the bundled
        // lexicon: before this batch only its capital letter kept it unmarked.)
        XCTAssertEqual(engine.scanMarks(text: "Speoll next", windowStart: 0, caret: 11).map(\.word), ["Speoll"])
        XCTAssertEqual(engine.scanMarks(text: "Speoll next", windowStart: 100, caret: 111), [])
        XCTAssertEqual(engine.scanMarks(text: "Teh next. Hte ok", windowStart: 0, caret: 16).map(\.word), ["Teh", "Hte"])
        XCTAssertEqual(engine.scanMarks(text: "Marko met Higgsfield", windowStart: 0, caret: 20), [])
        XCTAssertEqual(engine.scanMarks(text: "Higgsfield met Speoll", windowStart: 0, caret: 21).map(\.word), ["Higgsfield"])
        XCTAssertEqual(engine.scanMarks(text: "Marko said hi. Djerko too", windowStart: 0, caret: 25).map(\.word), ["Djerko"])
        preferences.ignoredWords = ["speoll", "higgsfield"]
        XCTAssertEqual(engine.scanMarks(text: "Speoll next. Higgsfield", windowStart: 0, caret: 23), [])
        preferences.ignoredWords = []
        // Detection is not replacement: a typed capitalized word without a confident repair
        // is marked, and the mark survives the existing-text scan that replaces marks.
        engine.invalidate()
        engine.lastProposal = nil
        engine.fieldStartConfirmation = { _ in false }
        engine.debugAppendKeys("Higgsfield ")
        engine.processBoundaries(using: snapshot("Higgsfield "))
        XCTAssertEqual(engine.marks.map(\.word), ["Higgsfield"])
        XCTAssertNil(engine.lastProposal)
        XCTAssertEqual(engine.scanMarks(text: "Higgsfield next", windowStart: 0, caret: 15).map(\.word), ["Higgsfield"])
    }
}
