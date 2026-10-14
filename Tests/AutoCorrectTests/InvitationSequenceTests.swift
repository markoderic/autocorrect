import XCTest
import AppKit
import AutoCorrectCore
@testable import AutoCorrect

/// The owner's missed `lets` corrections, typed through the real engine against a fake host:
/// slow and fast typing, sentence starts, discourse openers, deletion and retyping, and the
/// Return key. Same seams as the field-start tests; not real-editor evidence.
final class InvitationSequenceTests: XCTestCase {
    final class Host {
        var text = ""
        let element = AXUIElementCreateApplication(getpid())
        func snapshot() -> AccessibilityText.Snapshot {
            AccessibilityText.Snapshot(element: element, pid: getpid(), text: text, windowStart: 0,
                                       caret: text.utf16.count, physicalKeyCount: 0, isTextArea: true)
        }
        func apply(_ proposal: CorrectionEngine.Proposal, _ plan: KeyboardReplacementPlan) -> String? {
            guard text == proposal.snapshot.text else { return nil }
            let kept = (text as NSString).substring(to: text.utf16.count - plan.deleteCount)
            text = kept + plan.insertion
            return (text as NSString).substring(to: plan.expectedCaret)
        }
    }

    private var suite: String!
    private var defaults: UserDefaults!
    private var preferences: Preferences!
    private var engine: CorrectionEngine!
    private var host: Host!

    override func setUp() {
        suite = "InvitationSequence.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        preferences = Preferences(defaults: defaults)
        preferences.language = "en_US"
        preferences.showsSpellingIndicators = false
        preferences.showsCorrectionPopup = false
        host = Host()
        engine = CorrectionEngine(preferences: preferences)
        engine.suppressesRendering = true
        engine.fieldStartConfirmation = { _ in true }
        let host = self.host!
        engine.editTransport = { proposal, plan, completion in completion(host.apply(proposal, plan)) }
        engine.snapshotProvider = { host.snapshot() }
    }
    override func tearDown() {
        engine = nil
        defaults.removePersistentDomain(forName: suite)
    }

    private func type(_ keys: String) {
        for character in keys {
            host.text.append(character)
            engine.debugAppendKeys(String(character))
            engine.processBoundaries(using: host.snapshot())
        }
    }
    private func typeFast(_ keys: String) {
        host.text += keys
        engine.debugAppendKeys(keys)
        engine.processBoundaries(using: host.snapshot())
        // Remaining boundaries are processed on the next read, as the engine would schedule.
        engine.processBoundaries(using: host.snapshot())
    }

    func testOwnerPhrasesTypedSlowly() {
        type("Ok then lets go ")
        XCTAssertEqual(host.text, "Ok then let's go ")
        engine.invalidate(); host.text = ""
        type("No lets do it in claude ")
        XCTAssertEqual(host.text, "No let's do it in Claude ", "the product name gains its casing as well (repair pass, October 5)")
    }

    func testOwnerPhrasesTypedFast() {
        typeFast("Ok then lets go ")
        XCTAssertEqual(host.text, "Ok then let's go ")
        engine.invalidate(); host.text = ""
        typeFast("No lets do it in claude ")
        XCTAssertEqual(host.text, "No let's do it in Claude ")
    }

    func testCoordinatedInvitationsTypedSlowlyAndQuickly() {
        for fast in [false, true] {
            engine.invalidate(); host.text = "Let's improve this and "
            if fast { typeFast("lets work through it ") }
            else { type("lets work through it ") }
            XCTAssertEqual(host.text, "Let's improve this and let's work through it ")
        }
    }

    func testCoordinatedInvitationRespectsPreferencesAndIgnoredWords() {
        let text = "Let's improve this and lets work "
        preferences.ignoredWords = ["lets"]
        XCTAssertNil(engine.contextualCandidate(in: text))
        preferences.ignoredWords = []
        preferences.customCorrections = ["lets": "custom"]
        XCTAssertNil(engine.contextualCandidate(in: text))
        preferences.customCorrections = [:]
        preferences.checksContext = false
        XCTAssertNil(engine.contextualCandidate(in: text))
    }

    func testCoordinatedVerbRemainsIntactDuringTyping() {
        for prefix in ["She grabs the rope and ", "Let's see how she waits and "] {
            engine.invalidate(); host.text = prefix
            type("lets go ")
            XCTAssertEqual(host.text, prefix + "lets go ")
        }
    }

    func testSentenceStartsAndDiscourseOpeners() {
        type("lets go ")
        XCTAssertEqual(host.text, "Let's go ", "field start: capitalized and contracted")
        engine.invalidate(); host.text = "Done. "
        type("lets try again ")
        XCTAssertEqual(host.text, "Done. Let's try again ")
        engine.invalidate(); host.text = ""
        type("Yes please lets start ")
        XCTAssertEqual(host.text, "Yes please let's start ")
    }

    func testVerbUsesAreNeverChanged() {
        for sentence in ["The app lets users export ", "She then lets go of the rope ", "He lets me choose ", "No one lets him in "] {
            engine.invalidate(); host.text = ""
            type(sentence)
            XCTAssertEqual(host.text, sentence)
        }
    }

    func testDeletingTheCorrectionAndRetypingKeepsTheWriterSpelling() {
        type("No lets do it ")
        XCTAssertEqual(host.text, "No let's do it ")
        // Delete back to "No " and retype the same words: the occurrence-level override must hold.
        host.text = "No "
        engine.debugDeleteKey()
        type("lets do it ")
        XCTAssertEqual(host.text, "No lets do it ", "a deliberate retype of the same occurrence is respected")
    }

    func testDeletingTheWholeFieldAndRetypingCorrectsAgain() {
        type("No lets do it ")
        XCTAssertEqual(host.text, "No let's do it ")
        host.text = ""
        engine.debugDeleteKey()
        type("No lets do it ")
        XCTAssertEqual(host.text, "No let's do it ", "a fresh attempt at the whole field is not an override")
    }

    func testVerbCompletedByReturnIsNotCorrectedBecauseNoBoundaryExists() {
        // In a chat composer Return submits; the engine never synthesizes a boundary for it.
        type("Ok then lets go")
        engine.debugTypeKey(nil, keyCode: 36)
        XCTAssertEqual(host.text, "Ok then lets go", "documented limitation: the final word before Return is never assessed")
    }
    func testOmissionsPreserveFollowingTextAtSlowAndFastBoundaries() {
        for fast in [false, true] {
            for (input, expected) in [("wit that ", "with that "), ("the user wats to type ", "the user wants to type "),
                                      ("the men bar ", "the menu bar "), ("os we can go ", "so we can go ")] {
                preferences.capitalizesAfterPeriod = false
                engine.invalidate(); host.text = ""
                if fast {
                    typeFast(input)
                    for _ in 0..<8 { engine.processBoundaries(using: host.snapshot()) }
                } else { type(input) }
                type("next ")
                XCTAssertEqual(host.text, expected + "next ", "fast=\(fast), \(input)")
            }
        }
        preferences.capitalizesAfterPeriod = true
        engine.invalidate(); host.text = ""
        type("os we can go ")
        XCTAssertEqual(host.text, "So we can go ")
    }

    func testNewContextRulesHonorOverridesAndCorrectWords() {
        preferences.capitalizesAfterPeriod = false
        for text in ["her sharp wit ", "a wit that delights ", "the men work ", "OS updates ", "os.path ", "its just working parts "] {
            engine.invalidate(); host.text = ""
            type(text)
            XCTAssertEqual(host.text, text)
        }
        preferences.ignoredWords = ["wit", "os", "anyones"]
        XCTAssertNil(engine.previewText(in: "wit that "))
        XCTAssertNil(engine.previewText(in: "os we go "))
        XCTAssertNil(engine.previewText(in: "anyones computer "))
        preferences.ignoredWords = []
        preferences.customCorrections = ["wit": "wit"]
        XCTAssertNil(engine.contextualCandidate(in: "wit that "))
        preferences.customCorrections = [:]
        preferences.checksContext = false
        XCTAssertNil(engine.contextualCandidate(in: "wit that "))
    }

    func testContextualOmissionManualRetypeIsRespected() {
        preferences.capitalizesAfterPeriod = false
        type("work wit that ")
        XCTAssertEqual(host.text, "work with that ")
        host.text = "work "
        engine.debugDeleteKey()
        type("wit that ")
        XCTAssertEqual(host.text, "work wit that ")
    }
}
