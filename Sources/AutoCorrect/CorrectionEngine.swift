import AppKit
import AutoCorrectCore

final class CorrectionEngine {
    struct Proposal {
        let snapshot: AccessibilityText.Snapshot
        let range: NSRange
        let original: String
        let replacement: String
        let created: Date
    }
    let preferences: Preferences
    var onChange: (() -> Void)?
    private(set) var pending: Proposal?
    private(set) var undoProposal: Proposal?
    private(set) var flaggedWord: String?
    private(set) var correctionCount = 0
    private(set) var status = "Ready"
    private var generation: UInt64 = 0
    private var work: DispatchWorkItem?
    private let spellDocument = NSSpellChecker.uniqueSpellDocumentTag()
    private struct Assessment {
        let misspelled: Bool
        let replacement: String?
        let automatic: Bool
    }
    private var cache: [String: Assessment] = [:]
    private let indicator = SpellingIndicator()
    private let monitor = KeyboardMonitor()
    var isRunning: Bool { monitor.isRunning }

    init(preferences: Preferences) {
        self.preferences = preferences
        monitor.onKey = { [weak self] text, flags, key in self?.key(text, flags: flags, keyCode: key) }
        monitor.onMouse = { [weak self] in self?.cancelScheduled(); self?.indicator.hide() }
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
    }

    func focusChanged() {
        invalidate()
        prepareFocusedApplication()
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
        cancelScheduled()
        pending = nil
        undoProposal = nil
        flaggedWord = nil
        indicator.hide()
        if monitor.isRunning { status = "Ready" }
    }

    private func key(_ text: String?, flags: CGEventFlags, keyCode: Int64) {
        cancelScheduled()
        let hadProposal = pending != nil || undoProposal != nil || flaggedWord != nil
        pending = nil
        undoProposal = nil
        flaggedWord = nil
        indicator.hide()
        if hadProposal { status = "Ready"; onChange?() }
        guard preferences.enabled, !flags.contains(.maskCommand), !flags.contains(.maskControl), !flags.contains(.maskAlternate),
              ![36, 48, 76].contains(keyCode), // Return and Tab can submit or change fields.
              let text = text, text.count == 1, let character = text.first,
              CorrectionPolicy.isDelimiter(character) else { return }
        RuntimeDiagnostics.record("boundary observed")
        let ticket = generation
        let task = DispatchWorkItem { [weak self] in
            guard let self = self, self.generation == ticket else { return }
            self.checkBoundary()
        }
        work = task
        // Let the receiving app insert the separator. Fast subsequent typing cancels this check.
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(45), execute: task)
    }

    private func checkBoundary() {
        guard AXIsProcessTrusted(), KeyboardMonitor.safeInputSource,
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let bundleID = app.bundleIdentifier, !preferences.excludedApps.contains(bundleID) else { return }
        AccessibilityText.prepare(app: app)
        guard let snapshot = AccessibilityText.snapshot(pid: app.processIdentifier) else {
            status = "Text access unavailable in \(app.localizedName ?? "this app")"
            onChange?()
            return
        }
        if status.hasPrefix("Text access unavailable") { status = "Ready"; onChange?() }
        guard let candidate = candidate(in: snapshot.text),
              // A clipped window must not turn the end of an identifier into an apparent whole word.
              snapshot.windowStart == 0 || candidate.range.location > 0,
              !preferences.ignoredWords.contains(UserDictionary.normalizedKey(candidate.original)) else { return }
        let result = assessment(candidate.original, context: snapshot.text, range: candidate.range)
        guard result.misspelled else { RuntimeDiagnostics.record("no correction needed"); return }
        RuntimeDiagnostics.record("correction assessed")
        flaggedWord = candidate.original
        guard let replacement = result.replacement else {
            status = "Possible misspelling: \(candidate.original)"
            if preferences.showsSpellingIndicators { indicator.show(snapshot: snapshot, range: candidate.range) }
            onChange?()
            return
        }
        let proposal = Proposal(snapshot: snapshot, range: candidate.range, original: candidate.original, replacement: replacement, created: Date())
        if preferences.asksBeforeCorrecting || !result.automatic {
            pending = proposal
            status = "Suggestion ready"
            if preferences.showsSpellingIndicators { indicator.show(snapshot: snapshot, range: candidate.range) }
            onChange?()
        } else {
            apply(proposal)
        }
    }

    private func candidate(in text: String) -> CorrectionCandidate? {
        CorrectionPolicy.candidate(in: text, caret: text.utf16.count, caseExceptions: Set(preferences.customCorrections.keys))
            ?? (preferences.capitalizesAfterPeriod ? SentenceCapitalization.candidate(in: text, caret: text.utf16.count) : nil)
    }

    /// Uses exactly the same completed-word assessment as the keyboard path, without edits.
    func suggestion(in completedText: String) -> String? {
        guard let candidate = candidate(in: completedText) else { return nil }
        let result = assessment(candidate.original, context: completedText, range: candidate.range)
        return result.misspelled && result.automatic ? result.replacement : nil
    }

    func suggestion(_ word: String) -> String? {
        let result = assessment(word)
        return result.misspelled && result.automatic ? result.replacement : nil
    }

    private func assessment(_ word: String, context: String? = nil, range: NSRange? = nil) -> Assessment {
        let normalized = UserDictionary.normalizedKey(word)
        if preferences.ignoredWords.contains(normalized) { return Assessment(misspelled: false, replacement: nil, automatic: false) }
        if let custom = preferences.customCorrections[normalized] {
            return Assessment(misspelled: custom != word, replacement: custom, automatic: true)
        }
        let spelling = spellingAssessment(word, context: context, range: range)
        guard preferences.capitalizesAfterPeriod, let context, let range,
              let sentence = SentenceCapitalization.candidate(in: context, caret: context.utf16.count), sentence.range == range,
              let chosen = spelling.replacement ?? (spelling.misspelled ? nil : word),
              let capitalized = SentenceCapitalization.replacement(for: chosen) else { return spelling }
        return Assessment(misspelled: true, replacement: capitalized, automatic: !spelling.misspelled || spelling.automatic)
    }

    private func spellingAssessment(_ word: String, context: String?, range: NSRange?) -> Assessment {
        if let writing = EnglishWritingRules.replacement(for: word, language: preferences.language) {
            return Assessment(misspelled: true, replacement: writing, automatic: true)
        }
        let text = context ?? word
        let wordRange = range ?? NSRange(location: 0, length: (word as NSString).length)
        let key = preferences.language + ":" + text + ":" + String(wordRange.location)
        if let value = cache[key] { return value }
        let checker = NSSpellChecker.shared
        let misspelled = checker.checkSpelling(of: word, startingAt: 0, language: preferences.language, wrap: false, inSpellDocumentWithTag: spellDocument, wordCount: nil)
        var answer = Assessment(misspelled: false, replacement: nil, automatic: false)
        if misspelled.location != NSNotFound {
            let proposed = checker.correction(forWordRange: wordRange, in: text, language: preferences.language, inSpellDocumentWithTag: spellDocument)
            let guesses = checker.guesses(forWordRange: wordRange, in: text, language: preferences.language, inSpellDocumentWithTag: spellDocument) ?? []
            let confident = CorrectionPolicy.preferredAutomaticReplacement(for: word, systemCorrection: proposed, guesses: guesses)
            // Dictionary guesses can cover larger mistakes, but never apply them without approval.
            let review = confident ?? proposed ?? guesses.first
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
    private func perform(_ proposal: Proposal, isUndo: Bool, andIgnore: Bool) {
        indicator.hide()
        flaggedWord = nil
        guard preferences.enabled, monitor.isRunning, Date().timeIntervalSince(proposal.created) < 30,
              let plan = KeyboardReplacementPlan.make(text: proposal.snapshot.text, wordRange: proposal.range, replacement: proposal.replacement) else {
            status = "Text changed or field unsupported — skipped"
            onChange?()
            return
        }
        let ticket = generation
        monitor.replace(plan, validate: { [weak self] in
            guard let self, self.generation == ticket, self.preferences.enabled,
                  KeyboardMonitor.safeInputSource,
                  let bundle = NSRunningApplication(processIdentifier: proposal.snapshot.pid)?.bundleIdentifier,
                  !self.preferences.excludedApps.contains(bundle) else { return false }
            return AccessibilityText.stillMatches(proposal.snapshot)
        }, completion: { [weak self] posted in
            guard let self else { return }
            guard posted else {
                if self.generation == ticket {
                    self.status = "Text changed — skipped"
                    self.onChange?()
                }
                return
            }
            // Give the editor time to process its input queue. Verification is read-only:
            // never repeat a deletion or overwrite the field when an editor responds slowly.
            self.verify(proposal, plan: plan, ticket: ticket, isUndo: isUndo, andIgnore: andIgnore, attempt: 0)
        })
    }

    private func verify(_ proposal: Proposal, plan: KeyboardReplacementPlan, ticket: UInt64,
                        isUndo: Bool, andIgnore: Bool, attempt: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(attempt == 0 ? 40 : 100)) { [weak self] in
            guard let self else { return }
            guard AccessibilityText.verifies(snapshot: proposal.snapshot, expectedText: plan.expectedText, expectedCaret: plan.expectedCaret) else {
                if attempt < 2 {
                    self.verify(proposal, plan: plan, ticket: ticket, isUndo: isUndo, andIgnore: andIgnore, attempt: attempt + 1)
                } else if self.generation == ticket {
                    RuntimeDiagnostics.record("correction unconfirmed")
                    self.status = "Editor did not confirm correction"
                    self.onChange?()
                }
                return
            }
            RuntimeDiagnostics.record("correction verified")
            self.correctionCount = max(0, self.correctionCount + (isUndo ? -1 : 1))
            if andIgnore { self.preferences.ignoredWords.insert(UserDictionary.normalizedKey(proposal.replacement)) }
            // Continued typing is fine, but Undo must never act on a newer word.
            if self.generation == ticket {
                self.status = isUndo ? "Correction undone" : "Ready"
                if !isUndo, let updated = AccessibilityText.snapshot(pid: proposal.snapshot.pid),
                   updated.caret == proposal.snapshot.windowStart + plan.expectedCaret {
                    let location = proposal.snapshot.windowStart + proposal.range.location - updated.windowStart
                    if location >= 0 {
                        self.undoProposal = Proposal(snapshot: updated,
                            range: NSRange(location: location, length: (proposal.replacement as NSString).length),
                            original: proposal.replacement, replacement: proposal.original, created: Date())
                    }
                }
            }
            self.onChange?()
        }
    }

    func undo(andIgnore: Bool = false) {
        guard let proposal = undoProposal else { return }
        undoProposal = nil
        perform(proposal, isUndo: true, andIgnore: andIgnore)
    }

    func ignorePendingWord() {
        guard let word = pending?.original ?? flaggedWord else { return }
        preferences.ignoredWords.insert(UserDictionary.normalizedKey(word))
        self.pending = nil
        flaggedWord = nil
        indicator.hide()
        status = "Word ignored"
        onChange?()
    }

    deinit { monitor.stop(); NSSpellChecker.shared.closeSpellDocument(withTag: spellDocument) }
}
