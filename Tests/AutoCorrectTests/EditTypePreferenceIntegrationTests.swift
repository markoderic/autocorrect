import XCTest
import AutoCorrectCore
@testable import AutoCorrect

/// Actual NSSpellChecker integration for the edit-type preference. Native guess order
/// varies by macOS version; failures print the native signal for diagnosis.
final class EditTypePreferenceIntegrationTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private var engine: CorrectionEngine!
    override func setUp() {
        suite = "EditTypePreference.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        let preferences = Preferences(defaults: defaults)
        preferences.language = "en_US"
        engine = CorrectionEngine(preferences: preferences)
    }
    override func tearDown() {
        engine = nil
        defaults.removePersistentDomain(forName: suite)
    }

    private func check(_ source: String, _ expected: String?, file: StaticString = #filePath, line: UInt = #line) {
        var native = "no native assessment"
        engine.nativeAssessmentObserver = { _, miss, correction, guesses in
            native = "miss=\(miss) correction=\(correction ?? "nil") guesses=\(guesses)"
        }
        let result = engine.suggestion(in: "we said \(source) ")
        XCTAssertEqual(result, expected, "\(source): \(native)", file: file, line: line)
    }

    func testLetterPreservingRepairsReplaceNativeConsonantSubstitutionsAndDeletions() {
        for (source, expected) in ["higer": "higher", "chuch": "church", "sevice": "service", "caost": "coast",
                                   "returnd": "returned", "considerd": "considered", "diety": "deity",
                                   "twon": "town", "stong": "strong", "seach": "search", "peom": "poem"] {
            check(source, expected)
        }
    }

    func testNativeChoiceIsKeptForTranspositionsInsertionsVowelsAndDoubledLetters() {
        for (source, expected) in ["teh": "the", "adress": "address", "carefull": "careful", "andd": "and",
                                   "faught": "fought", "kiding": "kidding", "speoll": "spell"] {
            check(source, expected)
        }
    }

    func testCompetingLetterPreservingGuessesAbstain() {
        // agree (insertion) and ager (transposition) both keep the letters of agre.
        let result = engine.suggestion(in: "we said agre ")
        XCTAssertTrue(result == nil || result == "agree", result ?? "nil")
        // else, eels and lees are all transpositions of eles: abstain rather than guess.
        check("eles", nil)
    }
}
