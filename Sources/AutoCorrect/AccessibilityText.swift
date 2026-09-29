import AppKit
import ApplicationServices

/// Read-only Accessibility snapshots. Text and selections are never changed through AX.
enum AccessibilityText {
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
        // Some controls expose AXValue but not AXStringForRange. Keep this fallback small.
        guard let count = attribute(element, kAXNumberOfCharactersAttribute) as? NSNumber,
              (0...16_384).contains(count.intValue),
              let value = attribute(element, kAXValueAttribute) as? String,
              range.location >= 0, range.length >= 0,
              range.location <= (value as NSString).length - range.length else { return nil }
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
        guard let element = focusedElement(pid: pid),
              let role = attribute(element, kAXRoleAttribute) as? String,
              [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role),
              (attribute(element, kAXSubroleAttribute) as? String) != kAXSecureTextFieldSubrole,
              let selected = range(element), selected.length == 0, selected.location > 0 else { return nil }
        // Extra preceding context prevents treating the tail of a long URL/token as a word.
        let start = max(0, selected.location - 256)
        guard let text = substring(element, range: CFRange(location: start, length: selected.location - start)),
              physicalKeyCount == keyCount else { return nil }
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
