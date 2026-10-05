import AppKit
import ApplicationServices
import AutoCorrectCore

/// Read-only Accessibility snapshots. Text and selections are never changed through AX.
enum AccessibilityText {
    private struct Preparation {
        let launch: Date
        var attempts = 0
        var lastAttempt: TimeInterval = -.infinity
        var finished = false
    }
    private static var preparedApplications: [pid_t: Preparation] = [:]

    static func needsManualAccessibility(bundleURL: URL, fileExists: (String) -> Bool) -> Bool {
        let frameworks = bundleURL.appendingPathComponent("Contents/Frameworks")
        return ["Electron Framework.framework", "Electron.framework", "Chromium Framework.framework",
                "Google Chrome Framework.framework", "Microsoft Edge Framework.framework", "Brave Browser Framework.framework"]
            .contains { fileExists(frameworks.appendingPathComponent($0).path) }
    }

    /// Electron/Chromium can defer their full accessibility tree until an assistive
    /// client requests it. Do this once per process launch: repeated requests reset
    /// Electron's two-second activation debounce. Never turn another client's access off.
    static func prepare(app: NSRunningApplication) {
        guard AXIsProcessTrusted(), let url = app.bundleURL else { return }
        let launch = app.launchDate ?? .distantPast
        let now = ProcessInfo.processInfo.systemUptime
        var state = preparedApplications[app.processIdentifier] ?? Preparation(launch: launch)
        if state.launch != launch { state = Preparation(launch: launch) }
        guard !state.finished, state.attempts < 3, now - state.lastAttempt >= 5 else { return }
        preparedApplications = preparedApplications.filter { NSRunningApplication(processIdentifier: $0.key)?.isTerminated == false }
        guard needsManualAccessibility(bundleURL: url, fileExists: { FileManager.default.fileExists(atPath: $0) }) else {
            state.finished = true
            preparedApplications[app.processIdentifier] = state
            return
        }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(application, 0.05)
        let result = AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        state.attempts += 1
        state.lastAttempt = now
        // A timeout may be transient; allow at most two retries, separated by more than
        // Electron's activation delay. Successful/unsupported requests are never repeated.
        state.finished = result == .success || result == .attributeUnsupported || result == .notImplemented
        preparedApplications[app.processIdentifier] = state
        RuntimeDiagnostics.record(result == .success ? "accessibility tree requested" : "accessibility request failed or unsupported")
    }

    struct Snapshot {
        let element: AXUIElement
        let pid: pid_t
        let text: String
        let windowStart: Int
        let caret: Int
        let physicalKeyCount: UInt32
        /// Multi-line prose control (AXTextArea) rather than a single-line field or combo
        /// box. Field-start capitalization applies only to prose areas: a search box, address
        /// bar, filename or subject field is not a sentence.
        var isTextArea = true
    }

    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
        return result
    }

    static func range(_ element: AXUIElement) -> CFRange? {
        guard let value = attribute(element, kAXSelectedTextRangeAttribute),
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return range
    }

    static func substring(_ element: AXUIElement, range: CFRange) -> String? {
        guard range.location >= 0, (0...512).contains(range.length) else { return nil }
        var input = range
        guard let boxed = AXValueCreate(.cfRange, &input) else { return nil }
        var output: CFTypeRef?
        if AXUIElementCopyParameterizedAttributeValue(element, kAXStringForRangeParameterizedAttribute as CFString, boxed, &output) == .success,
           let string = output as? String, (string as NSString).length == range.length { return string }
        // Some rich editors expose only the attributed range API. Read the same
        // bounded range; never infer a caret or fetch an entire document to find it.
        output = nil
        if AXUIElementCopyParameterizedAttributeValue(element, kAXAttributedStringForRangeParameterizedAttribute as CFString, boxed, &output) == .success,
           let string = attributedSubstring(output, expectedLength: range.length) { return string }
        // Rich contenteditable controls can expose AXValue without NumberOfCharacters.
        // A known oversize value is skipped before fetching it; unknown sizes are checked
        // immediately after the one fallback read. Never infer a caret from the value.
        let count = (attribute(element, kAXNumberOfCharactersAttribute) as? NSNumber)?.intValue
        if let count, !(0...16_384).contains(count) { return nil }
        guard let value = attribute(element, kAXValueAttribute) as? String else { return nil }
        return boundedSubstring(value, reportedCount: count, range: range)
    }

    static func attributedSubstring(_ value: Any?, expectedLength: Int) -> String? {
        guard (0...512).contains(expectedLength), let attributed = value as? NSAttributedString,
              attributed.length == expectedLength else { return nil }
        return attributed.string
    }

    static func boundedSubstring(_ value: String, reportedCount: Int?, range: CFRange) -> String? {
        let length = (value as NSString).length
        guard (0...16_384).contains(length), range.location >= 0, (0...512).contains(range.length),
              range.location <= length, range.length <= length - range.location,
              reportedCount == nil || reportedCount == length else { return nil }
        return (value as NSString).substring(with: NSRange(location: range.location, length: range.length))
    }

    static func focusedElement(pid: pid_t) -> AXUIElement? {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, 0.01)
        guard let element = attribute(application, kAXFocusedUIElementAttribute),
              CFGetTypeID(element) == AXUIElementGetTypeID() else { return nil }
        let result = element as! AXUIElement
        AXUIElementSetMessagingTimeout(result, 0.01)
        return result
    }

    static func snapshot(pid: pid_t) -> Snapshot? {
        let keyCount = physicalKeyCount
        guard let element = focusedElement(pid: pid) else {
            RuntimeDiagnostics.record("snapshot: focus unavailable"); return nil
        }
        guard let role = attribute(element, kAXRoleAttribute) as? String,
              [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role),
              (attribute(element, kAXSubroleAttribute) as? String) != kAXSecureTextFieldSubrole else {
            RuntimeDiagnostics.record("snapshot: unsupported or secure role"); return nil
        }
        guard let selected = range(element), selected.length == 0, selected.location > 0 else {
            RuntimeDiagnostics.record("snapshot: caret unavailable or selection active"); return nil
        }
        let start = max(0, selected.location - 256)
        guard let text = substring(element, range: CFRange(location: start, length: selected.location - start)) else {
            RuntimeDiagnostics.record("snapshot: text range unavailable"); return nil
        }
        guard physicalKeyCount == keyCount else {
            RuntimeDiagnostics.record("snapshot: input changed"); return nil
        }
        RuntimeDiagnostics.record(role == kAXTextAreaRole ? "snapshot available (text area)" : "snapshot available (single-line field)")
        return Snapshot(element: element, pid: pid, text: text, windowStart: start, caret: selected.location,
                        physicalKeyCount: keyCount, isTextArea: role == kAXTextAreaRole)
    }

    /// Evidence that `snapshot.text` is the entire content of the field, so its first word
    /// really is the field's first word. The window must begin at offset zero and the field's
    /// reported length (AXNumberOfCharacters, or the bounded AXValue when the editor has no
    /// count) must end at the caret, allowing one trailing line break that rich editors keep
    /// after the last paragraph. A window offset of zero alone proves nothing: editors that
    /// report offsets relative to a paragraph, or a caret far into a document, fail here.
    /// Costs one or two Accessibility reads; call it only after the text already looks like
    /// a field start. Deletion-restart checks also allow single-line inputs; capitalization does not.
    static func confirmsFieldStart(_ snapshot: Snapshot, requireTextArea: Bool = true) -> Bool {
        guard snapshot.windowStart == 0, snapshot.caret == snapshot.text.utf16.count, snapshot.caret <= 64,
              (!requireTextArea || snapshot.isTextArea) else { return false }
        if let count = (attribute(snapshot.element, kAXNumberOfCharactersAttribute) as? NSNumber)?.intValue {
            guard count >= snapshot.caret, count <= snapshot.caret + 1 else { return false }
            if count == snapshot.caret + 1 {
                guard let trailing = substring(snapshot.element, range: CFRange(location: snapshot.caret, length: 1)),
                      trailing == "\n" || trailing == "\r" else { return false }
            }
            return true
        }
        // No count: the value itself must be the snapshot text (plus at most one line break).
        guard let value = attribute(snapshot.element, kAXValueAttribute) as? String else { return false }
        let length = (value as NSString).length
        guard length >= snapshot.caret, length <= snapshot.caret + 1, value.hasPrefix(snapshot.text) else { return false }
        return length == snapshot.caret || value.hasSuffix("\n") || value.hasSuffix("\r")
    }

    struct Region {
        let element: AXUIElement
        let pid: pid_t
        let text: String
        let windowStart: Int
        let caret: Int
        /// The field's total length when the editor reports it.
        let length: Int?
    }

    /// A bounded read around the caret for scanning existing text: the editor's visible
    /// character range when it reports one (at most 2,048 units), otherwise up to 768 units
    /// before and 256 after the caret. Same role, secure-field and caret requirements as
    /// `snapshot`; reads happen in bounded chunks and never fetch a whole document.
    static func focusedTextRegion(pid: pid_t) -> Region? {
        guard let element = focusedElement(pid: pid) else { return nil }
        guard let role = attribute(element, kAXRoleAttribute) as? String,
              [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role),
              (attribute(element, kAXSubroleAttribute) as? String) != kAXSecureTextFieldSubrole else { return nil }
        guard let selected = range(element), selected.length == 0, selected.location >= 0 else { return nil }
        let caret = selected.location
        let count = (attribute(element, kAXNumberOfCharactersAttribute) as? NSNumber)?.intValue
        var start = max(0, caret - 768)
        var end = caret + 256
        if let value = attribute(element, kAXVisibleCharacterRangeAttribute), CFGetTypeID(value) == AXValueGetTypeID() {
            var visible = CFRange()
            if AXValueGetValue(value as! AXValue, .cfRange, &visible), visible.location >= 0, (1...2048).contains(visible.length),
               visible.location <= caret, caret <= visible.location + visible.length {
                start = visible.location
                end = visible.location + visible.length
            }
        }
        if let count { end = min(end, count) }
        guard end > start, end - start <= 2048 else { return nil }
        var text = ""
        var cursor = start
        while cursor < end {
            let length = min(512, end - cursor)
            guard let chunk = substring(element, range: CFRange(location: cursor, length: length)) else {
                // A count-less editor may reject the part after the caret; keep what was read.
                if cursor >= caret, !text.isEmpty { break }
                return nil
            }
            text += chunk
            cursor += length
        }
        guard !text.isEmpty else { return nil }
        return Region(element: element, pid: pid, text: text, windowStart: start, caret: caret, length: count)
    }

    // The SDK specifies that this counts hardware key-down events, but not autorepeat.
    private static var physicalKeyCount: UInt32 {
        CGEventSource.counterForEventType(.hidSystemState, eventType: .keyDown)
    }

    private static func hasFocus(_ snapshot: Snapshot) -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == snapshot.pid,
              let current = focusedElement(pid: snapshot.pid), CFEqual(current, snapshot.element) else { return false }
        return true
    }

    static func stillMatches(_ snapshot: Snapshot) -> Bool {
        guard physicalKeyCount == snapshot.physicalKeyCount, hasFocus(snapshot),
              let selected = range(snapshot.element), selected.length == 0, selected.location == snapshot.caret,
              let text = substring(snapshot.element, range: CFRange(location: snapshot.windowStart, length: snapshot.caret - snapshot.windowStart)) else { return false }
        return text == snapshot.text && physicalKeyCount == snapshot.physicalKeyCount
    }

    /// Verification tolerates continued typing after the replaced suffix. It never retries a write.
    /// Returns the host's actual text, which may carry its own smart punctuation.
    static func verifies(snapshot: Snapshot, expectedText: String, expectedCaret: Int) -> String? {
        guard hasFocus(snapshot),
              let selected = range(snapshot.element), selected.length == 0,
              selected.location >= snapshot.windowStart + expectedCaret else { return nil }
        return confirmedText(observed: substring(snapshot.element, range: CFRange(location: snapshot.windowStart, length: expectedCaret)),
                             expected: expectedText)
    }

    /// Rich hosts (Notes, TextEdit, Mail, Messages, Pages) substitute curly quotes and
    /// nonbreaking spaces for what we insert. That is still the confirmed correction.
    static func confirmedText(observed: String?, expected: String) -> String? {
        guard let observed, TypingTypography.equivalent(observed: observed, typed: expected) else { return nil }
        return observed
    }
}
