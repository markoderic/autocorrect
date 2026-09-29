import Foundation

/// Opt-in development diagnostics: phase names only, never keys, field values, or app names.
/// Nothing is persisted, and normal background operation does not print anything.
enum RuntimeDiagnostics {
    private static let enabled = CommandLine.arguments.contains("--trace")
    static func record(_ phase: String) {
        guard enabled else { return }
        print("AutoCorrect: \(phase)")
        fflush(stdout)
    }
}
