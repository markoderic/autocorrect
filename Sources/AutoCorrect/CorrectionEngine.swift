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
    private var sessionEpoch: UInt64 = 0
    private var work: DispatchWorkItem?
    private var backlog = CompletedWordBacklog()
    private var inFlight = false
    private var readAttempts = 0
    private var undoAnchor: CorrectionUndoAnchor?
    private var attemptedBoundaries: [UInt64: Int] = [:]
    private var manualRewrites = ManualRewriteProtection()
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
    #if DEBUG
    var nativeAssessmentObserver: ((String, Bool, String?, [String]) -> Void)?
    /// Test hook: feeds keystrokes to the boundary queue without the event tap.
    func debugAppendKeys(_ text: String) { for character in text { backlog.append(String(character)) } }
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

    init(preferences: Preferences) {
        self.preferences = preferences
        monitor.onKey = { [weak self] text, flags, key in self?.key(text, flags: flags, keyCode: key) }
        monitor.onMouse = { [weak self] in
            self?.manualRewrites.noteManualEdit(now: ProcessInfo.processInfo.systemUptime)
            self?.resetTyping(); self?.indicator.hide()
            // Clicks and scrolling move text under the marks; redraw once the view settles,
            // and scan the region that may have scrolled into view.
            self?.scheduleRender(delay: 250)
            self?.scheduleScan(delay: 450)
        }
        monitor.onUndo = { [weak self] in
            guard let self, self.undoProposal != nil, !self.inFlight else { return false }
            DispatchQueue.main.async { self.undo() }
            return true
        }
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
        resetTyping()
        manualRewrites.reset()
        rewriteField = nil
        pending = nil
        undoProposal = nil
        undoAnchor = nil
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
    }

    private func key(_ text: String?, flags: CGEventFlags, keyCode: Int64) {
        if [51, 117].contains(keyCode) || (keyCode == 6 && flags.contains(.maskCommand) && !flags.contains(.maskShift)) {
            manualRewrites.noteManualEdit(now: ProcessInfo.processInfo.systemUptime)
        }
        cancelScheduled()
        let hadProposal = pending != nil || flaggedWord != nil
        pending = nil
        flaggedWord = nil
        // Text moves while typing; marks stay in the model and are redrawn after a pause.
        indicator.hide()
        if hadProposal { status = "Ready"; onChange?() }
        if keyCode == 9, flags.contains(.maskCommand) { scheduleScan(delay: 600) }   // paste
        guard preferences.enabled, !flags.contains(.maskCommand), !flags.contains(.maskControl), !flags.contains(.maskAlternate),
              ![36, 48, 51, 53, 76, 115, 116, 117, 119, 121, 123, 124, 125, 126].contains(keyCode),
              let text, TypingTypography.isSupportedKeystroke(text) else { resetTyping(); scheduleRender(delay: 300); return }
        backlog.append(text)
        readAttempts = 0
        attemptedBoundaries = attemptedBoundaries.filter { entry in backlog.boundaries.contains { $0.id == entry.key } }
        scheduleCheck()
    }

    private func scheduleCheck(delay: Int = 18) {
        guard !inFlight, !backlog.boundaries.isEmpty else { return }
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
        markSet.reconcile(text: snapshot.text, windowStart: snapshot.windowStart)
        overridden.reconcile(text: snapshot.text, windowStart: snapshot.windowStart)
        defer { scheduleRender(delay: 120); scheduleScan(delay: 500) }
        while let boundary = backlog.boundaries.first {
            guard let completed = boundary.completedPrefix(in: snapshot.text) else {
                if retryRead() { return }
                backlog.remove(boundary.id)
                continue
            }
            if !boundary.spellingCorrected, let candidate = candidate(in: completed),
               snapshot.windowStart == 0 || candidate.range.location > 0,
               !preferences.ignoredWords.contains(UserDictionary.normalizedKey(candidate.original)) {
                if isManualRewrite(candidate, snapshot: snapshot) {
                    // The user deliberately restored this spelling here: no correction, no mark.
                    noteOverride(SpellingMark(location: snapshot.windowStart + candidate.range.location, word: candidate.original))
                } else {
                    let result = assessment(candidate.original, context: completed, range: candidate.range)
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
    }

    private func retryRead() -> Bool {
        guard readAttempts < 3 else { return false }
        readAttempts += 1
        scheduleCheck(delay: 40)
        return true
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
              let candidate = ContextualWritingRules.candidate(in: text),
              !preferences.ignoredWords.contains(UserDictionary.normalizedKey(candidate.original)),
              preferences.customCorrections[UserDictionary.normalizedKey(candidate.original)] == nil else { return nil }
        return candidate
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
        case .valueChanged: scheduleScan(delay: 500)
        case .selectionChanged: scheduleRender(delay: 150)
        case .windowMoved, .windowResized: indicator.hide(); scheduleRender(delay: 120)
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
        let task = DispatchWorkItem { [weak self] in self?.renderMarks() }
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

    private func assessment(_ word: String, context: String? = nil, range: NSRange? = nil) -> Assessment {
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
              let sentence = SentenceCapitalization.candidate(in: context, caret: context.utf16.count), sentence.range == range,
              let chosen = spelling.replacement ?? (spelling.misspelled ? nil : word),
              let capitalized = SentenceCapitalization.replacement(for: chosen) else { return spelling }
        return Assessment(misspelled: true, replacement: capitalized, automatic: !spelling.misspelled || spelling.automatic)
    }

    private func spellingAssessment(_ word: String, context: String?, range: NSRange?) -> Assessment {
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
        guard !inFlight, preferences.enabled, monitor.isRunning, Date().timeIntervalSince(proposal.created) < 30,
              let plan = KeyboardReplacementPlan.make(text: proposal.snapshot.text, wordRange: proposal.range, replacement: proposal.replacement, reversingExpansion: isUndo) else {
            if let boundaryID { backlog.remove(boundaryID); scheduleCheck() }
            status = "Text changed or field unsupported — skipped"
            onChange?()
            return
        }
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
                    now: ProcessInfo.processInfo.systemUptime)
            }
            return true
        }, completion: { [weak self] posted in
            guard let self, self.sessionEpoch == epoch else { return }
            guard posted else {
                self.inFlight = false
                if let boundaryID {
                    let attempts = self.attemptedBoundaries[boundaryID, default: 0] + 1
                    self.attemptedBoundaries[boundaryID] = attempts
                    if attempts >= 3 { self.backlog.remove(boundaryID) }
                }
                self.scheduleCheck()
                return
            }
            if let boundaryID {
                self.backlog.recordCorrection(boundaryID, contextual: contextual)
                self.attemptedBoundaries.removeValue(forKey: boundaryID)
            }
            if isUndo { self.undoProposal = nil; self.undoAnchor = nil }
            // A posted edit is never repeated, even if the editor is slow to confirm it.
            self.verify(proposal, plan: plan, epoch: epoch, isUndo: isUndo, andIgnore: andIgnore, protectionID: protectionID, attempt: 0)
        })
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
                    self.onChange?()
                }
                return
            }
            self.inFlight = false
            RuntimeDiagnostics.record("correction verified")
            self.correctionCount = max(0, self.correctionCount + (isUndo ? -1 : 1))
            let editLocation = proposal.snapshot.windowStart + proposal.range.location
            self.noteAppliedEdit(location: editLocation, length: proposal.original.utf16.count,
                                 replacementLength: proposal.replacement.utf16.count)
            if isUndo {
                // The user asked for the original spelling back: keep that occurrence unmarked.
                self.noteOverride(SpellingMark(location: editLocation, word: proposal.replacement))
            }
            if andIgnore {
                self.preferences.ignoredWords.insert(UserDictionary.normalizedKey(proposal.replacement))
                self.markSet.remove(word: proposal.replacement)
            }
            if !isUndo {
                // Anchor undo to the host's actual text: it may have restyled our punctuation.
                var bounded = observed[...]
                while bounded.utf16.count > 256 { bounded.removeFirst() }
                let clipped = observed.utf16.count - bounded.utf16.count
                let reverseRange = NSRange(location: proposal.range.location, length: proposal.replacement.utf16.count)
                self.undoAnchor = CorrectionUndoAnchor(text: String(bounded), windowStart: proposal.snapshot.windowStart + clipped,
                    range: NSRange(location: reverseRange.location - clipped, length: reverseRange.length))
                self.undoProposal = Proposal(snapshot: proposal.snapshot, range: reverseRange,
                    original: (observed as NSString).substring(with: reverseRange), replacement: proposal.original, created: Date())
            }
            self.status = isUndo ? "Correction undone" : "Ready"
            self.onChange?()
            self.scheduleCheck()
        }
    }

    func undo(andIgnore: Bool = false) {
        guard !inFlight, let saved = undoProposal, let anchor = undoAnchor else { return }
        resetTyping()
        guard Date().timeIntervalSince(saved.created) < 300,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == saved.snapshot.pid,
              let current = AccessibilityText.snapshot(pid: saved.snapshot.pid),
              CFEqual(current.element, saved.snapshot.element),
              let range = anchor.matchingRange(in: current.text, windowStart: current.windowStart) else {
            status = "Undo unavailable: return to the unchanged text near the correction"
            onChange?()
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
