import AppKit
import Carbon
import AutoCorrectCore

final class KeyboardMonitor {
    var onKey: ((String?, CGEventFlags, Int64) -> Void)?
    var onMouse: (() -> Void)?
    var onUndo: (() -> Bool)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private struct PendingEdit {
        let marker: Int64
        let events: [CGEvent]
        let validate: () -> Bool
        let completion: (Bool) -> Void
    }
    private var pendingEdit: PendingEdit?
    private var nextEdit: Int64 = 0
    private static let triggerBase: Int64 = 0x4155435400000000
    private static let injectedMarker: Int64 = 0x4155434900000000
    var isRunning: Bool { tap != nil && CGEvent.tapIsEnabled(tap: tap!) }

    func start() -> Bool {
        if isRunning { return true }
        stop()
        let types: [CGEventType] = [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .defaultTap, eventsOfInterest: mask, callback: { proxy, type, event, context in
            guard let context = context else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(context).takeUnretainedValue()
            let marker = event.getIntegerValueField(.eventSourceUserData)
            if marker == KeyboardMonitor.injectedMarker { return Unmanaged.passUnretained(event) }
            if marker & Int64(bitPattern: 0xffffffff00000000) == KeyboardMonitor.triggerBase {
                // The trigger is a text-free modifier event, consumed even if its request expired.
                if let edit = monitor.pendingEdit, edit.marker == marker {
                    monitor.pendingEdit = nil
                    RuntimeDiagnostics.record("edit trigger received")
                    let valid = monitor.isRunning && edit.validate()
                    RuntimeDiagnostics.record(valid ? "edit revalidated" : "edit canceled")
                    if valid {
                        // Apple guarantees these events are delivered before the event returned
                        // by this callback. Keep the complete edit ahead of the next typed key.
                        for generated in edit.events { generated.tapPostEvent(proxy) }
                        RuntimeDiagnostics.record("edit posted")
                    }
                    DispatchQueue.main.async { edit.completion(valid) }
                }
                return nil
            }
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                monitor.cancelEdit()
                if let tap = monitor.tap { CGEvent.tapEnable(tap: tap, enable: true) }
            } else if type == .keyDown {
                monitor.cancelEdit()
                if event.getIntegerValueField(.keyboardEventKeycode) == 6,
                   event.flags.intersection([.maskControl, .maskAlternate, .maskCommand, .maskShift]) == [.maskControl, .maskAlternate, .maskCommand],
                   monitor.onUndo?() == true { return nil }
                var buffer = [UniChar](repeating: 0, count: 8)
                var length = 0
                event.keyboardGetUnicodeString(maxStringLength: buffer.count, actualStringLength: &length, unicodeString: &buffer)
                let text = length > 0 ? String(utf16CodeUnits: buffer, count: min(length, buffer.count)) : nil
                monitor.onKey?(text, event.flags, event.getIntegerValueField(.keyboardEventKeycode))
            } else if type != .flagsChanged {
                monitor.cancelEdit()
                monitor.onMouse?()
            }
            return Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        cancelEdit()
        if let tap = tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    /// Prebuild the complete native edit, then revalidate immediately inside the event tap.
    /// No selection is ever created and no physical keyboard event is suppressed or replayed.
    func replace(_ plan: KeyboardReplacementPlan, validate: @escaping () -> Bool, completion: @escaping (Bool) -> Void) {
        guard isRunning, pendingEdit == nil,
              let events = KeyboardEventSequence.make(plan: plan, marker: KeyboardMonitor.injectedMarker),
              let eventSource = CGEventSource(stateID: .privateState) else { completion(false); return }
        eventSource.localEventsSuppressionInterval = 0
        guard let trigger = CGEvent(source: eventSource) else { completion(false); return }
        nextEdit = (nextEdit + 1) & 0xffffffff
        let marker = KeyboardMonitor.triggerBase | nextEdit
        trigger.type = .flagsChanged
        trigger.flags = []
        trigger.setIntegerValueField(.eventSourceUserData, value: marker)
        pendingEdit = PendingEdit(marker: marker, events: events, validate: validate, completion: completion)
        RuntimeDiagnostics.record("edit queued")
        trigger.post(tap: .cgSessionEventTap)
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250)) { [weak self] in
            guard self?.pendingEdit?.marker == marker else { return }
            self?.cancelEdit()
        }
    }

    private func cancelEdit() {
        guard let edit = pendingEdit else { return }
        pendingEdit = nil
        DispatchQueue.main.async { edit.completion(false) }
    }

    static var safeInputSource: Bool {
        guard !IsSecureEventInputEnabled(), let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceType) else { return false }
        let type = Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue()
        return type == kTISTypeKeyboardLayout
    }

    deinit { stop() }
}
