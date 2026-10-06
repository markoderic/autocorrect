import AppKit
import AutoCorrectCore

final class CorrectionEngine {
    struct Proposal {
        let snapshot: AccessibilityText.Snapshot
        let range: NSRange
        let original: String
        let replacement: String
        let created: Date
        /// What the user actually typed for this span when `original` already carries a
        /// capital that AutoCorrect introduced (so undo restores the typed text).
        var typed: String? = nil
        /// Immediate capitalization of the field's first word (records the occurrence).
        var capitalizesFieldStart = false
    }
    /// The one occurrence in the focused field whose first letter AutoCorrect capitalized,
    /// so the completed token can be judged as typed (`Github` → `GitHub`, `IPhone` →
    /// `iPhone`) instead of as a deliberately capitalized name. Field-scoped, one record.
    private struct AutoCapital {
        let field: UUID
        let location: Int
        let typed: String
        let replacement: String
    }
    private var autoCapital: AutoCapital?
    let preferences: Preferences
    var onChange: (() -> Void)?
    private(set) var pending: Proposal?
    private(set) var undoProposal: Proposal?
    private(set) var flaggedWord: String?
    private(set) var correctionCount = 0
    private(set) var status = "Ready"
    private var generation: UInt64 = 0
    private var sessionEpoch: UInt64 = 0
    private var work: DispatchWorkItem?
    private var backlog = CompletedWordBacklog()
    private var inFlight = false
    private var readAttempts = 0
    private var undoAnchor: CorrectionUndoAnchor?
    /// Identity of the one correction that can currently be undone. Every popup action is bound
    /// to this id; an action created for an older record is refused.
    private(set) var undoRecordID: UUID?
    private var popup = CorrectionPopup()
    private var popupExpiryWork: DispatchWorkItem?
    private var popupMode: CorrectionPopup.Mode = .dot
    private var popupDismissedID: UUID?
    private(set) var popupStatus = "Popup: none"
    /// Sentence-level grammar and punctuation suggestions (Suggest only; never automatic).
    let sentences: SentenceAssistant
    private var suggestionPopup = CorrectionPopup()
    private var suggestionPopupMode: CorrectionPopup.Mode = .capsule
    private(set) var suggestionPopupStatus = ""
    var activeSuggestion: SentenceSuggestion? { sentences.active?.suggestion }
    var sentenceStatus: String { sentences.status }
    private var attemptedBoundaries: [UInt64: Int] = [:]
    private var manualRewrites = ManualRewriteProtection()
    // A deletion may empty the editor. The next typing snapshot must prove a new field
    // attempt before old occurrence-level rejection records are discarded.
    private var pendingDeletionRestart = false
    private var rewriteField: (pid: pid_t, element: AXUIElement, id: UUID)?
    // Persistent spelling marks for the focused field: the model, the occurrences the user
    // deliberately kept, the field they belong to, and the debounced scan/render work.
    private var markSet = SpellingMarkSet()
    private var overridden = SpellingMarkSet()
    private var markField: (pid: pid_t, element: AXUIElement)?
    private var fieldObserver: FieldObserver?
    private var scanWork: DispatchWorkItem?
    private var renderWork: DispatchWorkItem?
    private(set) var underlineStatus = "Underlines: none"
    var marks: [SpellingMark] { markSet.marks }
    /// Tests inspect the model without a real field; nothing is drawn.
    var suppressesRendering = false
    /// Field-start capitalization evidence for the current typing session. `unknown` until
    /// the first word of a possibly empty prose area is checked; `confirmed` once the field's
    /// reported length proves the snapshot holds the whole field; `finished` when there is
    /// nothing to capitalize this session (existing text, another control, a capital, an
    /// ignored word or a deliberate lowercase retype).
    private enum FieldStart { case unknown, confirmed, finished }
    private var fieldStart = FieldStart.unknown
    private var fieldStartAttempts = 0
    #if DEBUG
    var nativeAssessmentObserver: ((String, Bool, String?, [String]) -> Void)?
    /// Test hook: feeds keystrokes to the boundary queue without the event tap.
    func debugAppendKeys(_ text: String) { for character in text { backlog.append(String(character)) } }
    /// Test hook: field-start evidence without Accessibility (nil uses the real read).
    var fieldStartConfirmation: ((AccessibilityText.Snapshot) -> Bool)?
    /// Test hook: the last edit handed to the keyboard path, whether or not it could post.
    var lastProposal: Proposal?
    /// Test seam standing in for the keyboard transport plus the host editor: receives the
    /// prepared plan and completes with the host's verification text after applying it,
    /// or nil if no edit posted. Completion may be delayed to exercise cancellation while
    /// typing continues. Unposted attempts use the production bounded retry path.
    var editTransport: ((Proposal, KeyboardReplacementPlan, @escaping (String?) -> Void) -> Void)?
    /// Deliver a printable key through the real session/proposal invalidation path.
    func debugTypeKey(_ text: String) { key(text, flags: [], keyCode: 0) }
    /// Test hooks for the popup path: a headless popup (placement and bindings without windows),
    /// injected geometry, the record's context text and the focus check.
    var popupGeometryProvider: ((NSRange) -> CorrectionPopup.Geometry?)?
    var undoContextReader: ((NSRange) -> String?)?
    var popupFieldFocused: (() -> Bool)?
    var debugPopup: CorrectionPopup { popup }
    var sentenceContextReader: ((NSRange) -> String?)?
    var debugSuggestionPopup: CorrectionPopup { suggestionPopup }
    func debugRenderSuggestion() { renderSuggestion() }
    /// Test hook: analyze the last complete sentence of this snapshot now, even if it was analyzed before.
    func debugReanalyze(using snapshot: AccessibilityText.Snapshot) { sentences.debugForgetLastAnalyzed(); sentences.consider(snapshot: snapshot, reason: "test") }
    func debugInstallHeadlessPopup() {
        popup = CorrectionPopup(makesWindows: false)
        wirePopup()
        suggestionPopup = CorrectionPopup(makesWindows: false)
        wireSuggestionPopup()
    }
    func debugRenderPopup() { renderPopup() }
    /// Test hook: ages the current undo record so expiry can be exercised without waiting.
    func debugBackdateUndoRecord(seconds: TimeInterval) {
        guard let saved = undoProposal else { return }
        undoProposal = Proposal(snapshot: saved.snapshot, range: saved.range, original: saved.original,
                                replacement: saved.replacement, created: saved.created.addingTimeInterval(-seconds),
                                typed: saved.typed, capitalizesFieldStart: saved.capitalizesFieldStart)
    }
    /// Test seam for the fresh read that undo takes (nil uses Accessibility).
    var snapshotProvider: (() -> AccessibilityText.Snapshot?)?
    /// Test hook: what a Backspace or navigation key does to the typing session.
    func debugDeleteKey() { key(nil, flags: [], keyCode: 51) }
    /// Test hook: an arbitrary key (Return, arrows) exactly as the event tap reports it.
    func debugTypeKey(_ text: String?, keyCode: Int64) { key(text, flags: [], keyCode: keyCode) }
    func debugNoteManualEdit() {
        manualRewrites.noteManualEdit(now: ProcessInfo.processInfo.systemUptime)
        resetTyping()
    }
    #endif
    private struct Assessment {
        let misspelled: Bool
        let replacement: String?
        let automatic: Bool
    }
    private var cache: [String: Assessment] = [:]
    private let indicator = SpellingIndicator()
    private let monitor = KeyboardMonitor()
    var isRunning: Bool { monitor.isRunning }

    init(preferences: Preferences, analyzer: SentenceAnalyzer? = nil) {
        self.preferences = preferences
        sentences = SentenceAssistant(analyzer: analyzer ?? SentenceAnalyzers.preferred())
        sentences.grammarEnabled = { preferences.grammarSuggestions }
        sentences.punctuationEnabled = { preferences.punctuationSuggestions }
        sentences.onChange = { [weak self] in self?.onChange?(); self?.scheduleRender(delay: 0) }
        sentences.contextReader = { [weak self] field, range in self?.readSentenceContext(field: field, range: range) }
        sentences.snapshotReader = { [weak self] _ in self?.analysisSnapshot() }
        sentences.fieldFocused = { [weak self] field in self?.isFieldFocused(field) ?? false }
        sentences.isSpanProtected = { [weak self] _, location, original in self?.isSuggestionSpanProtected(location: location, original: original) ?? true }
        monitor.onKey = { [weak self] text, flags, key in self?.key(text, flags: flags, keyCode: key) }
        monitor.onMouse = { [weak self] type, location in self?.handleMouse(type: type, location: location) }
        monitor.onUndo = { [weak self] in
            guard let self, self.undoProposal != nil, !self.inFlight else { return false }
            DispatchQueue.main.async { self.undo() }
            return true
        }
        monitor.onShowPopup = { [weak self] in
            guard let self, self.preferences.showsCorrectionPopup, self.undoRecordID != nil else { return false }
            DispatchQueue.main.async { self.showPopupForLatestCorrection() }
            return true
        }
        wirePopup()
        wireSuggestionPopup()
    }

    /// Bounded read of a field at an absolute range, for sentence verification (test seam first).
    private func readSentenceContext(field: SentenceAssistant.Field, range: NSRange) -> String? {
        #if DEBUG
        if let sentenceContextReader { return sentenceContextReader(range) }
        #endif
        return AccessibilityText.substring(field.element, range: CFRange(location: range.location, length: range.length))
    }

    private func isFieldFocused(_ field: SentenceAssistant.Field) -> Bool {
        #if DEBUG
        if let popupFieldFocused { return popupFieldFocused() }
        #endif
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == field.pid,
              let current = AccessibilityText.focusedElement(pid: field.pid) else { return false }
        return CFEqual(current, field.element)
    }

    /// Ignored words and occurrences the user deliberately kept are never proposed for change.
    private func isSuggestionSpanProtected(location: Int, original: String) -> Bool {
        let words = original.split(whereSeparator: { !$0.isLetter && $0 != "'" && $0 != "’" }).map { UserDictionary.normalizedKey(String($0)) }
        if words.contains(where: { preferences.ignoredWords.contains($0) }) { return true }
        if overridden.marks.contains(where: { $0.location >= location && $0.location < location + original.utf16.count }) { return true }
        return false
    }

    private func wireSuggestionPopup() {
        suggestionPopup.onUndo = { [weak self] id in self?.applySuggestion(id: id) }
        suggestionPopup.onDismiss = { [weak self] id in self?.dismissSuggestion(id: id) }
        suggestionPopup.onExpand = { [weak self] id in
            guard let self, self.activeSuggestion?.id == id else { return }
            self.suggestionPopupMode = .capsule
            self.renderSuggestion()
        }
        suggestionPopup.onCollapsed = { [weak self] id in
            guard let self, self.activeSuggestion?.id == id else { return }
            self.suggestionPopupMode = .dot
            self.renderSuggestion()
        }
    }

    /// A bounded snapshot for sentence analysis after a typing pause: the test seam, or the
    /// focused field of the frontmost, non-excluded app. Nil when nothing can be read.
    private func analysisSnapshot() -> AccessibilityText.Snapshot? {
        #if DEBUG
        if let snapshotProvider { return snapshotProvider() }
        #endif
        guard preferences.enabled, AXIsProcessTrusted(), !inFlight,
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let bundleID = app.bundleIdentifier, !preferences.excludedApps.contains(bundleID) else { return nil }
        return AccessibilityText.snapshot(pid: app.processIdentifier)
    }

    /// Applies the active suggestion through the same guarded keyboard transport as every
    /// correction, after re-reading the field and confirming the exact analyzed sentence and span.
    func applySuggestion(id: UUID) {
        guard let current = sentences.active, current.suggestion.id == id else {
            RuntimeDiagnostics.record("suggestion: stale apply refused")
            status = "That suggestion is no longer current; nothing changed"
            onChange?()
            return
        }
        guard !inFlight else { status = "Busy with another edit; try again"; onChange?(); return }
        guard sentences.revalidate() else {
            status = "Suggestion unavailable: its full context could not be verified"
            suggestionPopup.hide()
            onChange?()
            return
        }
        var fresh: AccessibilityText.Snapshot?
        #if DEBUG
        if let snapshotProvider { fresh = snapshotProvider() }
        #endif
        if fresh == nil, NSWorkspace.shared.frontmostApplication?.processIdentifier == current.field.pid {
            fresh = AccessibilityText.snapshot(pid: current.field.pid)
        }
        guard let snapshot = fresh, snapshot.pid == current.field.pid, CFEqual(snapshot.element, current.field.element) else {
            status = "Suggestion unavailable: return to the field it was made for"
            onChange?()
            return
        }
        let ns = snapshot.text as NSString
        let sentenceLocal = current.sentenceLocation - snapshot.windowStart
        let sentenceLength = current.suggestion.sentence.utf16.count
        guard sentenceLocal >= 0, sentenceLocal + sentenceLength <= ns.length,
              ns.substring(with: NSRange(location: sentenceLocal, length: sentenceLength)) == current.suggestion.sentence else {
            sentences.withdraw(reason: "sentence changed")
            suggestionPopup.clear()
            status = "Suggestion withdrawn: the sentence changed"
            onChange?()
            return
        }
        let span = NSRange(location: sentenceLocal + current.suggestion.range.location, length: current.suggestion.range.length)
        guard ns.substring(with: span) == current.suggestion.original else {
            sentences.withdraw(reason: "span changed")
            suggestionPopup.clear()
            onChange?()
            return
        }
        guard sentences.applyStarted(id: id) != nil else { return }
        suggestionPopup.hide()
        applyingSuggestionID = id
        perform(Proposal(snapshot: snapshot, range: span, original: current.suggestion.original,
                         replacement: current.suggestion.replacement, created: Date()), isUndo: false, andIgnore: false)
    }

    /// The id of the suggestion whose edit is in flight, so the transport's outcome reaches it.
    private var applyingSuggestionID: UUID?

    private func suggestionApplyFailed(_ reason: String) {
        guard let id = applyingSuggestionID else { return }
        applyingSuggestionID = nil
        sentences.applyFailed(id: id, reason: reason)
        scheduleRender(delay: 0)
    }

    func dismissSuggestion(id: UUID) {
        guard sentences.dismiss(id: id) else { return }
        suggestionPopup.clear()
        suggestionPopupStatus = ""
        onChange?()
    }

    /// Grammar or punctuation switches changed: drop current analysis and redraw.
    func sentenceSettingsChanged() {
        sentences.invalidate()
        suggestionPopup.clear()
        suggestionPopupStatus = ""
        onChange?()
    }

    private func wirePopup() {
        popup.onUndo = { [weak self] id in self?.undo(recordID: id) }
        popup.onDismiss = { [weak self] id in
            guard let self, id == self.undoRecordID else { return }
            self.popupDismissedID = id
            self.popupStatus = "Popup: dismissed for this correction"
            self.onChange?()
        }
        popup.onExpand = { [weak self] id in
            guard let self, id == self.undoRecordID else { return }
            self.popupMode = .capsule
            self.renderPopup()
        }
        popup.onCollapsed = { [weak self] id in
            guard let self, id == self.undoRecordID else { return }
            self.popupMode = .dot
            self.renderPopup()
        }
    }

    /// A system mouse-down or scroll. A click that lands on the popup belongs to the popup's own
    /// controls: it must not reset the typing session or hide the popup before the button acts.
    /// Everything else (editor clicks, scrolling) invalidates typing state, hides the overlays
    /// and redraws them once the view settles.
    func handleMouse(type: CGEventType, location: CGPoint) {
        if type != .scrollWheel, popup.contains(quartzPoint: location) || suggestionPopup.contains(quartzPoint: location) {
            RuntimeDiagnostics.record("mouse inside popup")
            return
        }
        pendingDeletionRestart = false
        manualRewrites.noteManualEdit(now: ProcessInfo.processInfo.systemUptime)
        resetTyping()
        indicator.hide()
        // A click elsewhere or a scroll quiets the capsules to their indicators.
        if popupMode == .capsule { popupMode = .dot }
        popup.hide()
        if suggestionPopupMode == .capsule { suggestionPopupMode = .dot }
        suggestionPopup.hide()
        // Clicks and scrolling move text under the marks; redraw once the view settles,
        // and scan the region that may have scrolled into view.
        scheduleRender(delay: 250)
        scheduleScan(delay: 450)
    }

    /// Control-Option-Command-/ or the menu: reopen the capsule for the latest correction.
    func showPopupForLatestCorrection() {
        guard preferences.showsCorrectionPopup, undoRecordID != nil else { return }
        popupDismissedID = nil
        popupMode = .capsule
        renderPopup()
    }

    /// The popup setting changed: redraw or hide without dropping the correction record.
    func popupSettingChanged() {
        if !preferences.showsCorrectionPopup { popup.hide(); popupStatus = "Popup: off"; onChange?() }
        scheduleRender(delay: 0)
    }

    /// Undo bound to a specific correction. A popup built for an older record never undoes a
    /// newer one: the id must be the current record's id.
    func undo(recordID: UUID, andIgnore: Bool = false) {
        guard recordID == undoRecordID else {
            RuntimeDiagnostics.record("popup: stale undo refused")
            status = "That correction is no longer the latest; nothing changed"
            onChange?()
            return
        }
        undo(andIgnore: andIgnore)
    }

    func refresh() {
        invalidate()
        cache.removeAll(keepingCapacity: false)
        guard preferences.enabled else { monitor.stop(); status = "Paused"; onChange?(); return }
        guard AXIsProcessTrusted() else { monitor.stop(); status = "Accessibility permission needed"; onChange?(); return }
        guard CGPreflightListenEventAccess() else { monitor.stop(); status = "Input Monitoring permission needed"; onChange?(); return }
        prepareFocusedApplication()
        status = monitor.start() ? "Ready" : "Keyboard access unavailable — restart AutoCorrect"
        onChange?()
        scheduleScan(delay: 200)
    }

    func focusChanged() {
        invalidate()
        prepareFocusedApplication()
        scheduleScan(delay: 400)
    }

    private func prepareFocusedApplication() {
        guard preferences.enabled, let app = NSWorkspace.shared.frontmostApplication,
              let bundle = app.bundleIdentifier, !preferences.excludedApps.contains(bundle) else { return }
        AccessibilityText.prepare(app: app)
    }

    private func cancelScheduled() {
        generation &+= 1
        work?.cancel()
        work = nil
    }

    func invalidate() {
        pendingDeletionRestart = false
        resetTyping()
        manualRewrites.reset()
        rewriteField = nil
        pending = nil
        undoProposal = nil
        undoAnchor = nil
        undoRecordID = nil
        popupDismissedID = nil
        popup.clear()
        popupStatus = "Popup: none"
        sentences.invalidate()
        applyingSuggestionID = nil
        suggestionPopup.clear()
        suggestionPopupMode = .capsule
        suggestionPopupStatus = ""
        autoCapital = nil
        backlog.reset()
        attemptedBoundaries.removeAll()
        flaggedWord = nil
        scanWork?.cancel()
        renderWork?.cancel()
        markSet.removeAll()
        overridden.removeAll()
        markField = nil
        fieldObserver = nil
        underlineStatus = "Underlines: none"
        indicator.hide()
        if monitor.isRunning { status = "Ready" }
    }

    private func resetTyping() {
        cancelScheduled()
        sessionEpoch &+= 1
        inFlight = false
        backlog.reset()
        attemptedBoundaries.removeAll()
        readAttempts = 0
        fieldStart = .unknown
        fieldStartAttempts = 0
        autoCapital = nil
    }

    /// A read is worth scheduling for the unfinished first word of a typing session only
    /// while capitalization is on, the session has not been settled, the word is short and
    /// at most three immediate edits have been handed to the keyboard path (a fast next
    /// key invalidates an edit; the completed-word fallback still covers the word).
    private var needsFieldStartCheck: Bool {
        preferences.capitalizesAfterPeriod && fieldStart != .finished && fieldStartAttempts < 3
            && backlog.isTypingFirstWord && backlog.typedSinceReset <= 32
    }

    private func confirmsFieldStart(_ snapshot: AccessibilityText.Snapshot, requireTextArea: Bool = true) -> Bool {
        #if DEBUG
        if let fieldStartConfirmation { return fieldStartConfirmation(snapshot) }
        #endif
        let confirmed = AccessibilityText.confirmsFieldStart(snapshot, requireTextArea: requireTextArea)
        RuntimeDiagnostics.record(confirmed ? "field start confirmed" : "field start not confirmed")
        return confirmed
    }

    private func key(_ text: String?, flags: CGEventFlags, keyCode: Int64) {
        if [51, 117].contains(keyCode) { pendingDeletionRestart = true }
        else if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate)
                    || [36, 48, 53, 76, 115, 116, 119, 121, 123, 124, 125, 126].contains(keyCode) {
            pendingDeletionRestart = false
        }
        if [51, 117].contains(keyCode) || (keyCode == 6 && flags.contains(.maskCommand) && !flags.contains(.maskShift)) {
            manualRewrites.noteManualEdit(now: ProcessInfo.processInfo.systemUptime)
        }
        cancelScheduled()
        let hadProposal = pending != nil || flaggedWord != nil
        pending = nil
        flaggedWord = nil
        // Text moves while typing; marks stay in the model and are redrawn after a pause.
        indicator.hide()
        if popupMode == .capsule { popupMode = .dot }
        popup.hide()
        if suggestionPopupMode == .capsule { suggestionPopupMode = .dot }
        suggestionPopup.hide()
        if undoRecordID != nil, preferences.showsCorrectionPopup { scheduleRender(delay: 400) }
        if sentences.active != nil { scheduleRender(delay: 400) }
        if preferences.enabled { sentences.noteTyping { [weak self] in self?.analysisSnapshot() } }
        if hadProposal { status = "Ready"; onChange?() }
        if keyCode == 9, flags.contains(.maskCommand) { scheduleScan(delay: 600) }   // paste
        guard preferences.enabled, !flags.contains(.maskCommand), !flags.contains(.maskControl), !flags.contains(.maskAlternate),
              ![36, 48, 51, 53, 76, 115, 116, 117, 119, 121, 123, 124, 125, 126].contains(keyCode),
              let text, TypingTypography.isSupportedKeystroke(text) else { resetTyping(); scheduleRender(delay: 300); return }
        backlog.append(text)
        readAttempts = 0
        attemptedBoundaries = attemptedBoundaries.filter { entry in backlog.boundaries.contains { $0.id == entry.key } }
        // A letter starting (or continuing) the first word of a session may need immediate
        // capitalization; later letters retry an edit that a fast next key invalidated.
        guard pendingDeletionRestart || !backlog.boundaries.isEmpty || (needsFieldStartCheck && text.first?.isLowercase == true) else { return }
        scheduleCheck()
    }

    private func scheduleCheck(delay: Int = 18) {
        guard !inFlight, !backlog.boundaries.isEmpty || needsFieldStartCheck || pendingDeletionRestart else { return }
        work?.cancel()
        let ticket = generation
        let task = DispatchWorkItem { [weak self] in
            guard let self, self.generation == ticket, !self.inFlight else { return }
            self.checkBoundary()
        }
        work = task
        // Briefly yield for the receiving editor. Later letters retain earlier boundaries.
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delay), execute: task)
    }

    private func checkBoundary() {
        guard AXIsProcessTrusted(), KeyboardMonitor.safeInputSource,
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let bundleID = app.bundleIdentifier, !preferences.excludedApps.contains(bundleID) else { backlog.reset(); return }
        AccessibilityText.prepare(app: app)
        guard let snapshot = AccessibilityText.snapshot(pid: app.processIdentifier) else {
            if retryRead() { return }
            backlog.reset()
            status = "Text access unavailable in \(app.localizedName ?? "this app")"
            onChange?()
            return
        }
        if status.hasPrefix("Text access unavailable") { status = "Ready"; onChange?() }
        processBoundaries(using: snapshot)
    }

    /// Assesses every queued boundary against one snapshot. Separated from the
    /// Accessibility read so tests can drive it. Detection adds marks; only confident
    /// automatic repairs post edits; rendering happens after the pass.
    func processBoundaries(using snapshot: AccessibilityText.Snapshot) {
        adoptField(snapshot.element, pid: snapshot.pid)
        reconcileDeletionRestart(using: snapshot)
        markSet.reconcile(text: snapshot.text, windowStart: snapshot.windowStart)
        overridden.reconcile(text: snapshot.text, windowStart: snapshot.windowStart)
        if capitalizeFieldStart(using: snapshot) { return }
        // A read made only for the first word of a session queues no scan or render.
        guard !backlog.boundaries.isEmpty else { return }
        defer { scheduleRender(delay: 120); scheduleScan(delay: 500) }
        while let boundary = backlog.boundaries.first {
            guard let completed = boundary.completedPrefix(in: snapshot.text) else {
                if retryRead() { return }
                backlog.remove(boundary.id)
                continue
            }
            // The word whose first letter AutoCorrect capitalized is judged as typed first.
            var reconciledThisWord = false
            if !boundary.spellingCorrected, let reconciled = reconcileAutoCapital(in: completed, snapshot: snapshot) {
                reconciledThisWord = true
                if preferences.asksBeforeCorrecting || !reconciled.automatic {
                    showSuggestion(reconciled.proposal, spelling: false)
                } else {
                    perform(reconciled.proposal, isUndo: false, andIgnore: false, boundaryID: boundary.id)
                    return
                }
            }
            let atFieldStart = isVerifiedFieldStart(completed, snapshot: snapshot)
            if !boundary.spellingCorrected, !reconciledThisWord, let candidate = candidate(in: completed, atFieldStart: atFieldStart),
               snapshot.windowStart == 0 || candidate.range.location > 0,
               !preferences.ignoredWords.contains(UserDictionary.normalizedKey(candidate.original)) {
                if isManualRewrite(candidate, snapshot: snapshot) {
                    // The user deliberately restored this spelling here: no correction, no mark.
                    noteOverride(SpellingMark(location: snapshot.windowStart + candidate.range.location, word: candidate.original))
                } else {
                    let result = assessment(candidate.original, context: completed, range: candidate.range, atFieldStart: atFieldStart)
                    if result.misspelled {
                        flaggedWord = candidate.original
                        if let replacement = result.replacement {
                            let proposal = Proposal(snapshot: snapshot, range: candidate.range, original: candidate.original,
                                                    replacement: replacement, created: Date())
                            if preferences.asksBeforeCorrecting || !result.automatic {
                                showSuggestion(proposal)
                            } else {
                                // Keep this boundary until both spelling and context have been
                                // assessed against a fresh post-edit snapshot.
                                perform(proposal, isUndo: false, andIgnore: false, boundaryID: boundary.id)
                                return
                            }
                        } else {
                            status = "Possible misspelling: \(candidate.original)"
                            addMark(SpellingMark(location: snapshot.windowStart + candidate.range.location, word: candidate.original), near: snapshot.caret)
                            onChange?()
                        }
                    }
                }
            }
            // Check each completed prefix, including while the next word is incomplete.
            // Reading only snapshot.text here used to lose context checks during fast typing.
            if !boundary.contextCorrected, pending == nil, let contextual = contextualCandidate(in: completed),
               snapshot.windowStart == 0 || contextual.range.location > 0,
               !isManualRewrite(CorrectionCandidate(original: contextual.original, range: contextual.range), snapshot: snapshot) {
                let proposal = Proposal(snapshot: snapshot, range: contextual.range, original: contextual.original,
                                        replacement: contextual.replacement, created: Date())
                if contextual.automatic && !preferences.asksBeforeCorrecting {
                    perform(proposal, isUndo: false, andIgnore: false, boundaryID: boundary.id, contextual: true)
                    return
                }
                showSuggestion(proposal, spelling: false)
            }
            backlog.remove(boundary.id)
        }
        // Every boundary settled without an edit: the last complete sentence may be analyzed.
        if preferences.enabled, !inFlight { sentences.noteBoundary(snapshot: snapshot) }
    }

    /// Count only newly typed keys after the deletion. If they cover the entire verified
    /// field, this is a fresh attempt, not a rejection of the old spelling at offset zero.
    /// A retained suffix, selection/navigation, or missing evidence keeps normal protection.
    private func reconcileDeletionRestart(using snapshot: AccessibilityText.Snapshot) {
        guard pendingDeletionRestart, backlog.typedSinceReset > 0 else { return }
        pendingDeletionRestart = false
        guard snapshot.windowStart == 0,
              snapshot.text.utf16.count <= backlog.typedSinceReset,
              confirmsFieldStart(snapshot, requireTextArea: false) else { return }
        manualRewrites.reset()
        overridden.removeAll()
        undoProposal = nil
        undoAnchor = nil
        undoRecordID = nil
        popup.clear()
        popupStatus = "Popup: none"
        RuntimeDiagnostics.record("fresh field attempt after deletion")
    }

    private func retryRead() -> Bool {
        guard readAttempts < 3 else { return false }
        readAttempts += 1
        scheduleCheck(delay: 40)
        return true
    }

    /// Immediate capitalization of the first letter typed into an empty prose area, before
    /// a space or any other delimiter. The snapshot must hold nothing but optional leading
    /// whitespace/openers and the lowercase word typed in this session, and the field's
    /// reported length must confirm (once per session) that this is the whole field. Any
    /// other finding settles the session: no further reads for it.
    private func capitalizeFieldStart(using snapshot: AccessibilityText.Snapshot) -> Bool {
        guard needsFieldStartCheck else { return false }
        guard snapshot.windowStart == 0, snapshot.isTextArea,
              let candidate = SentenceCapitalization.fieldStartCandidate(in: snapshot.text),
              snapshot.text.utf16.count <= backlog.typedSinceReset else {
            fieldStart = .finished
            return false
        }
        guard !preferences.ignoredWords.contains(UserDictionary.normalizedKey(candidate.original)),
              !isManualRewrite(candidate, snapshot: snapshot) else {
            fieldStart = .finished
            return false
        }
        if fieldStart == .unknown { fieldStart = confirmsFieldStart(snapshot) ? .confirmed : .finished }
        guard fieldStart == .confirmed, let replacement = SentenceCapitalization.replacement(for: candidate.original) else { return false }
        let proposal = Proposal(snapshot: snapshot, range: candidate.range, original: candidate.original,
                                replacement: replacement, created: Date(), capitalizesFieldStart: true)
        if preferences.asksBeforeCorrecting {
            // Review mode: offer once, never edit. The next key clears the proposal; the
            // completed word is offered again through the ordinary delimiter path.
            fieldStartAttempts = 3
            showSuggestion(proposal, spelling: false)
            return true
        }
        fieldStartAttempts += 1
        perform(proposal, isUndo: false, andIgnore: false)
        return true
    }

    /// The completed token at the occurrence AutoCorrect capitalized, judged as typed.
    /// A deliberately typed internal capital (`iPhone`) is restored exactly when it is a
    /// canonical name; otherwise the lowercase form runs through the ordinary assessment
    /// (`github` → `GitHub`, `idk` → `I don't know`, `teh` → `The`, `hello` → `Hello`).
    /// Keep the record while an edit is unposted so a canceled attempt can be reassessed
    /// against a fresh snapshot. Terminal decisions and posted edits retire it.
    private func reconcileAutoCapital(in completed: String, snapshot: AccessibilityText.Snapshot) -> (proposal: Proposal, automatic: Bool)? {
        guard let record = autoCapital, record.field == rewriteFieldID(for: snapshot),
              snapshot.windowStart <= record.location else { return nil }
        let local = record.location - snapshot.windowStart
        guard local < completed.utf16.count else { return nil }
        var awaitingEdit = false
        defer { if !awaitingEdit { autoCapital = nil } }
        guard let candidate = CorrectionPolicy.candidate(in: completed, caret: completed.utf16.count,
                                                         caseExceptions: Set(preferences.customCorrections.keys), relaxedCaseAt: local),
              candidate.range.location == local, candidate.original.hasPrefix(record.replacement),
              !preferences.ignoredWords.contains(UserDictionary.normalizedKey(candidate.original)),
              !isManualRewrite(candidate, snapshot: snapshot) else { return nil }
        let typed = record.typed + candidate.original.dropFirst(record.replacement.count)
        var replacement: String?
        var automatic = true
        if let custom = preferences.customCorrections[UserDictionary.normalizedKey(typed)] {
            replacement = custom
        } else if typed.dropFirst().contains(where: \.isUppercase) {
            // Internal capitals were typed deliberately. Only a known canonical spelling
            // justifies undoing our capital (iPhone, eBay, macOS); anything else is kept.
            guard preferences.normalizesProductNames, NameLexicon.isCanonicalName(typed) else { return nil }
            replacement = typed
        } else {
            let context = (completed as NSString).replacingCharacters(in: candidate.range, with: typed)
            let result = assessment(typed, context: context, range: NSRange(location: candidate.range.location, length: typed.utf16.count),
                                    atFieldStart: true)
            guard result.misspelled, let chosen = result.replacement else { return nil }
            replacement = chosen
            automatic = result.automatic
        }
        guard let replacement, replacement != candidate.original else { return nil }
        awaitingEdit = true
        return (Proposal(snapshot: snapshot, range: candidate.range, original: candidate.original, replacement: replacement,
                         created: Date(), typed: typed), automatic)
    }

    /// `typed` identifies a reconciliation proposal. Retire before verification: once
    /// events post, a slow or failed verification must never cause the edit to repeat.
    private func retireAutoCapital(for proposal: Proposal) {
        if proposal.typed != nil { autoCapital = nil }
    }

    /// Bookkeeping shared by Accessibility verification and the test transport once the host
    /// shows the edit: counters, marks, overrides, the field-start record and the undo anchor.
    private func completeVerifiedEdit(_ proposal: Proposal, observed: String, isUndo: Bool, andIgnore: Bool) {
        inFlight = false
        RuntimeDiagnostics.record("correction verified")
        correctionCount = max(0, correctionCount + (isUndo ? -1 : 1))
        let editLocation = proposal.snapshot.windowStart + proposal.range.location
        noteAppliedEdit(location: editLocation, length: proposal.original.utf16.count,
                        replacementLength: proposal.replacement.utf16.count)
        if isUndo {
            // The user asked for the original spelling back: keep that occurrence unmarked.
            noteOverride(SpellingMark(location: editLocation, word: proposal.replacement))
            manualRewrites.noteExplicitRejection(field: rewriteFieldID(for: proposal.snapshot), location: editLocation)
            sentences.noteUndo(spanLocation: editLocation, restoredText: proposal.replacement)
            autoCapital = nil
            undoRecordID = nil
            popup.clear()
            popupStatus = "Popup: none"
        } else if let id = applyingSuggestionID {
            applyingSuggestionID = nil
            sentences.applySucceeded(id: id)
        } else if proposal.capitalizesFieldStart {
            // The field's first letter is now capitalized: no further reads this session,
            // and the completed token will be judged as typed.
            fieldStart = .finished
            autoCapital = AutoCapital(field: rewriteFieldID(for: proposal.snapshot), location: editLocation,
                                      typed: proposal.original, replacement: proposal.replacement)
        }
        if andIgnore {
            preferences.ignoredWords.insert(UserDictionary.normalizedKey(proposal.replacement))
            markSet.remove(word: proposal.replacement)
        }
        if !isUndo {
            // Anchor undo to the host's actual text: it may have restyled our punctuation.
            var bounded = observed[...]
            while bounded.utf16.count > 256 { bounded.removeFirst() }
            let clipped = observed.utf16.count - bounded.utf16.count
            let reverseRange = NSRange(location: proposal.range.location, length: proposal.replacement.utf16.count)
            undoAnchor = CorrectionUndoAnchor(text: String(bounded), windowStart: proposal.snapshot.windowStart + clipped,
                range: NSRange(location: reverseRange.location - clipped, length: reverseRange.length))
            undoProposal = Proposal(snapshot: proposal.snapshot, range: reverseRange,
                original: (observed as NSString).substring(with: reverseRange), replacement: proposal.typed ?? proposal.original, created: Date())
            // A new record gets a new identity. It starts as the quiet indicator; details open
            // only on a deliberate click or the documented shortcut.
            let id = UUID()
            undoRecordID = id
            popupDismissedID = nil
            popupMode = .dot
            // Expiry removes the popup even when nothing else happens in the field.
            popupExpiryWork?.cancel()
            let expiry = DispatchWorkItem { [weak self] in
                guard let self, self.undoRecordID == id else { return }
                self.renderPopup()
            }
            popupExpiryWork = expiry
            DispatchQueue.main.asyncAfter(deadline: .now() + 300.5, execute: expiry)
        }
        status = isUndo ? "Correction undone" : "Ready"
        onChange?()
        scheduleCheck()
    }

    /// Undo of a case-only edit (field-start capitalization, casing reconciliation) after
    /// the user kept typing: the recorded span is the start of a longer word now, so the
    /// reversal covers the whole ASCII word and keeps the letters typed after the span.
    /// Anything else (a non-ASCII continuation, a changed span) leaves the range alone and
    /// the ordinary plan safeguards decide. Spelling and expansion undo are unchanged.
    private func caseOnlyUndoRange(for saved: Proposal, in text: String, at range: NSRange) -> (range: NSRange, original: String, replacement: String)? {
        guard saved.original.count == saved.replacement.count,
              saved.original.lowercased() == saved.replacement.lowercased() else { return nil }
        let units = Array(text.utf16)
        var end = NSMaxRange(range)
        while end < units.count, end - range.location < 64,
              let scalar = Unicode.Scalar(units[end]), scalar.isASCII,
              CharacterSet.letters.contains(scalar) || scalar == "'" { end += 1 }
        guard end > NSMaxRange(range) else { return nil }
        let extended = NSRange(location: range.location, length: end - range.location)
        let onScreen = (text as NSString).substring(with: extended)
        guard onScreen.hasPrefix(saved.original) else { return nil }
        return (extended, onScreen, saved.replacement + onScreen.dropFirst(saved.original.count))
    }

    /// Field-start evidence for a completed first word (the fallback when the immediate
    /// edit never landed, e.g. every attempt was invalidated by fast typing): the completed
    /// text was typed entirely in this session into a verified empty prose area.
    private func isVerifiedFieldStart(_ completed: String, snapshot: AccessibilityText.Snapshot) -> Bool {
        guard preferences.capitalizesAfterPeriod, snapshot.windowStart == 0, snapshot.isTextArea,
              completed.utf16.count <= backlog.typedSinceReset else { return false }
        switch fieldStart {
        case .confirmed: return true
        case .finished: return false
        case .unknown:
            let caret = completed.utf16.count
            // Only a word that is a candidate solely because of the field start needs the read.
            guard SentenceCapitalization.candidate(in: completed, caret: caret, atFieldStart: true) != nil,
                  SentenceCapitalization.candidate(in: completed, caret: caret) == nil else { return false }
            fieldStart = confirmsFieldStart(snapshot) ? .confirmed : .finished
            return fieldStart == .confirmed
        }
    }

    private func rewriteFieldID(for snapshot: AccessibilityText.Snapshot) -> UUID {
        if let field = rewriteField, field.pid == snapshot.pid, CFEqual(field.element, snapshot.element) { return field.id }
        manualRewrites.reset()
        let id = UUID()
        rewriteField = (snapshot.pid, snapshot.element, id)
        return id
    }

    private func isManualRewrite(_ candidate: CorrectionCandidate, snapshot: AccessibilityText.Snapshot) -> Bool {
        let field = rewriteFieldID(for: snapshot)
        return manualRewrites.suppresses(field: field, candidate: candidate, text: snapshot.text,
                                        windowStart: snapshot.windowStart, now: ProcessInfo.processInfo.systemUptime)
    }

    func contextualCandidate(in text: String) -> ContextualWritingCandidate? {
        guard preferences.checksContext, preferences.language.lowercased().hasPrefix("en"),
              let candidate = ContextualWritingRules.candidate(in: text) ?? uppercaseContractionCandidate(in: text),
              !preferences.ignoredWords.contains(UserDictionary.normalizedKey(candidate.original)),
              preferences.customCorrections[UserDictionary.normalizedKey(candidate.original)] == nil else { return nil }
        return candidate
    }

    /// `ODNT DO ` → `DON'T DO `: the native checker treats all-caps tokens as acronyms, so
    /// the rule asks it about the lowercase forms instead (the following word must be a
    /// dictionary word; a transposed four-letter key needs the native correction too).
    private func uppercaseContractionCandidate(in text: String) -> ContextualWritingCandidate? {
        let checker = NSSpellChecker.shared
        let language = preferences.language
        return EnglishWritingRules.uppercaseContractionCandidate(in: text, language: language, isWord: { word in
            let tag = NSSpellChecker.uniqueSpellDocumentTag()
            defer { checker.closeSpellDocument(withTag: tag) }
            return checker.checkSpelling(of: word, startingAt: 0, language: language, wrap: false,
                                         inSpellDocumentWithTag: tag, wordCount: nil).location == NSNotFound
        }, nativeCorrection: { word in
            let tag = NSSpellChecker.uniqueSpellDocumentTag()
            defer { checker.closeSpellDocument(withTag: tag) }
            let range = NSRange(location: 0, length: word.utf16.count)
            return checker.correction(forWordRange: range, in: word + " ", language: language, inSpellDocumentWithTag: tag)
                ?? checker.guesses(forWordRange: range, in: word + " ", language: language, inSpellDocumentWithTag: tag)?.first
        })
    }

    /// `spelling` distinguishes an unresolved misspelling (marked) from a contextual
    /// grammar doubt such as its/it's (indicated in the menu only, never underlined).
    func showSuggestion(_ proposal: Proposal, spelling: Bool = true) {
        // Automatic mode must never silently turn into review mode for a weak guess.
        // Keep its visual indication, but only create an approval action when requested.
        pending = preferences.asksBeforeCorrecting ? proposal : nil
        flaggedWord = proposal.original
        status = preferences.asksBeforeCorrecting ? "Suggestion ready" : "Possible misspelling: \(proposal.original)"
        if spelling {
            addMark(SpellingMark(location: proposal.snapshot.windowStart + proposal.range.location, word: proposal.original),
                    near: proposal.snapshot.caret)
        }
        onChange?()
    }

    // MARK: - Persistent spelling marks

    private func adoptField(_ element: AXUIElement, pid: pid_t) {
        if let field = markField, field.pid == pid, CFEqual(field.element, element) { return }
        markSet.removeAll()
        overridden.removeAll()
        markField = (pid, element)
        fieldObserver = nil
        guard pid != ProcessInfo.processInfo.processIdentifier, AXIsProcessTrusted(),
              let observer = FieldObserver(pid: pid, element: element) else { return }
        observer.onEvent = { [weak self] event in self?.handleFieldEvent(event) }
        fieldObserver = observer
    }

    private func handleFieldEvent(_ event: FieldObserver.Event) {
        switch event {
        case .valueChanged: scheduleScan(delay: 500); scheduleRender(delay: 150)
        case .selectionChanged: scheduleRender(delay: 150)
        case .windowMoved, .windowResized: indicator.hide(); popup.hide(); scheduleRender(delay: 120)
        case .focusChanged: invalidate(); scheduleScan(delay: 300)
        case .deactivated, .destroyed: invalidate()
        }
    }

    private func addMark(_ mark: SpellingMark, near caret: Int) {
        guard preferences.showsSpellingIndicators, !overridden.marks.contains(mark) else { return }
        markSet.insert(mark, near: caret)
    }

    /// A deliberate user override (undo, retyping a correction) keeps that occurrence unmarked.
    func noteOverride(_ mark: SpellingMark) {
        markSet.remove(at: mark.location)
        overridden.insert(mark, near: mark.location)
        scheduleRender(delay: 50)
    }

    /// A posted edit changed `length` units at `location` into `replacementLength` units.
    func noteAppliedEdit(location: Int, length: Int, replacementLength: Int) {
        markSet.applyEdit(at: location, length: length, replacementLength: replacementLength)
        overridden.applyEdit(at: location, length: length, replacementLength: replacementLength)
        scheduleRender(delay: 50)
    }

    func ignore(word: String) {
        preferences.ignoredWords.insert(UserDictionary.normalizedKey(word))
        markSet.remove(word: word)
        scheduleRender(delay: 50)
    }

    /// Marks for existing text: one native query for the whole bounded region, then the
    /// tokenization and policy filters. Never posts edits.
    func scanMarks(text: String, windowStart: Int, caret: Int) -> [SpellingMark] {
        guard preferences.showsSpellingIndicators, (1...2048).contains(text.utf16.count) else { return [] }
        let checker = NSSpellChecker.shared
        let spellDocument = NSSpellChecker.uniqueSpellDocumentTag()
        defer { checker.closeSpellDocument(withTag: spellDocument) }
        let orthography = NSOrthography(dominantScript: "Latn", languageMap: ["Latn": [preferences.language]])
        let results = checker.check(text, range: NSRange(location: 0, length: text.utf16.count),
                                    types: NSTextCheckingResult.CheckingType.spelling.rawValue,
                                    options: [.orthography: orthography],
                                    inSpellDocumentWithTag: spellDocument, orthography: nil, wordCount: nil)
        let ranges = results.filter { $0.resultType == .spelling }.map(\.range)
        let localCaret = (caret - windowStart) >= 0 && (caret - windowStart) <= text.utf16.count ? caret - windowStart : nil
        let ignored = preferences.ignoredWords
        let custom = preferences.customCorrections
        return SpellingScan.marks(in: text, windowStart: windowStart, misspelledRanges: ranges, activeCaret: localCaret) { word in
            let key = UserDictionary.normalizedKey(word)
            return !ignored.contains(key) && custom[key] == nil && !NameLexicon.recognizes(word)
                && BuiltInReplacements.casing[key] == nil && BuiltInReplacements.expansions[key] == nil
        }.filter { !overridden.marks.contains($0) }
    }

    private func scheduleScan(delay: Int) {
        scanWork?.cancel()
        guard preferences.enabled, preferences.showsSpellingIndicators, !suppressesRendering else { return }
        let task = DispatchWorkItem { [weak self] in self?.performScan() }
        scanWork = task
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delay), execute: task)
    }

    private func performScan() {
        guard preferences.enabled, preferences.showsSpellingIndicators, AXIsProcessTrusted(), !inFlight,
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let bundleID = app.bundleIdentifier, !preferences.excludedApps.contains(bundleID) else { return }
        guard let region = AccessibilityText.focusedTextRegion(pid: app.processIdentifier) else {
            underlineStatus = "Underlines: text unavailable in \(app.localizedName ?? "this app")"
            indicator.hide()
            onChange?()
            return
        }
        adoptField(region.element, pid: region.pid)
        let fresh = scanMarks(text: region.text, windowStart: region.windowStart, caret: region.caret)
        markSet.replace(in: NSRange(location: region.windowStart, length: region.text.utf16.count), with: fresh, near: region.caret)
        if let length = region.length {
            markSet.truncate(to: length)
            overridden.truncate(to: length)
        }
        RuntimeDiagnostics.record("scan: \(fresh.count) mark(s) in region")
        renderMarks()
    }

    private func scheduleRender(delay: Int) {
        renderWork?.cancel()
        guard !suppressesRendering else { return }
        let task = DispatchWorkItem { [weak self] in self?.renderMarks(); self?.renderPopup(); self?.renderSuggestion() }
        renderWork = task
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delay), execute: task)
    }

    private func renderMarks() {
        guard !suppressesRendering else { return }
        guard preferences.enabled, preferences.showsSpellingIndicators, let field = markField,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == field.pid else { indicator.hide(); return }
        guard !markSet.marks.isEmpty else {
            indicator.hide()
            if underlineStatus != "Underlines: none" { underlineStatus = "Underlines: none"; onChange?() }
            return
        }
        let summary = indicator.render(marks: markSet.marks, element: field.element)
        var parts = ["\(summary.placed) shown"]
        if summary.failed > 0 { parts.append("\(summary.failed) without geometry") }
        if summary.hidden > 0 { parts.append("\(summary.hidden) out of view") }
        let text = summary.placed == 0 && summary.failed > 0
            ? "Underlines: \(markSet.marks.count) found, geometry unavailable in this field"
            : "Underlines: " + parts.joined(separator: ", ")
        if text != underlineStatus { underlineStatus = text; onChange?() }
    }

    /// Draws the Undo popup (capsule or dot) beside the latest verified correction. Every step
    /// is a bounded Accessibility read of the recorded field; any doubt hides the popup and says
    /// so in the status line instead of guessing a position or keeping a stale record.
    private func renderPopup() {
        guard !suppressesRendering else { return }
        func report(_ text: String) { if popupStatus != text { popupStatus = text; onChange?() } }
        guard preferences.showsCorrectionPopup else { popup.hide(); report("Popup: off"); return }
        guard preferences.enabled, let saved = undoProposal, let anchor = undoAnchor, let id = undoRecordID else {
            popup.clear(); report("Popup: none"); return
        }
        guard Date().timeIntervalSince(saved.created) < 300 else {
            undoProposal = nil; undoAnchor = nil; undoRecordID = nil
            popup.clear(); report("Popup: none (correction expired)"); return
        }
        guard id != popupDismissedID else { popup.hide(); report("Popup: dismissed for this correction"); return }
        var focused = NSWorkspace.shared.frontmostApplication?.processIdentifier == saved.snapshot.pid
        if focused, let current = AccessibilityText.focusedElement(pid: saved.snapshot.pid) { focused = CFEqual(current, saved.snapshot.element) } else { focused = false }
        #if DEBUG
        if let popupFieldFocused { focused = popupFieldFocused() }
        #endif
        guard focused else { popup.hide(); report("Popup: hidden until the corrected field is focused again"); return }
        let element = saved.snapshot.element
        // Re-verify the record with a bounded read of exactly its saved context and span.
        let context = anchor.absoluteContextRange
        var contextText = AccessibilityText.substring(element, range: CFRange(location: context.location, length: context.length))
        #if DEBUG
        if let undoContextReader { contextText = undoContextReader(context) }
        #endif
        // An unreadable context is not evidence that the text changed: hide and keep the record,
        // so a later successful read (or keyboard Undo, which re-reads) can still use it.
        guard let text = contextText else {
            popup.hide(); report("Popup: hidden (text could not be read right now)"); return
        }
        guard anchor.matchingRange(in: text, windowStart: context.location) != nil else {
            undoProposal = nil; undoAnchor = nil; undoRecordID = nil
            popup.clear(); report("Popup: none (corrected text changed, no longer undoable)"); return
        }
        let target = anchor.absoluteTargetRange
        var geometry: CorrectionPopup.Geometry?
        #if DEBUG
        if let popupGeometryProvider { geometry = popupGeometryProvider(target) } else { geometry = popupGeometry(for: target, element: element) }
        #else
        geometry = popupGeometry(for: target, element: element)
        #endif
        guard let geometry else { popup.hide(); report("Popup: word position unavailable in this app"); return }
        // The undo proposal reverses the edit, so its "original" is the replacement now on screen.
        let content = CorrectionPopup.Content(id: id, original: saved.replacement, replacement: saved.original)
        let shown = popup.show(content, mode: popupMode, geometry: geometry)
        report(shown ? (popupMode == .capsule ? "Popup: beside the word" : "Popup: indicator after the word's line")
                     : (popupMode == .capsule ? "Popup: no placement that avoids the caret or the screen edge"
                                              : "Popup: indicator has no safe place on this line"))
    }

    /// Draws the active suggestion (capsule with Apply and dismiss, or its indicator) beside the
    /// suggested span. The sentence is re-read first; a changed sentence withdraws it. Missing
    /// geometry hides the popup and points to the menu, never to a guessed position.
    private func renderSuggestion() {
        guard !suppressesRendering else { return }
        func report(_ text: String) { if suggestionPopupStatus != text { suggestionPopupStatus = text; onChange?() } }
        guard preferences.enabled, let current = sentences.active else { suggestionPopup.clear(); report(""); return }
        var focused = NSWorkspace.shared.frontmostApplication?.processIdentifier == current.field.pid
        if focused, let element = AccessibilityText.focusedElement(pid: current.field.pid) { focused = CFEqual(element, current.field.element) } else { focused = false }
        #if DEBUG
        if let popupFieldFocused { focused = popupFieldFocused() }
        #endif
        guard focused else { suggestionPopup.hide(); report("Suggestion popup: hidden until the field is focused again"); return }
        let element = current.field.element
        guard sentences.applying == nil else { suggestionPopup.hide(); report("Suggestion popup: applying"); return }
        guard sentences.revalidate(), let live = sentences.active else {
            suggestionPopup.hide(); report(sentences.active == nil ? "" : "Suggestion popup: hidden (text could not be verified)"); return
        }
        let span = NSRange(location: live.spanLocation, length: live.suggestion.original.utf16.count)
        var geometry: CorrectionPopup.Geometry?
        #if DEBUG
        if let popupGeometryProvider { geometry = popupGeometryProvider(span) } else { geometry = popupGeometry(for: span, element: element) }
        #else
        geometry = popupGeometry(for: span, element: element)
        #endif
        guard let geometry else { suggestionPopup.hide(); report("Suggestion popup: word position unavailable here; review it from the menu"); return }
        let content = CorrectionPopup.Content(id: live.suggestion.id, original: live.suggestion.original, replacement: live.suggestion.replacement,
                                              kind: .suggestion, detail: live.suggestion.explanation)
        let shown = suggestionPopup.show(content, mode: suggestionPopupMode, geometry: geometry)
        report(shown ? (suggestionPopupMode == .capsule ? "Suggestion popup: beside the sentence" : "Suggestion popup: indicator after the line")
                     : "Suggestion popup: no safe placement; review it from the menu")
    }

    /// Verified geometry for the corrected span from Accessibility: single-line word rectangle
    /// (first and last character rectangles must agree), the last visible character of the
    /// word's line, the caret and the visible area. Nil means no popup.
    private func popupGeometry(for target: NSRange, element: AXUIElement) -> CorrectionPopup.Geometry? {
        AXUIElementSetMessagingTimeout(element, 0.02)
        guard target.length > 0 else { return nil }
        let wordRect = SpellingIndicator.bounds(for: CFRange(location: target.location, length: target.length), element: element)
        let firstRect = SpellingIndicator.bounds(for: CFRange(location: target.location, length: 1), element: element)
        let lastRect = SpellingIndicator.bounds(for: CFRange(location: NSMaxRange(target) - 1, length: 1), element: element)
        guard let word = CorrectionPopup.verifiedWord(word: wordRect, first: firstRect, last: lastRect) else { return nil }
        var lineEnd: CGRect?
        if let line = SpellingIndicator.line(at: target.location, element: element),
           let range = SpellingIndicator.lineRange(for: line, element: element), range.length > 0 {
            var last = range.location + range.length - 1
            // A trailing line break has no visible rectangle: use the character before it.
            if let trailing = AccessibilityText.substring(element, range: CFRange(location: last, length: 1)), trailing == "\n" || trailing == "\r" { last -= 1 }
            if last >= target.location, let rect = SpellingIndicator.bounds(for: CFRange(location: last, length: 1), element: element),
               CorrectionPopup.isValid(rect), abs(rect.midY - word.midY) <= max(rect.height, word.height) * 0.6 {
                lineEnd = rect
            }
        }
        var caret: CGRect?
        if let selected = AccessibilityText.range(element), selected.length == 0, selected.location > 0 {
            caret = SpellingIndicator.bounds(for: CFRange(location: selected.location - 1, length: 1), element: element)
        }
        return CorrectionPopup.Geometry(word: word, lineEnd: lineEnd, caret: caret, visible: SpellingIndicator.visibleArea(of: element))
    }

    private func candidate(in text: String, atFieldStart: Bool = false) -> CorrectionCandidate? {
        CorrectionPolicy.candidate(in: text, caret: text.utf16.count, caseExceptions: Set(preferences.customCorrections.keys))
            ?? (preferences.capitalizesAfterPeriod
                ? SentenceCapitalization.candidate(in: text, caret: text.utf16.count, atFieldStart: atFieldStart) : nil)
    }

    /// Uses exactly the same completed-word assessment as the keyboard path, without edits.
    /// `atFieldStart` stands in for verified evidence that `completedText` is the whole field.
    func suggestion(in completedText: String, atFieldStart: Bool = false) -> String? {
        guard let candidate = candidate(in: completedText, atFieldStart: atFieldStart) else { return nil }
        let result = assessment(candidate.original, context: completedText, range: candidate.range, atFieldStart: atFieldStart)
        return result.misspelled && result.automatic ? result.replacement : nil
    }

    /// Settings preview uses the same policies, without reading or modifying another app.
    func previewText(in text: String) -> String? {
        let completed = text.last.map(CorrectionPolicy.isDelimiter) == true ? text : text + " "
        guard completed.utf16.count <= 256 else { return nil }
        var output = ""
        var previewBoundaries = CompletedWordBacklog()
        for character in completed {
            output.append(character)
            previewBoundaries.append(String(character))
            if let boundary = previewBoundaries.boundaries.last {
                previewBoundaries.remove(boundary.id)
                if let candidate = candidate(in: output), let replacement = suggestion(in: output) {
                    output = (output as NSString).replacingCharacters(in: candidate.range, with: replacement)
                }
                if let context = contextualCandidate(in: output), context.automatic && !preferences.asksBeforeCorrecting {
                    output = (output as NSString).replacingCharacters(in: context.range, with: context.replacement)
                }
            }
        }
        if preferences.asksBeforeCorrecting, output.last != ".", output.last != ":", let context = contextualCandidate(in: output) {
            return (output as NSString).replacingCharacters(in: context.range, with: context.replacement) + " (approval required)"
        }
        return output == completed ? nil : output + (preferences.asksBeforeCorrecting ? " (approval required)" : "")
    }

    func suggestion(_ word: String) -> String? {
        let result = assessment(word)
        return result.misspelled && result.automatic ? result.replacement : nil
    }

    private func assessment(_ word: String, context: String? = nil, range: NSRange? = nil, atFieldStart: Bool = false) -> Assessment {
        let normalized = UserDictionary.normalizedKey(word)
        if preferences.ignoredWords.contains(normalized) { return Assessment(misspelled: false, replacement: nil, automatic: false) }
        if let custom = preferences.customCorrections[normalized] {
            return Assessment(misspelled: custom != word, replacement: custom, automatic: true)
        }
        if let builtIn = BuiltInReplacements.replacement(for: word, language: preferences.language,
            includeExpansions: preferences.expandsAbbreviations, includeCasing: preferences.normalizesProductNames) {
            return Assessment(misspelled: true, replacement: builtIn, automatic: true)
        }
        let spelling = spellingAssessment(word, context: context, range: range)
        // Product spelling is canonical even at a sentence start (iPhone, not IPhone).
        if preferences.normalizesProductNames, let replacement = spelling.replacement,
           NameLexicon.isCanonicalName(replacement) { return spelling }
        guard preferences.capitalizesAfterPeriod, let context, let range,
              let sentence = SentenceCapitalization.candidate(in: context, caret: context.utf16.count, atFieldStart: atFieldStart),
              sentence.range == range,
              let chosen = spelling.replacement ?? (spelling.misspelled ? nil : word),
              let capitalized = SentenceCapitalization.replacement(for: chosen) else { return spelling }
        return Assessment(misspelled: true, replacement: capitalized, automatic: !spelling.misspelled || spelling.automatic)
    }

    private func spellingAssessment(_ word: String, context: String?, range: NSRange?) -> Assessment {
        // A native transposition alone cannot choose between a purchase and a deadline.
        // Keep the typo available for the following-context pass instead of committing early.
        if preferences.language.lowercased().hasPrefix("en"), ContextualWritingRules.needsFollowingContext(word) {
            return Assessment(misspelled: true, replacement: nil, automatic: false)
        }
        if let writing = EnglishWritingRules.replacement(for: word, language: preferences.language) {
            return Assessment(misspelled: true, replacement: writing, automatic: true)
        }
        // Older spellcheck services require a completed word, including its delimiter,
        // to return an automatic recommendation even when they can supply guesses.
        let text = context ?? (word + " ")
        let wordRange = range ?? NSRange(location: 0, length: (word as NSString).length)
        let key = preferences.language + ":" + String(preferences.normalizesProductNames) + ":" + String(preferences.separatesJoinedWords) + ":" + text + ":" + String(wordRange.location)
        if let value = cache[key] { return value }
        let checker = NSSpellChecker.shared
        // A bounded snapshot is not a persistent document. Reusing one tag for every
        // field lets native correction-response state leak across words and apps.
        // Our own scoped rewrite protection and user dictionary handle user intent.
        let spellDocument = NSSpellChecker.uniqueSpellDocumentTag()
        defer { checker.closeSpellDocument(withTag: spellDocument) }
        let misspelled = checker.checkSpelling(of: word, startingAt: 0, language: preferences.language, wrap: false, inSpellDocumentWithTag: spellDocument, wordCount: nil)
        var answer = Assessment(misspelled: false, replacement: nil, automatic: false)
        let nativeMisspelled = misspelled.location != NSNotFound
        #if DEBUG
        nativeAssessmentObserver?(preferences.language, nativeMisspelled, nil, [])
        #endif
        if preferences.normalizesProductNames,
           let canonical = NameLexicon.canonicalReplacement(for: word, nativeMisspelled: nativeMisspelled) {
            return Assessment(misspelled: true, replacement: canonical, automatic: true)
        }
        // Recognition is independent of automatic capitalization: technical names should
        // not become unrelated English words even with product casing switched off.
        if NameLexicon.recognizes(word) { return answer }
        if nativeMisspelled {
            let proposed = checker.correction(forWordRange: wordRange, in: text, language: preferences.language, inSpellDocumentWithTag: spellDocument)
            let guesses = checker.guesses(forWordRange: wordRange, in: text, language: preferences.language, inSpellDocumentWithTag: spellDocument) ?? []
            #if DEBUG
            nativeAssessmentObserver?(preferences.language, nativeMisspelled, proposed, guesses)
            #endif
            if let contraction = EnglishWritingRules.typoReplacement(for: word, language: preferences.language,
                                                                     systemCorrection: proposed, guesses: guesses) {
                return Assessment(misspelled: true, replacement: contraction, automatic: true)
            }
            if let split = JoinedWordPolicy.replacement(for: word, language: preferences.language,
                    systemCorrection: proposed, guesses: guesses, isWord: { part in
                        checker.checkSpelling(of: part, startingAt: 0, language: self.preferences.language,
                            wrap: false, inSpellDocumentWithTag: spellDocument, wordCount: nil).location == NSNotFound
                    }) {
                return Assessment(misspelled: true, replacement: split, automatic: preferences.separatesJoinedWords)
            }
            if preferences.normalizesProductNames,
               let product = NameLexicon.typoReplacement(for: word, systemCorrection: proposed, guesses: guesses),
               (BuiltInReplacements.casing[product.lowercased()] == product ||
                NameLexicon.canonicalReplacement(for: product.lowercased(), nativeMisspelled:
                   checker.checkSpelling(of: product.lowercased(), startingAt: 0, language: preferences.language,
                       wrap: false, inSpellDocumentWithTag: spellDocument, wordCount: nil).location != NSNotFound) != nil) {
                // Company lists contain ordinary nouns (e.g. Business). A typo in an
                // ordinary word must use prose casing, just like the correctly typed word.
                return Assessment(misspelled: true, replacement: product, automatic: true)
            }
            let preserveCompound = CompoundSpellingPolicy.prefersUnchangedLetters(for: word, guesses: guesses)
            var confident = preserveCompound ? nil : CorrectionPolicy.preferredAutomaticReplacement(for: word, systemCorrection: proposed, guesses: guesses)
            if confident == nil, !preserveCompound, proposed == nil, text != word {
                let isolatedDocument = NSSpellChecker.uniqueSpellDocumentTag()
                let isolated = checker.correction(forWordRange: NSRange(location: 0, length: word.utf16.count),
                    in: word + " ", language: preferences.language, inSpellDocumentWithTag: isolatedDocument)
                let isolatedGuesses = checker.guesses(forWordRange: NSRange(location: 0, length: word.utf16.count),
                    in: word + " ", language: preferences.language, inSpellDocumentWithTag: isolatedDocument) ?? []
                checker.closeSpellDocument(withTag: isolatedDocument)
                confident = CorrectionPolicy.isolatedFallback(for: word, contextualCorrection: proposed,
                    contextualGuesses: guesses, isolatedCorrection: isolated, isolatedGuesses: isolatedGuesses)
            }
            // A lower-ranked prose split (as well, a bit, so far) means the typed letters are
            // two real words. Only a repair that keeps every typed letter may still proceed.
            var phrase: String?
            if let repair = confident, let prose = CompoundSpellingPolicy.prosePhrase(for: word, guesses: guesses),
               !CompoundSpellingPolicy.preservesTypedLetters(of: word, in: repair) {
                confident = nil
                phrase = prose
            }
            // A native consonant substitution or deletion yields to a ranked repair that keeps
            // every typed letter (higer → higher, not tiger). Several such repairs abstain.
            if let repair = confident {
                let alternatives = CorrectionPolicy.letterPreservingAlternatives(for: word, accepted: repair, guesses: guesses)
                    .filter { checker.checkSpelling(of: $0, startingAt: 0, language: preferences.language,
                                                    wrap: false, inSpellDocumentWithTag: spellDocument, wordCount: nil).location == NSNotFound }
                if alternatives.count == 1 { confident = alternatives[0] } else if alternatives.count > 1 { confident = nil }
            }
            // Dictionary guesses can cover larger mistakes, but never apply them without approval.
            let review = preserveCompound ? guesses.first : (confident ?? phrase ?? proposed ?? guesses.first)
            answer = Assessment(misspelled: true, replacement: review, automatic: confident != nil)
        }
        if cache.count >= 256 { cache.removeAll(keepingCapacity: true) }
        cache[key] = answer
        return answer
    }

    func approve() {
        guard let proposal = pending else { return }
        pending = nil
        apply(proposal)
    }

    private func apply(_ proposal: Proposal) {
        perform(proposal, isUndo: false, andIgnore: false)
    }

    /// Editing goes through the receiving app's normal keyboard pipeline. Accessibility
    /// only reads the field; a failed check can never leave a word selected.
    private func perform(_ proposal: Proposal, isUndo: Bool, andIgnore: Bool, boundaryID: UInt64? = nil, contextual: Bool = false) {
        indicator.hide()
        flaggedWord = nil
        #if DEBUG
        lastProposal = proposal
        #endif
        // A word that ends at the caret is the one still being typed (field-start
        // capitalization and its undo); every other edit must sit before a delimiter.
        let atCaret = NSMaxRange(proposal.range) == proposal.snapshot.text.utf16.count
        var transportAvailable = monitor.isRunning
        #if DEBUG
        if editTransport != nil { transportAvailable = true }
        #endif
        guard !inFlight, preferences.enabled, transportAvailable, Date().timeIntervalSince(proposal.created) < 30,
              let plan = KeyboardReplacementPlan.make(text: proposal.snapshot.text, wordRange: proposal.range, replacement: proposal.replacement,
                                                      reversingExpansion: isUndo, atCaret: atCaret) else {
            retireAutoCapital(for: proposal)
            if let boundaryID { backlog.remove(boundaryID); scheduleCheck() }
            status = "Text changed or field unsupported — skipped"
            suggestionApplyFailed("the caret position does not allow a safe edit (the caret must be within about 96 plain characters after the span, with no selection); move the caret closer or edit by hand")
            onChange?()
            return
        }
        #if DEBUG
        if let editTransport {
            // Test transport: the same records as the real revalidation, then the host's
            // text (or nil) stands in for the posted events and the verification read.
            inFlight = true
            let field = rewriteFieldID(for: proposal.snapshot)
            var protectionID: UUID?
            if isUndo {
                manualRewrites.noteManualEdit(now: ProcessInfo.processInfo.systemUptime)
            } else {
                protectionID = manualRewrites.recordPostedCorrection(field: field, text: proposal.snapshot.text,
                    windowStart: proposal.snapshot.windowStart, range: proposal.range, replacement: proposal.replacement,
                    now: ProcessInfo.processInfo.systemUptime, caseOnly: proposal.capitalizesFieldStart)
            }
            let epoch = sessionEpoch
            editTransport(proposal, plan) { [weak self] observed in
                guard let self, self.sessionEpoch == epoch else { return }
                guard let observed else {
                    if let protectionID { self.manualRewrites.remove(protectionID) }
                    self.retryUnpostedEdit(proposal, boundaryID: boundaryID)
                    return
                }
                self.retireAutoCapital(for: proposal)
                if let boundaryID { self.backlog.recordCorrection(boundaryID, contextual: contextual) }
                guard AccessibilityText.confirmedText(observed: observed, expected: plan.expectedText) != nil else {
                    self.inFlight = false
                    self.backlog.reset()
                    if let protectionID { self.manualRewrites.remove(protectionID) }
                    self.status = "Editor did not confirm correction"
                    self.suggestionApplyFailed("the editor did not confirm the edit")
                    return
                }
                if isUndo { self.undoProposal = nil; self.undoAnchor = nil }
                self.completeVerifiedEdit(proposal, observed: observed, isUndo: isUndo, andIgnore: andIgnore)
            }
            return
        }
        #endif
        inFlight = true
        let epoch = sessionEpoch
        let ticket = generation
        var protectionID: UUID?
        monitor.replace(plan, validate: { [weak self] in
            guard let self, self.generation == ticket, self.preferences.enabled,
                  KeyboardMonitor.safeInputSource,
                  let bundle = NSRunningApplication(processIdentifier: proposal.snapshot.pid)?.bundleIdentifier,
                  !self.preferences.excludedApps.contains(bundle) else { return false }
            guard AccessibilityText.stillMatches(proposal.snapshot) else { return false }
            let field = self.rewriteFieldID(for: proposal.snapshot)
            if isUndo {
                self.manualRewrites.noteManualEdit(now: ProcessInfo.processInfo.systemUptime)
            } else {
                protectionID = self.manualRewrites.recordPostedCorrection(field: field, text: proposal.snapshot.text,
                    windowStart: proposal.snapshot.windowStart, range: proposal.range, replacement: proposal.replacement,
                    now: ProcessInfo.processInfo.systemUptime, caseOnly: proposal.capitalizesFieldStart)
            }
            return true
        }, completion: { [weak self] posted in
            guard let self, self.sessionEpoch == epoch else { return }
            guard posted else {
                self.retryUnpostedEdit(proposal, boundaryID: boundaryID)
                return
            }
            self.retireAutoCapital(for: proposal)
            if let boundaryID {
                self.backlog.recordCorrection(boundaryID, contextual: contextual)
                self.attemptedBoundaries.removeValue(forKey: boundaryID)
            }
            if isUndo { self.undoProposal = nil; self.undoAnchor = nil }
            // A posted edit is never repeated, even if the editor is slow to confirm it.
            self.verify(proposal, plan: plan, epoch: epoch, isUndo: isUndo, andIgnore: andIgnore, protectionID: protectionID, attempt: 0)
        })
    }

    private func retryUnpostedEdit(_ proposal: Proposal, boundaryID: UInt64?) {
        inFlight = false
        if let boundaryID {
            let attempts = attemptedBoundaries[boundaryID, default: 0] + 1
            attemptedBoundaries[boundaryID] = attempts
            if attempts >= 3 {
                backlog.remove(boundaryID)
                retireAutoCapital(for: proposal)
            }
        } else {
            // Approval actions have no queued boundary to retry.
            retireAutoCapital(for: proposal)
            suggestionApplyFailed("the edit was cancelled before it could be posted; try again")
        }
        scheduleCheck()
    }

    private func verify(_ proposal: Proposal, plan: KeyboardReplacementPlan, epoch: UInt64,
                        isUndo: Bool, andIgnore: Bool, protectionID: UUID?, attempt: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(attempt == 0 ? 40 : 100)) { [weak self] in
            guard let self, self.sessionEpoch == epoch else { return }
            guard let observed = AccessibilityText.verifies(snapshot: proposal.snapshot, expectedText: plan.expectedText, expectedCaret: plan.expectedCaret) else {
                if attempt < 2 {
                    self.verify(proposal, plan: plan, epoch: epoch, isUndo: isUndo, andIgnore: andIgnore, protectionID: protectionID, attempt: attempt + 1)
                } else {
                    self.inFlight = false
                    self.backlog.reset()
                    if let protectionID { self.manualRewrites.remove(protectionID) }
                    RuntimeDiagnostics.record("correction unconfirmed")
                    self.status = "Editor did not confirm correction"
                    self.suggestionApplyFailed("the editor did not confirm the edit")
                    self.onChange?()
                }
                return
            }
            self.completeVerifiedEdit(proposal, observed: observed, isUndo: isUndo, andIgnore: andIgnore)
        }
    }

    func undo(andIgnore: Bool = false) {
        pendingDeletionRestart = false
        guard !inFlight, let saved = undoProposal, let anchor = undoAnchor else { return }
        resetTyping()
        var fresh: AccessibilityText.Snapshot?
        var sameApp = NSWorkspace.shared.frontmostApplication?.processIdentifier == saved.snapshot.pid
        #if DEBUG
        if let snapshotProvider { fresh = snapshotProvider(); sameApp = fresh != nil }
        #endif
        if fresh == nil, sameApp { fresh = AccessibilityText.snapshot(pid: saved.snapshot.pid) }
        guard Date().timeIntervalSince(saved.created) < 300, sameApp, let current = fresh,
              CFEqual(current.element, saved.snapshot.element),
              let range = anchor.matchingRange(in: current.text, windowStart: current.windowStart) else {
            status = "Undo unavailable: return to the unchanged text near the correction"
            onChange?()
            return
        }
        if let extended = caseOnlyUndoRange(for: saved, in: current.text, at: range) {
            perform(Proposal(snapshot: current, range: extended.range, original: extended.original,
                             replacement: extended.replacement, created: Date()), isUndo: true, andIgnore: andIgnore)
            return
        }
        perform(Proposal(snapshot: current, range: range, original: saved.original,
                         replacement: saved.replacement, created: Date()), isUndo: true, andIgnore: andIgnore)
    }

    func ignorePendingWord() {
        guard let word = pending?.original ?? flaggedWord else { return }
        ignore(word: word)
        self.pending = nil
        flaggedWord = nil
        status = "Word ignored"
        onChange?()
    }

    deinit { monitor.stop() }
}
