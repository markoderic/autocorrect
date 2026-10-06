import AppKit
import AutoCorrectCore

/// Sentence-level grammar and punctuation suggestions: one unit (a terminated sentence, or a
/// paused clause) at a time, analyzed after a word boundary or a typing pause, never while an
/// edit is in flight. Exactly one analyzer request runs at a time; a newer request waits and
/// replaces anything still queued, so work never accumulates. A result is published only after
/// the field and the full analyzed text are re-read and found unchanged. Dismissals and undone
/// applications are remembered for unchanged text. It proposes; the engine applies through the
/// guarded transport and reports back whether the edit was verified.
final class SentenceAssistant {
    struct Field: Equatable {
        let pid: pid_t
        let element: AXUIElement
        static func == (lhs: Field, rhs: Field) -> Bool { lhs.pid == rhs.pid && CFEqual(lhs.element, rhs.element) }
    }
    struct Active: Equatable {
        let suggestion: SentenceSuggestion
        /// Absolute UTF-16 location of the analyzed sentence in the editor.
        let sentenceLocation: Int
        let field: Field
        let created: Date
        var spanLocation: Int { sentenceLocation + suggestion.range.location }
        var sentenceRange: NSRange { NSRange(location: sentenceLocation, length: suggestion.sentence.utf16.count) }
    }
    private struct Request { let sentence: String; let location: Int; let field: Field; let reason: String }
    private struct Dismissal: Hashable { let sentence: String; let spanLocation: Int; let replacement: String }

    var analyzer: SentenceAnalyzer
    /// Current user settings, read at each step.
    var grammarEnabled: () -> Bool = { true }
    var punctuationEnabled: () -> Bool = { true }
    /// Bounded read of the editor at an absolute range (nil when unreadable), for publish-time
    /// and render-time verification.
    var contextReader: (Field, NSRange) -> String? = { _, _ in nil }
    /// A fresh caret snapshot verifies that an unterminated clause has not grown since analysis.
    var snapshotReader: (Field) -> AccessibilityText.Snapshot? = { _ in nil }
    /// Whether the given field is still the focused field of the frontmost app.
    var fieldFocused: (Field) -> Bool = { _ in false }
    /// Whether a span may not be proposed for replacement (ignored words, kept occurrences).
    var isSpanProtected: (Field, Int, String) -> Bool = { _, _, _ in false }
    /// Called on the main queue whenever `active`, `status`, `isAnalyzing` or `applying` changes.
    var onChange: (() -> Void)?

    private(set) var active: Active?
    /// The suggestion whose Apply is in progress; it stays until the edit is verified or fails.
    private(set) var applying: UUID?
    private(set) var isAnalyzing = false
    private(set) var status = "Sentence suggestions: idle"
    private var epoch: UInt64 = 0
    private var running: Request?
    private var queued: Request?
    private var task: Task<Void, Never>?
    private var lastAnalyzed: Request?
    private var dismissed: [Dismissal] = []
    private var pauseWork: DispatchWorkItem?
    static let pauseDelay: TimeInterval = 1.2
    static let maximumDismissals = 32

    init(analyzer: SentenceAnalyzer) {
        self.analyzer = analyzer
    }

    var isEnabled: Bool { grammarEnabled() || punctuationEnabled() }

    var availabilityText: String {
        guard isEnabled else { return "Sentence suggestions: off" }
        return "Sentence analysis: " + analyzer.availability.summary
    }

    // MARK: Triggers

    /// Typing continued: re-arm the pause timer. The running request's result, if any, will be
    /// verified against the text as it is when the result arrives.
    func noteTyping(read: @escaping () -> AccessibilityText.Snapshot?) {
        pauseWork?.cancel()
        guard isEnabled else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, let snapshot = read() else { return }
            self.consider(snapshot: snapshot, reason: "pause")
        }
        pauseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pauseDelay, execute: work)
    }

    /// A completed-word boundary was processed with this snapshot.
    func noteBoundary(snapshot: AccessibilityText.Snapshot) {
        consider(snapshot: snapshot, reason: "boundary")
    }

    /// Finds the eligible unit at the end of the snapshot (a terminated sentence; after a pause
    /// also a longer unterminated clause that begins inside the window) and requests analysis if
    /// it is new. A request made while another runs replaces whatever was queued.
    func consider(snapshot: AccessibilityText.Snapshot, reason: String) {
        guard isEnabled, applying == nil else { return }
        guard let (sentence, range) = SuggestionValidator.analysisUnit(in: snapshot.text, windowStart: snapshot.windowStart,
                                                                        allowUnterminated: reason == "pause") else { return }
        let field = Field(pid: snapshot.pid, element: snapshot.element)
        let location = snapshot.windowStart + range.location
        let request = Request(sentence: sentence, location: location, field: field, reason: reason)
        if let last = lastAnalyzed, sameUnit(last, request) { return }
        if let active, active.suggestion.sentence == sentence, active.sentenceLocation == location, active.field == field { return }
        if let running {
            if sameUnit(running, request) { return }
            // Coalesce: only the latest eligible context waits; the running result is obsolete.
            queued = request
            epoch &+= 1
            task?.cancel()
            status = "Sentence suggestions: analyzing (waiting for the previous analysis)"
            RuntimeDiagnostics.record("sentence analysis queued (\(reason))")
            onChange?()
            return
        }
        start(request)
    }

    private func sameUnit(_ a: Request, _ b: Request) -> Bool {
        a.sentence == b.sentence && a.location == b.location && a.field == b.field
    }

    private func start(_ request: Request) {
        epoch &+= 1
        let ticket = epoch
        running = request
        lastAnalyzed = request
        isAnalyzing = true
        status = "Sentence suggestions: analyzing (\(request.reason))"
        RuntimeDiagnostics.record("sentence analysis started (\(request.reason), \(request.sentence.utf16.count) units)")
        onChange?()
        let analyzer = self.analyzer
        task = Task { [weak self] in
            var outcome: Result<[ProposedEdit], Error>
            do { outcome = .success(try await analyzer.analyze(sentence: request.sentence)) } catch { outcome = .failure(error) }
            DispatchQueue.main.async { self?.finish(ticket: ticket, request: request, outcome: outcome) }
        }
    }

    /// Every analyzer completion lands here, stale or not: the request gate opens and the
    /// queued request (if any) starts. Only a current result that still matches the live field
    /// is published.
    private func finish(ticket: UInt64, request: Request, outcome: Result<[ProposedEdit], Error>) {
        running = nil
        task = nil
        isAnalyzing = false
        defer {
            if let next = queued { queued = nil; start(next) } else { onChange?() }
        }
        guard ticket == epoch else {
            RuntimeDiagnostics.record("sentence analysis result discarded (stale)")
            return
        }
        switch outcome {
        case .failure(let error):
            status = "Sentence suggestions: analysis failed (\(String(describing: error).prefix(60)))"
            RuntimeDiagnostics.record("sentence analysis failed")
        case .success(let edits):
            // Publish-time verification: the field must still be focused and the exact analyzed
            // text must still be where it was. Unreadable text is not evidence either way, so
            // nothing is published; the next trigger analyzes afresh.
            guard applying == nil else { lastAnalyzed = nil; return }
            guard let matches = matchesContext(sentence: request.sentence, location: request.location, field: request.field) else {
                status = "Sentence suggestions: result not shown (text could not be verified)"
                RuntimeDiagnostics.record("sentence analysis result discarded (unverifiable)"); lastAnalyzed = nil; return
            }
            guard matches else {
                status = "Sentence suggestions: result discarded (text changed)"
                RuntimeDiagnostics.record("sentence analysis result discarded (changed)"); lastAnalyzed = nil; return
            }
            let options = SuggestionValidator.Options(allowGrammar: grammarEnabled(), allowPunctuation: punctuationEnabled())
            let suggestions = SuggestionValidator.validate(sentence: request.sentence, edits: edits, options: options).filter { suggestion in
                let spanLocation = request.location + suggestion.range.location
                return !dismissed.contains(Dismissal(sentence: request.sentence, spanLocation: spanLocation, replacement: suggestion.replacement))
                    && !isSpanProtected(request.field, spanLocation, suggestion.original)
            }
            RuntimeDiagnostics.record("sentence analysis finished: \(edits.count) proposed, \(suggestions.count) accepted")
            if let first = suggestions.first {
                active = Active(suggestion: first, sentenceLocation: request.location, field: request.field, created: Date())
                status = "Sentence suggestion: \(first.original) → \(first.replacement)"
            } else {
                status = edits.isEmpty ? "Sentence suggestions: nothing to suggest" : "Sentence suggestions: proposals did not pass validation or were protected"
            }
        }
    }

    // MARK: Lifecycle

    /// A completed sentence can remain valid when a later sentence is typed. A paused clause
    /// has no such boundary: its entire current unit must still match, not only its old prefix.
    private func matchesContext(sentence: String, location: Int, field: Field) -> Bool? {
        guard fieldFocused(field),
              let text = contextReader(field, NSRange(location: location, length: sentence.utf16.count)) else { return nil }
        guard text == sentence else { return false }
        if SuggestionValidator.lastCompleteSentence(in: sentence) != nil { return true }
        guard let snapshot = snapshotReader(field) else { return nil }
        guard snapshot.pid == field.pid, CFEqual(snapshot.element, field.element),
              let unit = SuggestionValidator.analysisUnit(in: snapshot.text, windowStart: snapshot.windowStart,
                                                         allowUnterminated: true) else { return false }
        return unit.sentence == sentence && snapshot.windowStart + unit.range.location == location
    }

    /// Re-reads the analyzed sentence at its recorded location. A changed sentence withdraws the
    /// suggestion (it may be re-analyzed later). Returns whether it may be shown: an unreadable
    /// text keeps the record but is not shown.
    @discardableResult
    func revalidate() -> Bool {
        guard let current = active else { return false }
        guard let matches = matchesContext(sentence: current.suggestion.sentence, location: current.sentenceLocation, field: current.field) else { return false }
        guard matches, !isSpanProtected(current.field, current.spanLocation, current.suggestion.original) else {
            withdraw(reason: "context changed")
            return false
        }
        return true
    }

    func withdraw(reason: String) {
        guard active != nil else { return }
        active = nil
        applying = nil
        status = "Sentence suggestions: withdrawn (\(reason))"
        RuntimeDiagnostics.record("sentence suggestion withdrawn (\(reason))")
        onChange?()
    }

    /// The user dismissed this suggestion: it stays dismissed for this exact sentence at this
    /// location until the sentence changes.
    func dismiss(id: UUID) -> Bool {
        guard let current = active, current.suggestion.id == id, applying == nil else { return false }
        remember(current)
        active = nil
        status = "Sentence suggestions: dismissed"
        onChange?()
        return true
    }

    private func remember(_ current: Active) {
        dismissed.append(Dismissal(sentence: current.suggestion.sentence, spanLocation: current.spanLocation, replacement: current.suggestion.replacement))
        if dismissed.count > Self.maximumDismissals { dismissed.removeFirst(dismissed.count - Self.maximumDismissals) }
    }

    /// Apply bookkeeping: the suggestion stays active and marked `applying` until the engine
    /// reports a verified edit or a failure.
    func applyStarted(id: UUID) -> Active? {
        guard let current = active, current.suggestion.id == id, applying == nil else { return nil }
        applying = id
        status = "Sentence suggestion: applying…"
        onChange?()
        return current
    }

    func applySucceeded(id: UUID) {
        guard applying == id, let current = active, current.suggestion.id == id else { return }
        // The changed sentence may be analyzed anew, but not re-proposed if the user undoes it.
        lastApplied = current
        active = nil
        applying = nil
        lastAnalyzed = nil
        status = "Sentence suggestion applied"
        onChange?()
    }

    func applyFailed(id: UUID, reason: String) {
        guard applying == id else { return }
        applying = nil
        status = "Sentence suggestion kept; the edit was not made: \(reason)"
        RuntimeDiagnostics.record("sentence suggestion apply failed")
        onChange?()
    }

    /// The most recently applied suggestion, kept so that undoing it is remembered as a
    /// dismissal instead of starting a propose/apply/undo cycle.
    private(set) var lastApplied: Active?

    /// The engine undid an edit at this absolute location whose typed original was `original`.
    func noteUndo(spanLocation: Int, restoredText: String) {
        guard let applied = lastApplied, applied.spanLocation == spanLocation, applied.suggestion.original == restoredText else { return }
        remember(applied)
        lastApplied = nil
        status = "Sentence suggestions: undone; not proposed again for this text"
        onChange?()
    }

    /// Focus or field changed, the engine reset, or settings changed: nothing survives except the
    /// running analyzer call, whose result is discarded when it arrives.
    func invalidate() {
        pauseWork?.cancel()
        task?.cancel()
        epoch &+= 1
        queued = nil
        let hadWork = isAnalyzing || active != nil || applying != nil
        isAnalyzing = false
        active = nil
        applying = nil
        lastAnalyzed = nil
        lastApplied = nil
        dismissed.removeAll()
        status = isEnabled ? "Sentence suggestions: idle" : "Sentence suggestions: off"
        if hadWork { onChange?() }
    }

    #if DEBUG
    var debugTask: Task<Void, Never>? { task }
    var debugHasRunningRequest: Bool { running != nil }
    var debugHasQueuedRequest: Bool { queued != nil }
    func debugForgetLastAnalyzed() { lastAnalyzed = nil }
    #endif
}
