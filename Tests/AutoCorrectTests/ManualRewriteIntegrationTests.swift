import XCTest
@testable import AutoCorrect

final class ManualRewriteIntegrationTests: XCTestCase {
    func testNativeCompoundGuardPreservesHomebrewWithoutGlobalIgnoreEntry() throws {
        let suite = "AutoCorrectTests.ManualRewrite.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)
        preferences.language = "en_US"
        let engine = CorrectionEngine(preferences: preferences)
        XCTAssertNil(engine.suggestion("homebrew"))
        XCTAssertNil(engine.suggestion(in: "Install homebrew "))
        XCTAssertFalse(preferences.ignoredWords.contains("homebrew"))
        XCTAssertEqual(engine.suggestion("teh"), "the")
        preferences.customCorrections = ["homebrew": "Homebrew"]
        XCTAssertEqual(engine.suggestion("homebrew"), "Homebrew")
    }
}
