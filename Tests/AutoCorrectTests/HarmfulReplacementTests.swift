import XCTest
@testable import AutoCorrect

final class HarmfulReplacementTests: XCTestCase {
    private func withEngine(_ check: (CorrectionEngine, Preferences) -> Void) {
        let suite = "HarmfulReplacement.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)
        preferences.language = "en_US"
        check(CorrectionEngine(preferences: preferences), preferences)
    }

    func testConflictingRepairsDoNotSilentlyChangeMeaning() {
        withEngine { engine, _ in
            for (source, expected) in [("bedore", "before"), ("adquiring", "acquiring"), ("lastr", "last")] {
                let result = engine.suggestion(in: "we said \(source) ")
                XCTAssertTrue(result == nil || result == expected, "\(source): \(result ?? "review")")
            }
        }
    }

    func testUnknownNamesAndRegionalSpellingsArePreserved() {
        withEngine { engine, _ in
            for text in ["Dr. Ngozi ", "Ask Ngozi ", "Ask Nkiru ", "Send it to Oluwaseun ",
                         "we organise ", "we finalise ", "the colour ", "the behaviour ", "the centre "] {
                XCTAssertNil(engine.suggestion(in: text), text)
            }
        }
    }

    func testExplicitOverridesWinOverNameAndDialectProtection() {
        withEngine { engine, preferences in
            preferences.customCorrections = ["ngozi": "Ngozi Okafor", "organise": "organize"]
            XCTAssertEqual(engine.suggestion(in: "Ask Ngozi "), "Ngozi Okafor")
            XCTAssertEqual(engine.suggestion(in: "we organise "), "organize")
            preferences.ignoredWords = ["organise"]
            XCTAssertNil(engine.suggestion(in: "we organise "))
        }
    }
}
