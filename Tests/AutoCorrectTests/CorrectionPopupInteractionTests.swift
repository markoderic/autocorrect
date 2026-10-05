import XCTest
import AppKit
import AutoCorrectCore
@testable import AutoCorrect

/// The popup's real action and event-routing paths through the engine, with a headless popup
/// (placement and bindings computed, no window) and injected geometry standing in for
/// Accessibility. Clicks are delivered the way the event tap delivers them (type and Quartz
/// point), and actions are invoked through the closures bound to the displayed view. This is
/// not on-screen evidence; it establishes the routing and identity rules.
final class CorrectionPopupInteractionTests: XCTestCase {
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
        /// Fixed-pitch geometry: 8 points per UTF-16 unit on one line at y = 300.
        func rect(_ location: Int, _ length: Int) -> CGRect { CGRect(x: 100 + 8 * CGFloat(location), y: 300, width: 8 * CGFloat(max(length, 1)), height: 16) }
        func geometry(for target: NSRange) -> CorrectionPopup.Geometry {
            let count = text.utf16.count
            return CorrectionPopup.Geometry(word: rect(target.location, target.length),
                                            lineEnd: count > 0 ? rect(count - 1, 1) : nil,
                                            caret: count > 0 ? rect(count - 1, 1) : nil,
                                            visible: CGRect(x: 0, y: 0, width: 1440, height: 900))
        }
    }

    private var suite: String!
    private var defaults: UserDefaults!
    private var preferences: Preferences!
    private var engine: CorrectionEngine!
    private var host: Host!
    private var geometryAvailable = true

    override func setUp() {
        suite = "CorrectionPopupInteraction.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        preferences = Preferences(defaults: defaults)
        preferences.language = "en_US"
        preferences.showsSpellingIndicators = false
        preferences.capitalizesAfterPeriod = false
        host = Host()
        geometryAvailable = true
        engine = CorrectionEngine(preferences: preferences)
        engine.debugInstallHeadlessPopup()
        engine.suppressesRendering = false
        let host = self.host!
        engine.editTransport = { proposal, plan, completion in completion(host.apply(proposal, plan)) }
        engine.snapshotProvider = { host.snapshot() }
        engine.popupFieldFocused = { true }
        engine.undoContextReader = { range in
            let ns = host.text as NSString
            guard range.location >= 0, NSMaxRange(range) <= ns.length else { return nil }
            return ns.substring(with: range)
        }
        engine.popupGeometryProvider = { [weak self] target in
            guard let self, self.geometryAvailable else { return nil }
            return host.geometry(for: target)
        }
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
    private var popup: CorrectionPopup { engine.debugPopup }
    private func center(_ rect: CGRect) -> CGPoint { CGPoint(x: rect.midX, y: rect.midY) }

    func testNewCorrectionStartsQuietlyAndOpensOnDeliberateAction() throws {
        type("teh ")
        engine.debugRenderPopup()
        XCTAssertTrue(popup.isShown)
        XCTAssertEqual(popup.mode, .dot, "details require a deliberate click or the shortcut")
        XCTAssertEqual(engine.popupStatus, "Popup: indicator after the word's line")
        XCTAssertEqual(popup.content?.id, engine.undoRecordID)
        try XCTUnwrap(popup.lastActions).expand()
        XCTAssertEqual(popup.mode, .capsule)
        XCTAssertEqual(popup.content?.original, "teh")
        XCTAssertEqual(popup.content?.replacement, "the")
        XCTAssertEqual(engine.popupStatus, "Popup: beside the word")
    }

    func testAClickInsideThePopupIsLeftToThePopup() throws {
        type("teh ")
        engine.debugRenderPopup()
        try XCTUnwrap(popup.lastActions).expand()
        let frame = try XCTUnwrap(popup.displayedFrame)
        engine.handleMouse(type: .leftMouseDown, location: center(frame))
        XCTAssertTrue(popup.isShown, "the popup must stay for its own button to receive the click")
        XCTAssertEqual(popup.mode, .capsule)
        XCTAssertNotNil(engine.undoRecordID)
    }

    func testAClickOutsideHidesTheCapsuleAndQuietsItToTheIndicator() throws {
        type("teh ")
        engine.debugRenderPopup()
        try XCTUnwrap(popup.lastActions).expand()
        XCTAssertEqual(popup.mode, .capsule)
        let frame = try XCTUnwrap(popup.displayedFrame)
        engine.handleMouse(type: .leftMouseDown, location: CGPoint(x: frame.maxX + 200, y: frame.maxY + 200))
        XCTAssertFalse(popup.isShown)
        XCTAssertNotNil(engine.undoRecordID, "the record survives an editor click; only the UI hides")
        engine.debugRenderPopup()
        XCTAssertTrue(popup.isShown)
        XCTAssertEqual(popup.mode, .dot, "after a deliberate click elsewhere only the quiet indicator returns")
    }

    func testScrollingHidesEvenWhenThePointerIsOverThePopup() throws {
        type("teh ")
        engine.debugRenderPopup()
        let frame = try XCTUnwrap(popup.displayedFrame)
        engine.handleMouse(type: .scrollWheel, location: center(frame))
        XCTAssertFalse(popup.isShown)
        XCTAssertNotNil(engine.undoRecordID)
    }

    func testUndoButtonBoundToTheDisplayedRecordUndoesItAfterContinuedTyping() throws {
        type("teh ")
        engine.debugRenderPopup()
        let actions = try XCTUnwrap(popup.lastActions)
        type("next word ")
        actions.undo()
        XCTAssertEqual(host.text, "teh next word ")
        XCTAssertNil(engine.undoRecordID)
        XCTAssertFalse(popup.isShown)
    }

    func testRetainedOldActionsNeverAffectANewerCorrection() throws {
        type("teh ")
        engine.debugRenderPopup()
        let old = try XCTUnwrap(popup.lastActions)
        type("speoll ")
        engine.debugRenderPopup()
        let new = try XCTUnwrap(popup.lastActions)
        XCTAssertNotEqual(old.id, new.id)
        XCTAssertEqual(host.text, "the spell ")

        let shownContent = try XCTUnwrap(popup.content)
        old.undo()
        XCTAssertEqual(host.text, "the spell ", "an old Undo button must not undo the newer correction")
        XCTAssertEqual(engine.undoRecordID, new.id)
        XCTAssertTrue(engine.status.contains("no longer the latest"), engine.status)
        XCTAssertTrue(popup.isShown, "a stale action must not remove the newer UI")
        XCTAssertEqual(popup.content, shownContent)

        old.dismiss()
        XCTAssertTrue(popup.isShown, "an old Dismiss must not dismiss the newer correction's indicator")
        XCTAssertEqual(popup.content?.id, new.id)

        engine.debugTypeKey("x"); host.text.append("x")   // collapse to the dot
        engine.debugRenderPopup()
        XCTAssertEqual(popup.mode, .dot)
        old.expand()
        XCTAssertEqual(popup.mode, .dot, "an old dot click must not expand the newer record")
        new.expand()
        XCTAssertEqual(popup.mode, .capsule)

    }

    func testNewUndoActionUndoesOnlyTheNewerCorrection() throws {
        type("teh ")
        type("speoll ")
        engine.debugRenderPopup()
        let new = try XCTUnwrap(popup.lastActions)
        new.undo()
        XCTAssertEqual(host.text, "the speoll ")
    }

    func testDismissHidesTheIndicatorButKeepsKeyboardUndo() throws {
        type("teh ")
        engine.debugRenderPopup()
        let actions = try XCTUnwrap(popup.lastActions)
        actions.dismiss()
        XCTAssertFalse(popup.isShown)
        engine.debugRenderPopup()
        XCTAssertFalse(popup.isShown)
        XCTAssertEqual(engine.popupStatus, "Popup: dismissed for this correction")
        engine.undo()
        XCTAssertEqual(host.text, "teh ")
    }

    func testTypingCollapsesToTheDotAndTheDotExpandsOnClick() throws {
        type("teh ")
        engine.debugRenderPopup()
        try XCTUnwrap(popup.lastActions).expand()
        XCTAssertEqual(popup.mode, .capsule)
        engine.debugTypeKey("n"); host.text.append("n")
        XCTAssertFalse(popup.isShown, "the capsule hides as soon as typing continues")
        engine.debugRenderPopup()
        XCTAssertTrue(popup.isShown)
        XCTAssertEqual(popup.mode, .dot)
        let dot = try XCTUnwrap(popup.displayedFrame)
        let lineEnd = host.rect(host.text.utf16.count - 1, 1)
        XCTAssertGreaterThanOrEqual(dot.minX, lineEnd.maxX + 3, "the dot follows the line end, never the span")
        try XCTUnwrap(popup.lastActions).expand()
        XCTAssertEqual(popup.mode, .capsule)
        XCTAssertTrue(popup.isShown)
    }

    func testShortcutReopensTheCapsuleForTheLatestRecord() throws {
        type("teh ")
        engine.debugTypeKey("n"); host.text.append("n")
        engine.debugRenderPopup()
        XCTAssertEqual(popup.mode, .dot)
        engine.showPopupForLatestCorrection()
        XCTAssertEqual(popup.mode, .capsule)
        XCTAssertTrue(popup.isShown)
    }

    func testExpiredRecordRemovesItsUIWithoutFurtherTyping() throws {
        type("teh ")
        engine.debugRenderPopup()
        XCTAssertTrue(popup.isShown)
        engine.debugBackdateUndoRecord(seconds: 301)
        engine.debugRenderPopup()   // what the expiry timer invokes
        XCTAssertFalse(popup.isShown)
        XCTAssertNil(engine.undoRecordID)
        XCTAssertEqual(engine.popupStatus, "Popup: none (correction expired)")
    }

    func testChangedTextInvalidatesTheRecordAndRemovesTheUI() throws {
        type("teh ")
        engine.debugRenderPopup()
        host.text = "tha "   // the user edited the corrected word by hand
        engine.debugRenderPopup()   // what the value-changed notification invokes
        XCTAssertFalse(popup.isShown)
        XCTAssertNil(engine.undoRecordID)
        XCTAssertTrue(engine.popupStatus.contains("no longer undoable"), engine.popupStatus)
    }

    func testMissingGeometryHidesWithoutGuessingAndKeepsKeyboardUndo() throws {
        geometryAvailable = false
        type("teh ")
        engine.debugRenderPopup()
        XCTAssertFalse(popup.isShown)
        XCTAssertNil(popup.displayedFrame)
        XCTAssertEqual(engine.popupStatus, "Popup: word position unavailable in this app")
        XCTAssertNotNil(engine.undoRecordID)
        engine.undo()
        XCTAssertEqual(host.text, "teh ")
    }

    func testPopupOffNeverShowsButCorrectionAndUndoWork() throws {
        preferences.showsCorrectionPopup = false
        type("teh ")
        engine.debugRenderPopup()
        XCTAssertFalse(popup.isShown)
        XCTAssertEqual(engine.popupStatus, "Popup: off")
        XCTAssertEqual(host.text, "the ")
        engine.undo()
        XCTAssertEqual(host.text, "teh ")
    }

    func testTemporaryReadFailurePreservesKeyboardUndo() throws {
        type("teh ")
        engine.debugRenderPopup()
        let current = try XCTUnwrap(engine.undoRecordID)
        engine.undoContextReader = { _ in nil }   // Accessibility cannot read the context right now
        engine.debugRenderPopup()
        XCTAssertFalse(popup.isShown)
        XCTAssertEqual(engine.popupStatus, "Popup: hidden (text could not be read right now)")
        XCTAssertEqual(engine.undoRecordID, current, "unavailable context is not evidence that the text changed")
        XCTAssertNotNil(engine.undoProposal)
        engine.undo()   // ordinary keyboard Undo takes its own fresh read
        XCTAssertEqual(host.text, "teh ", "a later successful fresh read still allows ordinary Undo")
    }

    func testReadFailureThenSuccessfulReadShowsTheIndicatorAgain() throws {
        type("teh ")
        engine.debugRenderPopup()
        let host = self.host!
        engine.undoContextReader = { _ in nil }
        engine.debugRenderPopup()
        XCTAssertFalse(popup.isShown)
        engine.undoContextReader = { range in (host.text as NSString).substring(with: range) }
        engine.debugRenderPopup()
        XCTAssertTrue(popup.isShown)
        XCTAssertEqual(popup.content?.id, engine.undoRecordID)
    }

    func testLosingFocusHidesTheUIAndKeepsTheRecordUntilInvalidation() throws {
        type("teh ")
        engine.debugRenderPopup()
        engine.popupFieldFocused = { false }
        engine.debugRenderPopup()
        XCTAssertFalse(popup.isShown)
        XCTAssertNotNil(engine.undoRecordID)
        engine.invalidate()   // what an actual focus change does
        XCTAssertNil(engine.undoRecordID)
        XCTAssertFalse(popup.isShown)
    }
}
