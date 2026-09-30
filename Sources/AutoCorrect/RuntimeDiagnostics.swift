import Foundation

/// Opt-in development diagnostics: phase names only, never keys, field values, or app names.
/// Nothing is persisted, and normal background operation does not print anything.
enum RuntimeDiagnostics {
    static let isEnabled = CommandLine.arguments.contains("--trace")
    private static let start = ProcessInfo.processInfo.systemUptime
    static func record(_ phase: String) {
        guard isEnabled else { return }
        print(String(format: "AutoCorrect %8.2fs: %@", max(0, ProcessInfo.processInfo.systemUptime - start), phase))
        fflush(stdout)
    }
}
