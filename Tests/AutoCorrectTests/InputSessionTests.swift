import XCTest
import AppKit
import AutoCorrectCore
@testable import AutoCorrect

/// Fault injection at the native listener boundary; no global keyboard events or permissions.
final class InputSessionTests: XCTestCase {
    final class Monitor: KeyboardMonitoring {
        var onKey: ((String?, CGEventFlags, Int64) -> Void)?
        var onMouse: ((CGEventType, CGPoint) -> Void)?
        var onUndo: (() -> Bool)?
        var onShowPopup: (() -> Bool)?
        var onInterruption: (() -> Void)?
        var isRunning = false
        var canStart = true
        var falselyReportsSuccess = false
        var starts = 0
        var stops = 0
        func start() -> Bool { starts += 1; isRunning = canStart; return canStart || falselyReportsSuccess }
        func stop() { stops += 1; isRunning = false }
        func replace(_ plan: KeyboardReplacementPlan, validate: @escaping () -> Bool, completion: @escaping (Bool) -> Void) {
            XCTFail("Tests must not post native input")
            completion(false)
        }
    }

    private var monitor: Monitor!
    private var session: InputSession!
    private var enabled = true
    private var access = InputSession.Access()
    private var resets = 0
    private var changes = 0
    override func setUp() {
        monitor = Monitor()
        session = InputSession(monitor: monitor, enabled: { self.enabled }, access: { self.access },
                               reset: { self.resets += 1 }, changed: { self.changes += 1 })
    }
    override func tearDown() { session = nil; monitor = nil }

    func testDisabledListenerRecoversWithoutOpeningMenu() {
        session.check()
        monitor.isRunning = false
        session.check()
        XCTAssertTrue(monitor.isRunning)
        XCTAssertEqual(monitor.starts, 2)
        XCTAssertEqual(resets, 2)
        XCTAssertEqual(session.state, .ready)
    }

    func testHealthyChecksPreserveTypingAndAvoidRestarts() {
        session.check()
        for _ in 0..<1000 { session.check() }
        XCTAssertEqual(monitor.starts, 1)
        XCTAssertEqual(resets, 1)
        XCTAssertEqual(changes, 0)
    }

    func testFailureShowsUnavailableAndNextCheckRetries() {
        monitor.canStart = false
        monitor.falselyReportsSuccess = true
        session.check()
        XCTAssertEqual(session.state, .unavailable)
        XCTAssertNotNil(session.state.message)
        monitor.canStart = true
        session.check()
        XCTAssertEqual(session.state, .ready)
        XCTAssertTrue(monitor.isRunning)
    }

    func testPausedPreferenceNeverRestartsOnWakeOrHealthCheck() {
        session.check()
        enabled = false
        session.check()
        session.setSleeping(true)
        session.setSleeping(false)
        session.check()
        XCTAssertEqual(monitor.starts, 1)
        XCTAssertFalse(monitor.isRunning)
        XCTAssertEqual(session.state, .paused)
        enabled = true
        session.check()
        XCTAssertTrue(monitor.isRunning)
    }

    func testBothPermissionsStopInputAndRecoverWhenRestored() {
        for inputPermission in [false, true] {
            access = .init(); session.check()
            if inputPermission { access.inputMonitoring = false } else { access.accessibility = false }
            session.check()
            XCTAssertFalse(monitor.isRunning)
            XCTAssertEqual(session.state, inputPermission ? .inputMonitoringNeeded : .accessibilityNeeded)
            let starts = monitor.starts
            session.check()
            XCTAssertEqual(monitor.starts, starts)
            access = .init(); session.check()
            XCTAssertTrue(monitor.isRunning)
        }
    }

    func testSecureInputPausesAndRecoversWithoutBypassingIt() {
        session.check()
        access.secureInput = true
        session.check()
        XCTAssertEqual(session.state, .secureInput)
        XCTAssertFalse(monitor.isRunning)
        let resets = self.resets
        session.check()
        XCTAssertEqual(self.resets, resets)
        access.secureInput = false
        session.check()
        XCTAssertTrue(monitor.isRunning)
        XCTAssertEqual(self.resets, resets + 1)
    }

    func testWakeDoesNotResumeWhileSessionStillInactive() {
        session.check()
        session.setInactive(true)
        session.setSleeping(true)
        session.setSleeping(false)
        XCTAssertFalse(monitor.isRunning)
        XCTAssertEqual(session.state, .suspended)
        session.setInactive(false)
        XCTAssertTrue(monitor.isRunning)
        XCTAssertEqual(monitor.starts, 2)
    }

    func testSessionActivationDoesNotResumeWhileStillSleeping() {
        session.check()
        session.setSleeping(true)
        session.setInactive(true)
        session.setInactive(false)
        XCTAssertFalse(monitor.isRunning)
        session.setSleeping(false)
        XCTAssertTrue(monitor.isRunning)
    }

    func testWakeRecreatesApparentlyEnabledStaleListener() {
        session.check()
        session.setSleeping(false) // A wake notification can arrive without a recorded sleep.
        XCTAssertEqual(monitor.starts, 2)
        XCTAssertEqual(resets, 2)
    }

    func testInterruptionInvalidatesBeforeListenerRecovery() {
        session.check()
        session.interrupted()
        XCTAssertEqual(resets, 2)
        XCTAssertEqual(session.state, .recovering)
        XCTAssertEqual(monitor.starts, 1) // No recreation inside the native callback.
        session.check()
        XCTAssertEqual(monitor.starts, 2)
        XCTAssertEqual(session.state, .ready)
    }

    func testInterruptionCannotReenablePausedPreference() {
        session.check()
        session.interrupted()
        enabled = false
        session.check()
        XCTAssertFalse(monitor.isRunning)
        XCTAssertEqual(monitor.starts, 1)
        XCTAssertEqual(session.state, .paused)
    }

    func testEngineDropsInterruptedEditAndAcceptsFreshWords() {
        let name = "InputSessionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = Preferences(defaults: defaults)
        preferences.capitalizesAfterPeriod = false
        preferences.showsSpellingIndicators = false
        preferences.customCorrections = ["zztest": "tested"]
        let engine = CorrectionEngine(preferences: preferences, monitor: monitor, inputAccess: { self.access })
        engine.suppressesRendering = true
        engine.checkInputHealth()
        let element = AXUIElementCreateApplication(getpid())
        let snapshot = AccessibilityText.Snapshot(element: element, pid: getpid(), text: "zztest ", windowStart: 0,
                                                 caret: 7, physicalKeyCount: 0, isTextArea: true)
        var oldCompletion: ((String?) -> Void)?
        engine.editTransport = { _, _, completion in oldCompletion = completion }
        engine.debugAppendKeys("zztest ")
        engine.processBoundaries(using: snapshot)
        XCTAssertNotNil(oldCompletion)
        monitor.onInterruption?()
        XCTAssertEqual(engine.status, "Reconnecting keyboard listener…")
        oldCompletion?("tested ")
        XCTAssertEqual(engine.correctionCount, 0)
        XCTAssertNil(engine.undoProposal)
        engine.checkInputHealth()
        var freshEdits = 0
        engine.editTransport = { _, plan, completion in freshEdits += 1; completion(plan.expectedText) }
        engine.processBoundaries(using: snapshot)
        XCTAssertEqual(freshEdits, 0, "Do not replay pre-interruption words")
        engine.debugAppendKeys("zztest ")
        engine.processBoundaries(using: snapshot)
        XCTAssertEqual(freshEdits, 1, "An abandoned in-flight edit must not stall later words")
        XCTAssertEqual(engine.correctionCount, 1)
        XCTAssertNotNil(engine.undoProposal)
        engine.checkInputHealth()
        XCTAssertNotNil(engine.undoProposal, "A healthy check must preserve Undo")
    }

    func testUnavailableStatusSurvivesFocusChangesAndRefresh() {
        let name = "InputSessionStatus.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = Preferences(defaults: defaults)
        preferences.showsSpellingIndicators = false
        let engine = CorrectionEngine(preferences: preferences, monitor: monitor, inputAccess: { self.access })
        engine.suppressesRendering = true
        access.secureInput = true
        engine.checkInputHealth()
        engine.focusChanged()
        engine.refresh()
        XCTAssertEqual(engine.status, "Paused while macOS Secure Input is active")
        access.secureInput = false
        engine.checkInputHealth()
        XCTAssertEqual(engine.status, "Ready")
    }
}
