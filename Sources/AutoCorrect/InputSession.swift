import AppKit
import Carbon

/// Main-thread recovery only. A health check reads access flags and tap state, never text.
final class InputSession {
    struct Access {
        var accessibility = true
        var inputMonitoring = true
        var secureInput = false
        static var current: Access {
            Access(accessibility: AXIsProcessTrusted(), inputMonitoring: CGPreflightListenEventAccess(),
                   secureInput: IsSecureEventInputEnabled())
        }
    }

    enum State: Equatable {
        case ready, paused, suspended, accessibilityNeeded, inputMonitoringNeeded, secureInput, recovering, unavailable
        var message: String? {
            switch self {
            case .ready: return nil
            case .paused: return "Paused"
            case .suspended: return "Waiting for your Mac session"
            case .accessibilityNeeded: return "Accessibility permission needed"
            case .inputMonitoringNeeded: return "Input Monitoring permission needed"
            case .secureInput: return "Paused while macOS Secure Input is active"
            case .recovering: return "Reconnecting keyboard listener…"
            case .unavailable: return "Keyboard listener unavailable — retrying automatically"
            }
        }
    }

    private let monitor: KeyboardMonitoring
    private let enabled: () -> Bool
    private let access: () -> Access
    private let reset: () -> Void
    private let changed: () -> Void
    private var sleeping = false
    private var inactive = false
    private(set) var state = State.ready

    init(monitor: KeyboardMonitoring, enabled: @escaping () -> Bool, access: @escaping () -> Access,
         reset: @escaping () -> Void, changed: @escaping () -> Void) {
        self.monitor = monitor; self.enabled = enabled; self.access = access
        self.reset = reset; self.changed = changed
    }

    func check(forceRestart: Bool = false) {
        let blocked: State?
        if !enabled() { blocked = .paused }
        else if sleeping || inactive { blocked = .suspended }
        else {
            let permission = access()
            if !permission.accessibility { blocked = .accessibilityNeeded }
            else if !permission.inputMonitoring { blocked = .inputMonitoringNeeded }
            else if permission.secureInput { blocked = .secureInput }
            else { blocked = nil }
        }
        if let blocked {
            if state != blocked || monitor.isRunning { reset(); monitor.stop() }
            setState(blocked)
            return
        }
        guard forceRestart || state != .ready || !monitor.isRunning else { return }
        // Lost keys invalidate the old word/caret evidence, even if the tap re-enabled itself.
        // Reset before stop so delayed cancellation/verification callbacks are obsolete.
        reset()
        monitor.stop()
        let started = monitor.start()
        setState(started && monitor.isRunning ? .ready : .unavailable)
    }

    /// Called synchronously on interruption, before any new keys can reach the engine.
    /// Recreating the tap itself is deferred until outside its callback.
    func interrupted() {
        reset()
        setState(.recovering)
    }

    func setSleeping(_ value: Bool) { sleeping = value; check(forceRestart: !value) }
    func setInactive(_ value: Bool) { inactive = value; check(forceRestart: !value) }

    private func setState(_ next: State) {
        guard state != next else { return }
        state = next
        changed()
    }
}
