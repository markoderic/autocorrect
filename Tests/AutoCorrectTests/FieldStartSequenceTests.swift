import XCTest
import AppKit
import AutoCorrectCore
@testable import AutoCorrect

/// Whole sequences through the real engine and native checker: the first key, the edit
/// actually landing in a fake host, further typing, and then completed-token casing,
/// undo or approval. The host applies prepared plans exactly as the posted key events
/// would (delete N units, insert the string) and refuses an edit whose snapshot no longer
/// matches its text, like the real revalidation inside the event tap. No Accessibility or
/// keyboard events are involved; this is not real-editor evidence.
final class FieldStartSequenceTests: XCTestCase {
    /// A single-field editor. Text is the whole field; the caret is always at the end
    /// unless a test says otherwise.
    final class Host {
        var text = ""
        let element = AXUIElementCreateApplication(getpid())
        var isTextArea = true
        func snapshot() -> AccessibilityText.Snapshot {
            AccessibilityText.Snapshot(element: element, pid: getpid(), text: text, windowStart: 0,
                                       caret: text.utf16.count, physicalKeyCount: 0, isTextArea: isTextArea)
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
        suite = "FieldStartSequence.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        preferences = Preferences(defaults: defaults)
        preferences.language = "en_US"
        preferences.showsSpellingIndicators = false
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

    /// Slow typing: the engine's scheduled read runs after every key.
    private func type(_ keys: String) {
        for character in keys {
            host.text.append(character)
            engine.debugAppendKeys(String(character))
            engine.processBoundaries(using: host.snapshot())
        }
    }
    /// Fast typing: all keys arrive before one read.
    private func typeFast(_ keys: String) {
        host.text += keys
        engine.debugAppendKeys(keys)
        engine.processBoundaries(using: host.snapshot())
    }

    func testDeletingFirstAttemptStartsFreshWithCapitalizationOnAndOff() {
        for capitals in [true, false] {
            engine.invalidate(); host.text = ""
            preferences.capitalizesAfterPeriod = capitals
            type("teh ")
            engine.debugDeleteKey()
            host.text = ""
            type("lets do that ")
            for _ in 0..<4 { engine.processBoundaries(using: host.snapshot()) }
            XCTAssertEqual(host.text, capitals ? "Let's do that " : "let's do that ")
        }
    }

    func testFullyDeletingCapitalizedFirstWordAllowsSameInitialAgain() {
        type("h"); type("ello")
        engine.debugDeleteKey(); host.text = ""
        type("h"); type("owever ")
        XCTAssertEqual(host.text, "However ")
    }

    func testReportedDeadlineSentenceAndUndoAfterFollowingText() {
        type("lets do that byu this date ")
        for _ in 0..<8 { engine.processBoundaries(using: host.snapshot()) }
        XCTAssertEqual(host.text, "Let's do that by this date ")
        type("please ")
        engine.undo()
        XCTAssertEqual(host.text, "Let's do that byu this date please ")
    }

    func testAmbiguousByuWaitsForTheCompletedDeadline() {
        preferences.capitalizesAfterPeriod = false
        type("lets do that byu ")
        XCTAssertEqual(host.text, "let's do that byu ")
        type("this ")
        XCTAssertEqual(host.text, "let's do that byu this ")
        type("date ")
        XCTAssertEqual(host.text, "let's do that by this date ")
    }

    func testFastRestartAndDeadlineKeepsFollowingIncompleteText() {
        type("teh ")
        engine.debugDeleteKey(); host.text = ""
        typeFast("lets do that byu this date nex")
        for _ in 0..<8 { engine.processBoundaries(using: host.snapshot()) }
        XCTAssertEqual(host.text, "Let's do that by this date nex")
    }

    func testFreshSingleLineFieldAlsoDropsThePreviousRejection() {
        preferences.capitalizesAfterPeriod = false
        host.isTextArea = false
        type("teh ")
        engine.debugDeleteKey(); host.text = ""
        type("lets do that ")
        XCTAssertEqual(host.text, "let's do that ")
    }

    func testUnverifiedFieldRestartRetainsExistingProtection() {
        type("teh ")
        engine.debugDeleteKey(); host.text = ""
        engine.fieldStartConfirmation = { _ in false } // unreadable length or retained suffix
        type("teh ")
        XCTAssertEqual(host.text, "teh ")
    }

    func testExplicitUndoStillKeepsTheOriginalSpelling() {
        preferences.capitalizesAfterPeriod = false
        type("lets do ")
        XCTAssertEqual(host.text, "let's do ")
        engine.undo()
        type("that ")
        XCTAssertEqual(host.text, "lets do that ")
    }

    func testSentenceContextHonorsApprovalAndUserOverrides() {
        preferences.capitalizesAfterPeriod = false
        preferences.asksBeforeCorrecting = true
        type("do that byu this date ")
        XCTAssertEqual(host.text, "do that byu this date ")
        XCTAssertEqual(engine.pending?.replacement, "by")
        engine.approve()
        XCTAssertEqual(host.text, "do that by this date ")

        for kind in ["ignored", "custom", "contextOff"] {
            engine.invalidate(); host.text = ""
            preferences.asksBeforeCorrecting = false
            preferences.ignoredWords = kind == "ignored" ? ["byu"] : []
            preferences.customCorrections = kind == "custom" ? ["byu": "BYU"] : [:]
            preferences.checksContext = kind != "contextOff"
            type("do that byu this date ")
            XCTAssertEqual(host.text, kind == "custom" ? "do that BYU this date " : "do that byu this date ", kind)
        }
    }

    // MARK: Fix 1 — completed-token casing after the immediate capital

    func testCanceledReconciliationRetriesWithFollowingTextIntact() throws {
        for (tail, expected) in [("ithub ", "GitHub n"), ("Phone ", "iPhone n")] {
            engine.invalidate(); host.text = ""
            let initialCount = engine.correctionCount
            let host = self.host!
            engine.editTransport = { proposal, plan, completion in completion(host.apply(proposal, plan)) }
            type(tail == "ithub " ? "g" : "i")
            var canceled: ((String?) -> Void)?
            engine.editTransport = { _, _, completion in canceled = completion }
            type(tail)
            let completion = try XCTUnwrap(canceled)
            // A physical key arrives after the proposal but before it posts. Defer the
            // cancellation callback until the key has invalidated the old snapshot.
            host.text += "n"
            engine.debugTypeKey("n")
            engine.editTransport = { proposal, plan, completion in completion(host.apply(proposal, plan)) }
            let delivered = expectation(description: "unposted cancellation")
            DispatchQueue.main.async { completion(nil); delivered.fulfill() }
            wait(for: [delivered], timeout: 1)
            engine.processBoundaries(using: host.snapshot())
            XCTAssertEqual(host.text, expected)
            XCTAssertEqual(engine.correctionCount, initialCount + 2)
        }
    }

    func testMixedCaseCustomReplacementPrecedesCanonicalCasing() {
        preferences.customCorrections = ["iphone": "my phone"]
        type("i"); type("Phone ")
        XCTAssertEqual(host.text, "my phone ")
        engine.undo()
        XCTAssertEqual(host.text, "iPhone ")
    }

    func testMixedCaseCustomReplacementHonorsApprovalIgnoredWordsAndCasingOff() {
        preferences.customCorrections = ["iphone": "my phone"]
        type("i")
        preferences.asksBeforeCorrecting = true
        type("Phone ")
        XCTAssertEqual(host.text, "IPhone ")
        XCTAssertEqual(engine.pending?.replacement, "my phone")
        engine.approve()
        XCTAssertEqual(host.text, "my phone ")

        engine.invalidate(); host.text = ""
        preferences.asksBeforeCorrecting = false
        preferences.normalizesProductNames = false
        type("i"); type("Phone ")
        XCTAssertEqual(host.text, "my phone ")

        engine.invalidate(); host.text = ""
        preferences.ignoredWords = ["iphone"]
        type("i"); type("Phone ")
        XCTAssertEqual(host.text, "IPhone ")
    }

    func testCanceledReconciliationStopsAfterThreeUnpostedAttempts() {
        type("g")
        var attempts = 0
        engine.editTransport = { _, _, completion in attempts += 1; completion(nil) }
        type("ithub ")
        for _ in 0..<5 { engine.processBoundaries(using: host.snapshot()) }
        XCTAssertEqual(attempts, 3)
        XCTAssertEqual(host.text, "Github ")
        XCTAssertEqual(engine.correctionCount, 1)
    }

    func testPostedReconciliationWithFailedVerificationNeverReplays() {
        type("i")
        let host = self.host!
        var attempts = 0
        engine.editTransport = { proposal, plan, completion in
            attempts += 1
            _ = host.apply(proposal, plan)
            completion("unconfirmed host text")
        }
        type("Phone ")
        for _ in 0..<3 { engine.processBoundaries(using: host.snapshot()) }
        XCTAssertEqual(host.text, "iPhone ")
        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(engine.status, "Editor did not confirm correction")
    }

    func testDelayedCancellationAfterFocusResetDoesNotReviveOldOccurrence() throws {
        type("i")
        var canceled: ((String?) -> Void)?
        engine.editTransport = { _, _, completion in canceled = completion }
        type("Phone ")
        let completion = try XCTUnwrap(canceled)
        engine.invalidate()
        let host = self.host!
        engine.editTransport = { proposal, plan, completion in completion(host.apply(proposal, plan)) }
        completion(nil)
        type("next ")
        XCTAssertEqual(host.text, "IPhone next ")
    }

    func testFirstLetterCapitalIsReconciledWithProductCasing() {
        type("g")
        XCTAssertEqual(host.text, "G")
        type("ithub ")
        XCTAssertEqual(host.text, "GitHub ")
        XCTAssertEqual(engine.correctionCount, 2)
        engine.undo()
        XCTAssertEqual(host.text, "github ", "undo restores what was typed, not the intermediate capital")
    }

    func testLowercaseIphoneAndCanonicalMixedCaseFinishAsIphone() {
        type("i")
        XCTAssertEqual(host.text, "I")
        type("phone ")
        XCTAssertEqual(host.text, "iPhone ")
        // Typed with its internal capital: our capital is undone, nothing else changes.
        engine.invalidate(); host.text = ""
        type("i")
        type("Phone ")
        XCTAssertEqual(host.text, "iPhone ")
        engine.invalidate(); host.text = ""
        type("m")
        type("acos ")
        XCTAssertEqual(host.text, "macOS ")
    }

    func testOrdinaryWordsExpansionsAndRepairsKeepTheirBehavior() {
        type("h")
        type("ello world ")
        XCTAssertEqual(host.text, "Hello world ")
        XCTAssertEqual(engine.correctionCount, 1, "a plain word is capitalized once, never re-edited")
        engine.invalidate(); host.text = ""
        type("i")
        type("dk ")
        XCTAssertEqual(host.text, "I don't know ")
        engine.invalidate(); host.text = ""
        type("o")
        type("dnt do that ")
        XCTAssertEqual(host.text, "Don't do that ")
        engine.invalidate(); host.text = ""
        type("t")
        type("eh ")
        XCTAssertEqual(host.text, "The ")
    }

    func testUserVocabularyAndTogglesWin() {
        preferences.customCorrections = ["github": "GitHub Inc"]
        type("g"); type("ithub ")
        XCTAssertEqual(host.text, "GitHub Inc ")
        preferences.customCorrections = [:]
        preferences.ignoredWords = ["github"]
        engine.invalidate(); host.text = ""
        type("g"); type("ithub ")
        XCTAssertEqual(host.text, "Github ", "an ignored word is left as typed apart from the sentence capital")
        preferences.ignoredWords = []
        preferences.normalizesProductNames = false
        engine.invalidate(); host.text = ""
        type("g"); type("ithub ")
        XCTAssertEqual(host.text, "Github ", "product casing off: only the sentence capital applies")
        engine.invalidate(); host.text = ""
        type("i"); type("Phone ")
        XCTAssertEqual(host.text, "IPhone ", "product casing off: the typed internal capital is not treated as canonical")
        preferences.normalizesProductNames = true
        preferences.capitalizesAfterPeriod = false
        engine.invalidate(); host.text = ""
        type("g"); type("ithub ")
        XCTAssertEqual(host.text, "GitHub ", "capitalization off: no immediate edit, casing still applies at the delimiter")
    }

    func testExplicitCapitalizationUndoWinsAndCausesNoLoop() {
        type("g")
        XCTAssertEqual(host.text, "G")
        // Explicit Undo rejects capitalization; deleting the whole attempt instead starts fresh.
        engine.undo()
        XCTAssertEqual(host.text, "g")
        type("ithub ")
        XCTAssertEqual(host.text, "github ")
        type("is here ")
        XCTAssertEqual(host.text, "github is here ")
        XCTAssertEqual(engine.correctionCount, 0)
    }

    // MARK: Fix 2 — undo after continued typing

    func testUndoImmediatelyAfterFirstLetter() {
        type("h")
        XCTAssertEqual(host.text, "H")
        engine.undo()
        XCTAssertEqual(host.text, "h")
        XCTAssertEqual(engine.status, "Correction undone")
        type("ello ")
        XCTAssertEqual(host.text, "hello ", "the undone capital is not reapplied at the delimiter")
    }

    func testUndoAfterFinishingTheWordAndTheSentence() {
        type("h"); type("ello")
        XCTAssertEqual(host.text, "Hello")
        engine.undo()
        XCTAssertEqual(host.text, "hello")
        engine.invalidate(); host.text = ""
        type("h"); type("ello world")
        XCTAssertEqual(host.text, "Hello world")
        engine.undo()
        XCTAssertEqual(host.text, "hello world")
        type(" again ")
        XCTAssertEqual(host.text, "hello world again ")
    }

    func testUndoAfterFastTypingRecasedMoreThanOneLetter() {
        typeFast("he")
        XCTAssertEqual(host.text, "He")
        type("llo world")
        engine.undo()
        XCTAssertEqual(host.text, "hello world")
    }

    func testUndoWithLeadingQuoteAndFollowingPunctuation() {
        type("\"h")
        XCTAssertEqual(host.text, "\"H")
        type("ello,\" she said")
        engine.undo()
        XCTAssertEqual(host.text, "\"hello,\" she said")
    }

    func testUndoFailsSafelyWhenTextChangedOrContinuationIsUnsupported() {
        type("h"); type("ello")
        host.text = "Xello"                      // the span itself changed
        engine.undo()
        XCTAssertEqual(host.text, "Xello")
        XCTAssertTrue(engine.status.hasPrefix("Undo unavailable"), engine.status)
        engine.invalidate(); host.text = ""
        type("h")
        host.text = "Héllo"                      // non-ASCII continuation: no deletion plan
        engine.undo()
        XCTAssertEqual(host.text, "Héllo")
        XCTAssertNotEqual(engine.status, "Correction undone")
        engine.invalidate(); host.text = ""
        type("h"); type("ello")
        host.isTextArea = false
        engine.snapshotProvider = { nil }       // focus moved: no fresh read
        engine.undo()
        XCTAssertEqual(host.text, "Hello")
        XCTAssertTrue(engine.status.hasPrefix("Undo unavailable"), engine.status)
    }

    func testOrdinarySpellingAndExpansionUndoAreUnchanged() {
        engine.fieldStartConfirmation = { _ in false }
        type("teh next")
        XCTAssertEqual(host.text, "the next")
        engine.undo()
        XCTAssertEqual(host.text, "teh next")
        engine.invalidate(); host.text = ""
        type("say idk now")
        XCTAssertEqual(host.text, "say I don't know now")
        engine.undo()
        XCTAssertEqual(host.text, "say idk now")
    }

    // MARK: Fix 3 — Ask Before Correcting

    func testApprovalModeNeverEditsBeforeApproval() {
        preferences.asksBeforeCorrecting = true
        type("h")
        XCTAssertEqual(host.text, "h")
        XCTAssertEqual(engine.pending?.replacement, "H")
        XCTAssertEqual(engine.status, "Suggestion ready")
        // Continued typing: the proposal is gone, the completed word is offered instead.
        engine.invalidate(); host.text = ""
        type("h")
        host.text += "e"; engine.debugAppendKeys("e")
        XCTAssertNotNil(engine.pending, "pending is cleared by the key path, which the test harness bypasses")
        engine.processBoundaries(using: host.snapshot())
        type("llo ")
        XCTAssertEqual(host.text, "hello ")
        XCTAssertEqual(engine.pending?.replacement, "Hello")
        engine.approve()
        XCTAssertEqual(host.text, "Hello ")
    }

    func testApprovedFirstLetterRevalidatesCurrentText() {
        preferences.asksBeforeCorrecting = true
        type("h")
        XCTAssertEqual(engine.pending?.replacement, "H")
        engine.approve()
        XCTAssertEqual(host.text, "H")
        XCTAssertNil(engine.pending)
        // A stale proposal (text changed under it) is refused by the transport's revalidation.
        engine.invalidate(); host.text = ""
        type("h")
        host.text = "hx"
        engine.approve()
        XCTAssertEqual(host.text, "hx")
    }

    func testAutomaticModeStillEditsAndSettingsSwitchesClearProposals() {
        preferences.asksBeforeCorrecting = true
        type("h")
        XCTAssertNotNil(engine.pending)
        preferences.asksBeforeCorrecting = false
        engine.refresh()
        XCTAssertNil(engine.pending)
        XCTAssertFalse(preferences.asksBeforeCorrecting)
        XCTAssertTrue(preferences.capitalizesAfterPeriod)
        host.text = ""
        type("h")
        XCTAssertEqual(host.text, "H")
        preferences.capitalizesAfterPeriod = false
        engine.refresh(); host.text = ""
        type("h")
        XCTAssertEqual(host.text, "h")
        XCTAssertNil(engine.pending)
    }
}
