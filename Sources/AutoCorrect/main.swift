import AppKit
import ServiceManagement

let application = NSApplication.shared
if CommandLine.arguments.contains("--diagnostics") {
    print("AutoCorrect \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development")")
    print("Accessibility: \(AXIsProcessTrusted())")
    print("Input Monitoring: \(CGPreflightListenEventAccess())")
    print("Keyboard layout supported: \(KeyboardMonitor.safeInputSource)")
    print("Login service status: \(SMAppService.mainApp.status.rawValue) (0=not registered, 1=enabled, 2=needs approval, 3=not found)")
} else if CommandLine.arguments.contains("--check-spelling") {
    let preferences = Preferences()
    let engine = CorrectionEngine(preferences: preferences)
    for word in ["teh", "helllo", "recieve", "speling", "world", "Marko", "GitHub"] {
        print("\(word) → \(engine.suggestion(word) ?? "(unchanged)")")
    }
} else {
    let delegate = AppDelegate()
    application.delegate = delegate
    application.run()
}
