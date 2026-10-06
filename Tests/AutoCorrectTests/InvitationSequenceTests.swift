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
}
