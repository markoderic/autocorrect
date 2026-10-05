import XCTest
import AppKit
import AutoCorrectCore
@testable import AutoCorrect

/// The popup's Undo is bound to the identity of one verified correction. These sequences run
/// the real engine and native checker against a fake host (same seams as the field-start
/// tests): they establish the record and refusal logic, not real-editor delivery or the
/// panel's on-screen behavior, which need Accessibility geometry.
final class UndoRecordIdentityTests: XCTestCase {
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
        suite = "UndoRecordIdentity.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        preferences = Preferences(defaults: defaults)
        preferences.language = "en_US"
        preferences.showsSpellingIndicators = false
        preferences.capitalizesAfterPeriod = false
        host = Host()
        engine = CorrectionEngine(preferences: preferences)
        engine.suppressesRendering = true
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

    func testVerifiedCorrectionCreatesARecordWithAnIdentity() throws {
        XCTAssertNil(engine.undoRecordID)
        type("teh ")
        XCTAssertEqual(host.text, "the ")
        XCTAssertNotNil(engine.undoProposal)
        XCTAssertNotNil(engine.undoRecordID)
    }

    func testUndoByIdentityAfterContinuedTypingPreservesFollowingText() throws {
        type("teh ")
        let id = try XCTUnwrap(engine.undoRecordID)
        type("next word ")
        XCTAssertEqual(host.text, "the next word ")
        engine.undo(recordID: id)
        XCTAssertEqual(host.text, "teh next word ")
        XCTAssertNil(engine.undoRecordID, "a consumed record cannot be undone twice")
        XCTAssertNil(engine.undoProposal)
    }

    func testTwoRapidCorrectionsGiveDistinctIdentitiesAndAStaleOneIsRefused() throws {
        // Both words arrive before the first read; the engine posts one edit per pass.
        host.text = "teh speoll "
        engine.debugAppendKeys("teh speoll ")
        engine.processBoundaries(using: host.snapshot())
        XCTAssertEqual(host.text, "the speoll ")
        let first = try XCTUnwrap(engine.undoRecordID)
        engine.processBoundaries(using: host.snapshot())
        XCTAssertEqual(host.text, "the spell ")
        let second = try XCTUnwrap(engine.undoRecordID)
        XCTAssertNotEqual(first, second)
        engine.undo(recordID: first)
        XCTAssertEqual(host.text, "the spell ", "a button built for the first correction must not undo the second")
        XCTAssertEqual(engine.undoRecordID, second, "the current record survives a refused stale request")
        engine.undo(recordID: second)
        XCTAssertEqual(host.text, "the speoll ")
    }

    func testOutdatedPopupNeverEditsChangedText() throws {
        // Case 1: the user extended the corrected word ("the" → "then"). The anchor still finds
        // "the" at its offset, but the replacement plan refuses because no delimiter follows.
        type("teh ")
        let id = try XCTUnwrap(engine.undoRecordID)
        host.text = "then "
        engine.undo(recordID: id)
        XCTAssertEqual(host.text, "then ", "no edit when the recorded span has grown")
        XCTAssertTrue(engine.status.contains("Undo unavailable") || engine.status.contains("skipped"), engine.status)
        // Case 2: the user changed the corrected word itself ("the" → "tha"): the anchor fails.
        engine.invalidate(); host.text = ""
        type("teh ")
        let second = try XCTUnwrap(engine.undoRecordID)
        host.text = "tha "
        engine.undo(recordID: second)
        XCTAssertEqual(host.text, "tha ")
        XCTAssertTrue(engine.status.contains("Undo unavailable"), engine.status)
    }

    func testFocusChangeClearsTheRecord() throws {
        type("teh ")
        XCTAssertNotNil(engine.undoRecordID)
        engine.invalidate()
        XCTAssertNil(engine.undoRecordID)
        XCTAssertNil(engine.undoProposal)
        XCTAssertEqual(engine.popupStatus, "Popup: none")
    }

    func testExpiredRecordIsRefused() throws {
        type("teh ")
        let id = try XCTUnwrap(engine.undoRecordID)
        engine.debugBackdateUndoRecord(seconds: 301)
        engine.undo(recordID: id)
        XCTAssertEqual(host.text, "the ")
        XCTAssertTrue(engine.status.contains("Undo unavailable"), engine.status)
    }

    func testPopupOffLeavesCorrectionAndKeyboardUndoWorking() throws {
        preferences.showsCorrectionPopup = false
        type("teh ")
        XCTAssertEqual(host.text, "the ")
        XCTAssertNotNil(engine.undoRecordID, "the record exists for the keyboard shortcut and the menu")
        engine.undo()
        XCTAssertEqual(host.text, "teh ")
    }

    func testShortcutReopenRequiresARecordAndTheSetting() throws {
        XCTAssertNil(engine.undoRecordID)
        engine.showPopupForLatestCorrection()
        XCTAssertEqual(engine.popupStatus, "Popup: none")
        type("teh ")
        preferences.showsCorrectionPopup = false
        engine.showPopupForLatestCorrection()
        XCTAssertEqual(engine.popupStatus, "Popup: none", "rendering is suppressed in tests; the setting gate alone keeps the status")
    }
}
