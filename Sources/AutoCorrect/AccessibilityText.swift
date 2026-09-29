import AppKit
import ApplicationServices

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
        // Rich contenteditable controls can expose AXValue without NumberOfCharacters.
        // A known oversize value is skipped before fetching it; unknown sizes are checked
        // immediately after the one fallback read. Never infer a caret from the value.
        let count = (attribute(element, kAXNumberOfCharactersAttribute) as? NSNumber)?.intValue
        if let count, !(0...16_384).contains(count) { return nil }
        guard let value = attribute(element, kAXValueAttribute) as? String else { return nil }
        return boundedSubstring(value, reportedCount: count, range: range)
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
        RuntimeDiagnostics.record("snapshot available")
        return Snapshot(element: element, pid: pid, text: text, windowStart: start, caret: selected.location, physicalKeyCount: keyCount)
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
    static func verifies(snapshot: Snapshot, expectedText: String, expectedCaret: Int) -> Bool {
        guard hasFocus(snapshot),
              let selected = range(snapshot.element), selected.length == 0,
              selected.location >= snapshot.windowStart + expectedCaret else { return false }
        return substring(snapshot.element, range: CFRange(location: snapshot.windowStart, length: expectedCaret)) == expectedText
    }
}
