import XCTest
import AppKit
import AutoCorrectCore
@testable import AutoCorrect

/// Orchestration of sentence suggestions through the real engine with a deterministic analyzer
/// double: triggers, validation, stale and out-of-order results, dismissal, Apply through the
/// guarded transport, Undo, settings, unavailable or failing analyzers, and the interaction with
/// automatic spelling. A passing test here says nothing about language accuracy.
final class SentenceAssistantTests: XCTestCase {
    final class FakeAnalyzer: SentenceAnalyzer {
        var availability: SentenceAnalyzerAvailability = .onDeviceModel("fake")
        var responses: [String: [ProposedEdit]] = [:]
        var failure: Error?
        private(set) var received: [String] = []
        /// When true, analyses wait until the test resumes them (in any order).
        var hold = false
        private var pending: [(String, CheckedContinuation<[ProposedEdit], Error>)] = []
        private let lock = NSLock()

        func analyze(sentence: String) async throws -> [ProposedEdit] {
            lock.lock(); received.append(sentence); let holdNow = hold; lock.unlock()
            if let failure { throw failure }
            if holdNow {
                return try await withCheckedThrowingContinuation { continuation in
                    lock.lock(); pending.append((sentence, continuation)); lock.unlock()
                }
            }
            return responses[sentence] ?? []
        }
        /// Resumes the held analysis for `sentence` with the scripted response.
        func resume(_ sentence: String) {
            lock.lock()
            guard let index = pending.firstIndex(where: { $0.0 == sentence }) else { lock.unlock(); return }
            let (_, continuation) = pending.remove(at: index)
            let response = responses[sentence] ?? []
            lock.unlock()
            continuation.resume(returning: response)
        }
        var pendingSentences: [String] { lock.lock(); defer { lock.unlock() }; return pending.map(\.0) }
    }

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
        func read(_ range: NSRange) -> String? {
            let ns = text as NSString
            guard range.location >= 0, NSMaxRange(range) <= ns.length else { return nil }
            return ns.substring(with: range)
        }
        func rect(_ location: Int, _ length: Int) -> CGRect { CGRect(x: 100 + 8 * CGFloat(location), y: 300, width: 8 * CGFloat(max(length, 1)), height: 16) }
        func geometry(for target: NSRange) -> CorrectionPopup.Geometry {
            let count = text.utf16.count
            return CorrectionPopup.Geometry(word: rect(target.location, target.length), lineEnd: count > 0 ? rect(count - 1, 1) : nil,
                                            caret: count > 0 ? rect(count - 1, 1) : nil, visible: CGRect(x: 0, y: 0, width: 1440, height: 900))
        }
    }

    private var suite: String!
    private var defaults: UserDefaults!
    private var preferences: Preferences!
    private var engine: CorrectionEngine!
    private var host: Host!
    private var analyzer: FakeAnalyzer!

    let sentence = "She don't like the new design."
    let fix = ProposedEdit(original: "don't", replacement: "doesn't", category: "grammar", explanation: "Subject-verb agreement")

    override func setUp() {
        suite = "SentenceAssistant.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        preferences = Preferences(defaults: defaults)
        preferences.language = "en_US"
        preferences.showsSpellingIndicators = false
        preferences.capitalizesAfterPeriod = false
        host = Host()
        analyzer = FakeAnalyzer()
        analyzer.responses[sentence] = [fix]
        engine = CorrectionEngine(preferences: preferences, analyzer: analyzer)
        engine.suppressesRendering = true
        let host = self.host!
        engine.editTransport = { proposal, plan, completion in completion(host.apply(proposal, plan)) }
        engine.snapshotProvider = { host.snapshot() }
        engine.sentenceContextReader = { host.read($0) }
        engine.popupFieldFocused = { true }
        engine.popupGeometryProvider = { host.geometry(for: $0) }
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
    /// Lets the analysis task finish and its completion reach the main queue.
    private func settle(timeout: TimeInterval = 2) {
        let deadline = Date().addingTimeInterval(timeout)
        while engine.sentences.isAnalyzing, Date() < deadline { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01)) }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
    }

    func testCompletedSentenceProducesAValidatedSuggestion() throws {
        type(sentence + " ")
        settle()
        let active = try XCTUnwrap(engine.activeSuggestion)
        XCTAssertEqual(active.original, "don't"); XCTAssertEqual(active.replacement, "doesn't")
        XCTAssertEqual(active.category, .grammar); XCTAssertEqual(active.explanation, "Subject-verb agreement")
        XCTAssertEqual(analyzer.received, [sentence])
        XCTAssertEqual(host.text, sentence + " ", "a suggestion never edits on its own")
    }

    func testAutomaticSpellingRunsFirstAndTheAnalyzerSeesTheCorrectedSentence() {
        type("teh report is ready. ")
        settle()
        XCTAssertEqual(host.text, "the report is ready. ")
        XCTAssertEqual(analyzer.received, ["the report is ready."])
    }

    func testTheSameSentenceIsAnalyzedOnce() {
        type(sentence + " ")
        settle()
        type(" ")                      // another boundary, same sentence
        engine.processBoundaries(using: host.snapshot())
        settle()
        XCTAssertEqual(analyzer.received.count, 1)
    }

    func testApplyGoesThroughTheGuardedTransportAndCanBeUndone() throws {
        type(sentence + " ")
        settle()
        let id = try XCTUnwrap(engine.activeSuggestion?.id)
        engine.applySuggestion(id: id)
        XCTAssertEqual(host.text, "She doesn't like the new design. ")
        XCTAssertNil(engine.activeSuggestion)
        XCTAssertNotNil(engine.undoRecordID, "an applied suggestion is an ordinary undoable correction")
        engine.undo()
        XCTAssertEqual(host.text, sentence + " ")
    }

    func testApplyAfterContinuedTypingPreservesTheFollowingText() throws {
        type(sentence + " ")
        settle()
        let id = try XCTUnwrap(engine.activeSuggestion?.id)
        type("Really. ")
        engine.applySuggestion(id: id)
        XCTAssertEqual(host.text, "She doesn't like the new design. Really. ")
    }

    func testApplyIsRefusedWhenTheSentenceChanged() throws {
        type(sentence + " ")
        settle()
        let id = try XCTUnwrap(engine.activeSuggestion?.id)
        host.text = "She really don't like the new design. "   // edited inside the analyzed sentence
        engine.applySuggestion(id: id)
        XCTAssertEqual(host.text, "She really don't like the new design. ", "nothing is edited when the context changed")
        XCTAssertNil(engine.activeSuggestion, "the stale suggestion is withdrawn")
    }

    func testStaleSuggestionIdIsRefused() throws {
        type(sentence + " ")
        settle()
        let id = try XCTUnwrap(engine.activeSuggestion?.id)
        engine.applySuggestion(id: UUID())
        XCTAssertEqual(host.text, sentence + " ")
        XCTAssertEqual(engine.activeSuggestion?.id, id)
    }

    func testEditingInsideTheSentenceWithdrawsTheSuggestionTypingAfterItDoesNot() throws {
        type(sentence + " ")
        settle()
        XCTAssertNotNil(engine.activeSuggestion)
        type("Next thought ")
        XCTAssertTrue(engine.sentences.revalidate(), "typing after the sentence keeps it valid")
        XCTAssertNotNil(engine.activeSuggestion)
        host.text = host.text.replacingOccurrences(of: "new design", with: "design")
        XCTAssertFalse(engine.sentences.revalidate())
        XCTAssertNil(engine.activeSuggestion)
    }

    func testOutOfOrderResultsKeepOnlyTheLatestSentence() throws {
        analyzer.hold = true
        let second = "He walk to work every day."
        analyzer.responses[second] = [ProposedEdit(original: "walk", replacement: "walks", category: "grammar", explanation: "Agreement")]
        type(sentence + " ")
        type(second + " ")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertEqual(analyzer.pendingSentences, [sentence], "the second request waits for the first to finish")
        XCTAssertTrue(engine.sentences.debugHasQueuedRequest)
        analyzer.resume(sentence)              // the older result arrives first and is obsolete
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        XCTAssertNil(engine.activeSuggestion, "a result for an earlier sentence is discarded")
        XCTAssertEqual(analyzer.pendingSentences, [second], "the queued request starts only after the first finished")
        analyzer.resume(second)
        settle()
        XCTAssertEqual(engine.activeSuggestion?.replacement, "walks")
    }

    func testDismissedSuggestionDoesNotReappearForUnchangedText() throws {
        type(sentence + " ")
        settle()
        let id = try XCTUnwrap(engine.activeSuggestion?.id)
        engine.dismissSuggestion(id: id)
        XCTAssertNil(engine.activeSuggestion)
        engine.debugReanalyze(using: host.snapshot())
        settle()
        XCTAssertNil(engine.activeSuggestion, "the same suggestion for the same unchanged sentence stays dismissed")
        // The sentence changes: the dismissal no longer applies.
        host.text = ""; engine.invalidate()
        let changed = "Well, she don't like the new design."
        analyzer.responses[changed] = [fix]
        type(changed + " ")
        settle()
        XCTAssertNotNil(engine.activeSuggestion)
    }

    func testCategorySwitchesFilterAndDisable() {
        analyzer.responses[sentence] = [fix, ProposedEdit(original: "like the new", replacement: "like, the new", category: "punctuation", explanation: "Comma")]
        preferences.grammarSuggestions = false
        type(sentence + " ")
        settle()
        XCTAssertEqual(engine.activeSuggestion?.category, .punctuation)
        engine.invalidate(); host.text = ""
        preferences.grammarSuggestions = false; preferences.punctuationSuggestions = false
        type(sentence + " ")
        settle()
        XCTAssertNil(engine.activeSuggestion)
        XCTAssertEqual(analyzer.received.count, 1, "no analysis runs while both switches are off")
        XCTAssertEqual(engine.sentences.availabilityText, "Sentence suggestions: off")
    }

    func testAnalyzerFailureLeavesTheTypingEngineWorking() {
        analyzer.failure = NSError(domain: "fake", code: 1)
        type(sentence + " ")
        settle()
        XCTAssertNil(engine.activeSuggestion)
        XCTAssertTrue(engine.sentenceStatus.contains("failed"), engine.sentenceStatus)
        type("teh ")
        XCTAssertEqual(host.text, sentence + " the ", "spelling correction is unaffected")
    }

    func testUnavailableAnalyzerIsReportedHonestly() {
        analyzer.availability = .unavailable("Apple Intelligence model: deviceNotEligible")
        XCTAssertTrue(engine.sentences.availabilityText.contains("Unavailable"), engine.sentences.availabilityText)
        let limited = NativeGrammarAnalyzer(fallbackReason: "no on-device model")
        XCTAssertTrue(limited.availability.summary.hasPrefix("Limited"))
    }

    func testFocusChangeClearsTheSuggestionAndCancelsAnalysis() throws {
        analyzer.hold = true
        type(sentence + " ")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertTrue(engine.sentences.isAnalyzing)
        engine.invalidate()
        XCTAssertFalse(engine.sentences.isAnalyzing)
        analyzer.resume(sentence)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        XCTAssertNil(engine.activeSuggestion, "a result for a field that lost focus is discarded")
    }

    func testValidationDropsUnsafeModelOutputBeforeDisplay() {
        let risky = "Send 10 units to Marko today."
        analyzer.responses[risky] = [ProposedEdit(original: "Marko", replacement: "Marco", category: "grammar", explanation: "spelling"),
                                     ProposedEdit(original: "10 units", replacement: "12 units", category: "grammar", explanation: "number"),
                                     ProposedEdit(original: "Send", replacement: "Do not send", category: "grammar", explanation: "polarity")]
        type(risky + " ")
        settle()
        XCTAssertNil(engine.activeSuggestion)
        XCTAssertTrue(engine.sentenceStatus.contains("did not pass validation"), engine.sentenceStatus)
    }

    // MARK: Suggestion popup (headless)

    func testSuggestionPopupShowsApplyBoundToTheSuggestionAndAStaleActionIsRefused() throws {
        engine.debugInstallHeadlessPopup()
        engine.suppressesRendering = false
        type(sentence + " ")
        settle()
        engine.debugRenderSuggestion()
        let popup = engine.debugSuggestionPopup
        XCTAssertTrue(popup.isShown)
        XCTAssertEqual(popup.content?.kind, .suggestion)
        XCTAssertEqual(popup.content?.detail, "Subject-verb agreement")
        XCTAssertEqual(popup.mode, .capsule, "suggestions are shown for review, with Apply and dismiss")
        let old = try XCTUnwrap(popup.lastActions)
        // A newer suggestion replaces it before the old Apply is clicked.
        host.text = ""; engine.invalidate()
        let second = "He walk to work every day."
        analyzer.responses[second] = [ProposedEdit(original: "walk", replacement: "walks", category: "grammar", explanation: "Agreement")]
        type(second + " ")
        settle()
        engine.debugRenderSuggestion()
        let new = try XCTUnwrap(popup.lastActions)
        XCTAssertNotEqual(old.id, new.id)
        old.undo()
        XCTAssertEqual(host.text, second + " ", "an old Apply never edits the newer sentence")
        new.undo()
        XCTAssertEqual(host.text, "He walks to work every day. ")
    }

    func testSuggestionPopupHidesWithoutGeometryAndTheMenuPathRemains() throws {
        engine.debugInstallHeadlessPopup()
        engine.suppressesRendering = false
        engine.popupGeometryProvider = { _ in nil }
        type(sentence + " ")
        settle()
        engine.debugRenderSuggestion()
        XCTAssertFalse(engine.debugSuggestionPopup.isShown)
        XCTAssertTrue(engine.suggestionPopupStatus.contains("menu"), engine.suggestionPopupStatus)
        let id = try XCTUnwrap(engine.activeSuggestion?.id)
        engine.applySuggestion(id: id)          // the menu action
        XCTAssertEqual(host.text, "She doesn't like the new design. ")
    }

    func testDismissFromThePopupRemembersTheDismissal() throws {
        engine.debugInstallHeadlessPopup()
        engine.suppressesRendering = false
        type(sentence + " ")
        settle()
        engine.debugRenderSuggestion()
        try XCTUnwrap(engine.debugSuggestionPopup.lastActions).dismiss()
        XCTAssertNil(engine.activeSuggestion)
        XCTAssertFalse(engine.debugSuggestionPopup.isShown)
        engine.debugReanalyze(using: host.snapshot())
        settle()
        XCTAssertNil(engine.activeSuggestion)
    }
}

// MARK: - Independent review regressions (October 5, 2026)
extension SentenceAssistantTests {
    func testReviewOneActualAnalysisAtATime() {
        analyzer.hold = true
        let second = "He walk to work every day."
        type(sentence + " ")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        type(second + " ")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertEqual(analyzer.pendingSentences.count, 1, "cancelling a Task does not wait for the analyzer to stop")
        for pending in analyzer.pendingSentences { analyzer.resume(pending) }
        settle()
    }

    func testReviewStaleInflightResultAfterDeletion() {
        analyzer.hold = true
        type(sentence + " ")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        host.text = "She doesn't like the new design"
        engine.debugTypeKey(nil, keyCode: 51)
        analyzer.resume(sentence)
        settle()
        XCTAssertNil(engine.activeSuggestion, "obsolete context must not be published into the menu")
        engine.invalidate()
    }

    func testReviewPauseWithoutTerminalPunctuation() {
        let text = "She don't like the new design"
        analyzer.responses[text] = [fix]
        host.text = text
        engine.sentences.noteTyping { self.host.snapshot() }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.5))
        settle()
        XCTAssertEqual(analyzer.received, [text], "a complete clause paused in chat needs grammar help too")
        engine.invalidate()
    }

    func testReviewIgnoredWordNotSuggested() {
        preferences.ignoredWords = ["don't"]
        type(sentence + " "); settle()
        XCTAssertNil(engine.activeSuggestion)
    }

    func testReviewFailedApplyKeepsSuggestion() throws {
        let long = "She don't " + String(repeating: "really ", count: 15) + "like the design."
        analyzer.responses[long] = [fix]
        type(long + " "); settle()
        let id = try XCTUnwrap(engine.activeSuggestion?.id)
        engine.applySuggestion(id: id)
        XCTAssertEqual(host.text, long + " ")
        XCTAssertEqual(engine.activeSuggestion?.id, id, "a refused transport must not report the suggestion applied and discard it")
        XCTAssertFalse(engine.sentenceStatus.contains("applied"))
    }
}

// MARK: - Repair-pass coverage (October 5, 2026)
extension SentenceAssistantTests {
    func testRapidTypingCoalescesToTheLatestContextWithoutAccumulatingWork() {
        analyzer.hold = true
        let second = "He walk to work every day."
        let third = "They was late again."
        analyzer.responses[third] = [ProposedEdit(original: "was", replacement: "were", category: "grammar", explanation: "Agreement")]
        type(sentence + " "); type(second + " "); type(third + " ")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertEqual(analyzer.pendingSentences, [sentence])
        analyzer.resume(sentence)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        XCTAssertEqual(analyzer.pendingSentences, [third], "only the latest eligible context was kept; the middle one was never sent")
        analyzer.resume(third)
        settle()
        XCTAssertEqual(engine.activeSuggestion?.replacement, "were")
        XCTAssertEqual(analyzer.received.count, 2)
    }

    func testFocusChangeDuringAnalysisDiscardsTheResultAndStartsNothing() {
        analyzer.hold = true
        type(sentence + " ")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        engine.invalidate()                                  // focus moved elsewhere
        analyzer.resume(sentence)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        XCTAssertNil(engine.activeSuggestion)
        XCTAssertEqual(analyzer.received.count, 1)
        XCTAssertFalse(engine.sentences.debugHasRunningRequest)
    }

    func testSettingsTurnedOffDuringAnalysisDiscardTheResult() {
        analyzer.hold = true
        type(sentence + " ")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        preferences.grammarSuggestions = false; preferences.punctuationSuggestions = false
        engine.sentenceSettingsChanged()
        analyzer.resume(sentence)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        XCTAssertNil(engine.activeSuggestion)
    }

    func testEditsDuringPendingAnalysisAreNeverPublished() {
        let variants: [(String, String)] = [
            ("subject changed", "He don't like the new design."),
            ("negation changed", "She does like the new design."),
            ("punctuation removed", "She don't like the new design"),
            ("shortened", "She don't like design."),
        ]
        for (label, edited) in variants {
            engine.invalidate(); host.text = ""
            analyzer.hold = true
            type(sentence + " ")
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
            host.text = edited + " "
            engine.debugTypeKey(nil, keyCode: 51)
            analyzer.resume(sentence)
            settle()
            XCTAssertNil(engine.activeSuggestion, label)
            XCTAssertTrue(engine.sentenceStatus.contains("discarded") || engine.sentenceStatus.contains("could not be verified") || engine.sentenceStatus.contains("analyzing"),
                          "\(label): \(engine.sentenceStatus)")
        }
    }

    func testUnverifiableContextIsNotPublished() {
        analyzer.hold = true
        type(sentence + " ")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        engine.sentenceContextReader = { _ in nil }          // Accessibility cannot read right now
        analyzer.resume(sentence)
        settle()
        XCTAssertNil(engine.activeSuggestion)
        XCTAssertTrue(engine.sentenceStatus.contains("could not be verified"), engine.sentenceStatus)
    }

    func testApplyOutcomesKeepThePendingSuggestionUntilVerified() throws {
        // Cancelled posting: the transport reports no edit.
        type(sentence + " "); settle()
        let id = try XCTUnwrap(engine.activeSuggestion?.id)
        engine.editTransport = { _, _, completion in completion(nil) }
        engine.applySuggestion(id: id)
        XCTAssertEqual(host.text, sentence + " ")
        XCTAssertEqual(engine.activeSuggestion?.id, id, "a cancelled edit keeps the suggestion")
        XCTAssertNil(engine.sentences.applying)
        XCTAssertTrue(engine.sentenceStatus.contains("edit was not made"), engine.sentenceStatus)
        // Failed verification: the host shows something else.
        engine.editTransport = { _, _, completion in completion("garbage") }
        engine.applySuggestion(id: id)
        XCTAssertEqual(engine.activeSuggestion?.id, id, "an unconfirmed edit keeps the suggestion")
        XCTAssertTrue(engine.sentenceStatus.contains("did not confirm"), engine.sentenceStatus)
        // Success through the normal transport, then Undo.
        let host = self.host!
        engine.editTransport = { proposal, plan, completion in completion(host.apply(proposal, plan)) }
        engine.applySuggestion(id: id)
        XCTAssertEqual(host.text, "She doesn't like the new design. ")
        XCTAssertNil(engine.activeSuggestion)
        XCTAssertEqual(engine.sentenceStatus, "Sentence suggestion applied")
        engine.undo()
        XCTAssertEqual(host.text, sentence + " ")
    }

    func testUnsupportedTextAfterTheSpanIsReportedNotApplied() throws {
        let emoji = "She don't like the new design 🙂."
        analyzer.responses[emoji] = [fix]
        type(emoji + " "); settle()
        let id = try XCTUnwrap(engine.activeSuggestion?.id)
        engine.applySuggestion(id: id)
        XCTAssertEqual(host.text, emoji + " ", "the keyboard plan never deletes across the emoji")
        XCTAssertEqual(engine.activeSuggestion?.id, id)
        XCTAssertTrue(engine.sentenceStatus.contains("caret position"), engine.sentenceStatus)
    }

    func testUndoingAnAppliedSuggestionDoesNotStartACycle() throws {
        type(sentence + " "); settle()
        let id = try XCTUnwrap(engine.activeSuggestion?.id)
        engine.applySuggestion(id: id)
        XCTAssertEqual(host.text, "She doesn't like the new design. ")
        engine.undo()
        XCTAssertEqual(host.text, sentence + " ")
        engine.debugReanalyze(using: host.snapshot())
        settle()
        XCTAssertNil(engine.activeSuggestion, "the undone suggestion is not proposed again for the same text")
    }

    func testOverriddenOccurrenceIsNotProposed() throws {
        // The user restored "don't" by undoing an automatic edit elsewhere; the kept occurrence is protected.
        type(sentence + " "); settle()
        let id = try XCTUnwrap(engine.activeSuggestion?.id)
        engine.applySuggestion(id: id)
        engine.undo()
        engine.invalidate(); analyzer.responses[sentence] = [fix]
        engine.noteOverride(SpellingMark(location: 4, word: "don't"))
        engine.debugReanalyze(using: host.snapshot())
        settle()
        XCTAssertNil(engine.activeSuggestion)
    }

    func testPauseAnalyzesAnUnterminatedClauseButNeverAddsAPeriod() {
        let clause = "She don't like the new design"
        analyzer.responses[clause] = [fix, ProposedEdit(original: "design", replacement: "design.", category: "punctuation", explanation: "Add a period")]
        host.text = clause
        engine.sentences.noteTyping { self.host.snapshot() }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.5))
        settle()
        XCTAssertEqual(analyzer.received, [clause])
        XCTAssertEqual(engine.activeSuggestion?.replacement, "doesn't")
        XCTAssertNotEqual(engine.activeSuggestion?.replacement, "design.", "a pause never produces a period")
    }

    func testShortFragmentsAndTruncatedWindowsAreNotAnalyzedOnPause() {
        host.text = "lol ok"
        engine.sentences.noteTyping { self.host.snapshot() }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.5))
        settle()
        XCTAssertEqual(analyzer.received, [], "three words or fewer are not analyzed")
        let truncated = AccessibilityText.Snapshot(element: host.element, pid: getpid(), text: "like the new design here", windowStart: 40,
                                                   caret: 64, physicalKeyCount: 0, isTextArea: true)
        engine.sentences.consider(snapshot: truncated, reason: "pause")
        settle()
        XCTAssertEqual(analyzer.received, [], "a clause starting at a mid-document window edge may be truncated")
    }

    func testSentencesEndingWithQuotesOrParenthesesAreEligibleAtBoundaries() {
        let quoted = "She said \"it don't matter.\""
        let parenthesized = "He walk to work (every day)."
        analyzer.responses[quoted] = []
        analyzer.responses[parenthesized] = []
        type(quoted + " "); settle()
        type(parenthesized + " "); settle()
        XCTAssertEqual(analyzer.received, [quoted, parenthesized])
    }

    func testContinuedPausedClauseCannotPublishOldContext() {
        let clause = "She don't like the new design"
        analyzer.responses[clause] = [fix]
        analyzer.hold = true
        host.text = clause
        engine.sentences.consider(snapshot: host.snapshot(), reason: "pause")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        host.text += " or its colors"
        analyzer.resume(clause)
        settle()
        XCTAssertNil(engine.activeSuggestion, "the old clause is only a prefix of the current context")
    }

    func testContinuedPausedClauseCannotApplyOldSuggestion() throws {
        let clause = "She don't like the new design"
        analyzer.responses[clause] = [fix]
        host.text = clause
        engine.sentences.consider(snapshot: host.snapshot(), reason: "pause")
        settle()
        let id = try XCTUnwrap(engine.activeSuggestion?.id)
        host.text += " or its colors"
        engine.applySuggestion(id: id)
        XCTAssertEqual(host.text, clause + " or its colors")
        XCTAssertNil(engine.activeSuggestion)
    }

    func testAnalysisCompletionCannotReplaceAnApplyingSuggestion() throws {
        type(sentence + " "); settle()
        let id = try XCTUnwrap(engine.activeSuggestion?.id)
        analyzer.hold = true
        let second = "He walk to work every day."
        analyzer.responses[second] = [ProposedEdit(original: "walk", replacement: "walks", category: "grammar", explanation: "Agreement")]
        type(second + " ")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        var finishEdit: (() -> Void)?
        let host = self.host!
        engine.editTransport = { proposal, plan, completion in
            finishEdit = { completion(host.apply(proposal, plan)) }
        }
        engine.applySuggestion(id: id)
        XCTAssertEqual(engine.sentences.applying, id)
        analyzer.resume(second); settle()
        XCTAssertEqual(engine.activeSuggestion?.id, id)
        try XCTUnwrap(finishEdit)()
        XCTAssertNil(engine.activeSuggestion)
        XCTAssertEqual(engine.sentenceStatus, "Sentence suggestion applied")
        XCTAssertEqual(host.text, "She doesn't like the new design. " + second + " ")
    }
}
