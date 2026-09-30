import AppKit
import ApplicationServices

/// Supported Accessibility change notifications for the frontmost app and its focused
/// field, so marks are refreshed on edits, focus changes and window moves instead of
/// polling. One observer exists at a time; it is recreated when the frontmost app changes.
final class FieldObserver {
    enum Event {
        case focusChanged, valueChanged, selectionChanged, windowMoved, windowResized, deactivated, destroyed
    }
    let pid: pid_t
    var onEvent: ((Event) -> Void)?
    private var observer: AXObserver?

    init?(pid: pid_t, element: AXUIElement?) {
        self.pid = pid
        var created: AXObserver?
        let status = AXObserverCreate(pid, { _, _, notification, refcon in
            guard let refcon else { return }
            let field = Unmanaged<FieldObserver>.fromOpaque(refcon).takeUnretainedValue()
            field.handle(notification as String)
        }, &created)
        guard status == .success, let created else { return nil }
        observer = created
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let application = AXUIElementCreateApplication(pid)
        for name in [kAXFocusedUIElementChangedNotification, kAXWindowMovedNotification, kAXWindowResizedNotification,
                     kAXApplicationDeactivatedNotification, kAXApplicationHiddenNotification] {
            AXObserverAddNotification(created, application, name as CFString, refcon)
        }
        if let element {
            for name in [kAXValueChangedNotification, kAXSelectedTextChangedNotification, kAXUIElementDestroyedNotification] {
                AXObserverAddNotification(created, element, name as CFString, refcon)
            }
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .commonModes)
    }

    private func handle(_ notification: String) {
        let event: Event
        switch notification {
        case kAXFocusedUIElementChangedNotification: event = .focusChanged
        case kAXValueChangedNotification: event = .valueChanged
        case kAXSelectedTextChangedNotification: event = .selectionChanged
        case kAXWindowMovedNotification: event = .windowMoved
        case kAXWindowResizedNotification: event = .windowResized
        case kAXApplicationDeactivatedNotification, kAXApplicationHiddenNotification: event = .deactivated
        case kAXUIElementDestroyedNotification: event = .destroyed
        default: return
        }
        onEvent?(event)
    }

    deinit {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
    }
}
