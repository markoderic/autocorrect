import AppKit
import Carbon
import AutoCorrectCore

/// Constructs events without posting them or changing any application's state.
enum KeyboardEventSequence {
    static func make(plan: KeyboardReplacementPlan, marker: Int64) -> [CGEvent]? {
        guard let source = CGEventSource(stateID: .privateState) else { return nil }
        source.localEventsSuppressionInterval = 0
        var events: [CGEvent] = []
        func append(key: CGKeyCode, text: String? = nil) -> Bool {
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else { return false }
            for event in [down, up] {
                event.flags = []
                event.setIntegerValueField(.eventSourceUserData, value: marker)
                if let text = text {
                    let units = Array(text.utf16)
                    event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                }
                events.append(event)
            }
            return true
        }
        for _ in 0..<plan.deleteCount {
            guard append(key: CGKeyCode(kVK_Delete)) else { return nil }
        }
        for character in plan.insertion {
            guard append(key: 0, text: String(character)) else { return nil }
        }
        return events
    }
}
