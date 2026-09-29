import XCTest
@testable import AutoCorrectCore

final class NameLexiconTests: XCTestCase {
    func testAmbiguousNativeWordsBlockFuzzyNameReplacement() {
        XCTAssertNil(NameLexicon.typoReplacement(for: "figms", systemCorrection: "firms", guesses: ["firms", "Figma"]))
        XCTAssertNil(NameLexicon.typoReplacement(for: "POWERPIONT", systemCorrection: "PowerPoint", guesses: ["PowerPoint"]))
        XCTAssertNil(NameLexicon.typoReplacement(for: "powerPiont", systemCorrection: "PowerPoint", guesses: ["PowerPoint"]))
        XCTAssertNil(NameLexicon.typoReplacement(for: "powerpiont.pptx", systemCorrection: "PowerPoint", guesses: ["PowerPoint"]))
        XCTAssertNil(NameLexicon.typoReplacement(for: "a", systemCorrection: "Apple", guesses: ["Apple"]))
    }

    func testNativeAcceptanceProtectsOrdinaryCapitalizedNames() {
        for word in ["united", "general", "american", "first", "healthcare", "apple", "excel", "word", "slack"] {
            XCTAssertNil(NameLexicon.canonicalReplacement(for: word, nativeMisspelled: false), word)
        }
        XCTAssertEqual(NameLexicon.canonicalReplacement(for: "figma", nativeMisspelled: true), "Figma")
        XCTAssertTrue(NameLexicon.recognizes("Figma"))
        XCTAssertTrue(NameLexicon.isCanonicalName("PowerPoint"))
    }

    func testDamagedContractionsAreLanguageAndAmbiguityGated() {
        XCTAssertEqual(EnglishWritingRules.typoReplacement(for: "doenst", language: "en_US", systemCorrection: "doesn't", guesses: ["doesn't"]), "doesn't")
        XCTAssertNil(EnglishWritingRules.typoReplacement(for: "doenst", language: "fr_FR", systemCorrection: "doesn't", guesses: ["doesn't"]))
        XCTAssertNil(EnglishWritingRules.typoReplacement(for: "DOENST", language: "en_US", systemCorrection: "doesn't", guesses: ["doesn't"]))
        XCTAssertNil(EnglishWritingRules.typoReplacement(for: "havnt", language: "en_US", systemCorrection: "haven't", guesses: ["haven't", "hasn't", "hadn't"]))
    }

    func testThreeEditFallbackRequiresLongWordsAndNativeAgreement() {
        let word = "misnderstndng"
        let correction = "misunderstanding"
        XCTAssertEqual(CorrectionPolicy.editDistance(Array(word), Array(correction)), 3)
        XCTAssertEqual(CorrectionPolicy.preferredAutomaticReplacement(for: word, systemCorrection: correction, guesses: [correction]), correction)
        XCTAssertNil(CorrectionPolicy.preferredAutomaticReplacement(for: word, systemCorrection: nil, guesses: [correction]))
        XCTAssertNil(CorrectionPolicy.preferredAutomaticReplacement(for: word, systemCorrection: correction, guesses: ["unrelated", correction]))
        XCTAssertNil(CorrectionPolicy.preferredAutomaticReplacement(for: "abcdefgh", systemCorrection: "abxdyfzh", guesses: ["abxdyfzh"]))
    }

    func testPeriodWaitsForFilenameOrSentenceContinuation() throws {
        for word in ["doenst", "powerpoint", "iphoen"] {
            var queue = CompletedWordBacklog()
            for char in word + "." { queue.append(String(char)) }
            XCTAssertTrue(queue.boundaries.isEmpty)
            for char in "txt " { queue.append(String(char)) }
            let text = word + ".txt "
            let prefix = try XCTUnwrap(queue.boundaries.first?.completedPrefix(in: text))
            XCTAssertNil(CorrectionPolicy.candidate(in: prefix, caret: prefix.utf16.count))
        }
        var queue = CompletedWordBacklog()
        for char in "doenst. next" { queue.append(String(char)) }
        XCTAssertEqual(queue.boundaries.first?.completedPrefix(in: "doenst. next"), "doenst. ")
        queue.reset()
        queue.append(" ")
        XCTAssertTrue(queue.boundaries.isEmpty)
    }
}
