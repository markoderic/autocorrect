import AppKit
import ServiceManagement

let application = NSApplication.shared
if CommandLine.arguments.contains("--diagnostics") {
    print("AutoCorrect \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development")")
    print("Accessibility: \(AXIsProcessTrusted())")
    print("Input Monitoring: \(CGPreflightListenEventAccess())")
    let monitor = KeyboardMonitor()
    print("Keyboard listener available: \(monitor.start())")
    monitor.stop()
    print("Keyboard layout supported: \(KeyboardMonitor.safeInputSource)")
    print("Login service status: \(SMAppService.mainApp.status.rawValue) (0=not registered, 1=enabled, 2=needs approval, 3=not found)")
} else if CommandLine.arguments.contains("--check-spelling") {
    let preferences = Preferences()
    let engine = CorrectionEngine(preferences: preferences)
    for word in ["i", "im", "i'm", "ive", "doesnt", "dont", "didnt", "cant", "wont", "youre", "ti", "teh", "ths", "mispell", "ill", "well", "were", "its", "world", "Marko", "GitHub", "idk", "omw", "iphone", "ui", "api", "capitazed", "inconvient", "acomodation", "probblity", "homebrew"] {
        print("\(word) → \(engine.suggestion(word) ?? "(unchanged)")")
    }
    for text in ["Done. hello ", "Done. a ", "Done. teh ", "Dr. smith "] {
        print("\(text)→ \(engine.suggestion(in: text) ?? "(unchanged)")")
    }
} else {
    let delegate = AppDelegate()
    application.delegate = delegate
    application.run()
}
