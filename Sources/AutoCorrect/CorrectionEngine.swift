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
        status = monitor.start() ? "Ready" : "Keyboard access unavailable — restart AutoCorrect"
        onChange?()
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
              let bundleID = app.bundleIdentifier, !preferences.excludedApps.contains(bundleID),
              let snapshot = AccessibilityText.snapshot(pid: app.processIdentifier),
              let candidate = CorrectionPolicy.candidate(in: snapshot.text, caret: (snapshot.text as NSString).length, caseExceptions: Set(preferences.customCorrections.keys)),
              // A clipped window must not turn the end of an identifier into an apparent whole word.
              snapshot.windowStart == 0 || candidate.range.location > 0,
              !preferences.ignoredWords.contains(UserDictionary.normalizedKey(candidate.original)) else { return }
        let result = assessment(candidate.original)
        guard result.misspelled else { return }
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

    func suggestion(_ word: String) -> String? {
        let result = assessment(word)
        return result.misspelled && result.automatic ? result.replacement : nil
    }

    private func assessment(_ word: String) -> Assessment {
        let normalized = UserDictionary.normalizedKey(word)
        if preferences.ignoredWords.contains(normalized) { return Assessment(misspelled: false, replacement: nil, automatic: false) }
        if let custom = preferences.customCorrections[normalized] {
            return Assessment(misspelled: custom != word, replacement: custom, automatic: true)
        }
        let key = preferences.language + ":" + word
        if let value = cache[key] { return value }
        let checker = NSSpellChecker.shared
        let misspelled = checker.checkSpelling(of: word, startingAt: 0, language: preferences.language, wrap: false, inSpellDocumentWithTag: spellDocument, wordCount: nil)
        var answer = Assessment(misspelled: false, replacement: nil, automatic: false)
        if misspelled.location != NSNotFound {
            let wordRange = NSRange(location: 0, length: (word as NSString).length)
            let proposed = checker.correction(forWordRange: wordRange, in: word, language: preferences.language, inSpellDocumentWithTag: spellDocument)
            let confident = proposed.flatMap { CorrectionPolicy.confidentReplacement(for: word, suggestion: $0) }
            // Dictionary guesses can cover larger mistakes, but never apply them without approval.
            let review = confident ?? proposed ?? checker.guesses(forWordRange: wordRange, in: word, language: preferences.language, inSpellDocumentWithTag: spellDocument)?.first
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
        indicator.hide()
        flaggedWord = nil
        guard preferences.enabled, monitor.isRunning, Date().timeIntervalSince(proposal.created) < 30,
              KeyboardMonitor.safeInputSource,
              let bundle = NSRunningApplication(processIdentifier: proposal.snapshot.pid)?.bundleIdentifier,
              !preferences.excludedApps.contains(bundle),
              AccessibilityText.replace(snapshot: proposal.snapshot, localRange: proposal.range, with: proposal.replacement) else {
            status = "Text changed or field unsupported — skipped"
            onChange?()
            return
        }
        correctionCount += 1
        status = "Ready"
        if let updated = AccessibilityText.snapshot(pid: proposal.snapshot.pid) {
            let newRange = NSRange(location: proposal.snapshot.windowStart + proposal.range.location - updated.windowStart, length: (proposal.replacement as NSString).length)
            if newRange.location >= 0, NSMaxRange(newRange) <= (updated.text as NSString).length,
               (updated.text as NSString).substring(with: newRange) == proposal.replacement {
                undoProposal = Proposal(snapshot: updated, range: newRange, original: proposal.replacement, replacement: proposal.original, created: Date())
            }
        }
        onChange?()
    }

    func undo(andIgnore: Bool = false) {
        guard let proposal = undoProposal else { return }
        undoProposal = nil
        guard monitor.isRunning, Date().timeIntervalSince(proposal.created) < 30, KeyboardMonitor.safeInputSource,
              AccessibilityText.replace(snapshot: proposal.snapshot, localRange: proposal.range, with: proposal.replacement) else {
            status = "Text changed — undo skipped"
            onChange?()
            return
        }
        correctionCount = max(0, correctionCount - 1)
        if andIgnore { preferences.ignoredWords.insert(UserDictionary.normalizedKey(proposal.replacement)) }
        status = "Correction undone"
        onChange?()
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
