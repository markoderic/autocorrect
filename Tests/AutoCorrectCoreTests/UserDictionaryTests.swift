import Foundation
import XCTest
@testable import AutoCorrectCore

final class UserDictionaryTests: XCTestCase {
    func testEmptySettings() throws {
        let dictionary = try UserDictionary.parse(ignoredText: "\n \n", correctionsText: "")
        XCTAssertTrue(dictionary.ignoredWords.isEmpty)
        XCTAssertTrue(dictionary.corrections.isEmpty)
    }

    func testParsesArrowsAndPreservesCustomCase() throws {
        let dictionary = try UserDictionary.parse(
            ignoredText: " Marko \nNotch\n",
            correctionsText: "chatgtp -> ChatGPT\nnotcj → Notch\n ii -> I \n")
        XCTAssertEqual(dictionary.ignoredWords, ["marko", "notch"])
        XCTAssertEqual(dictionary.corrections, ["chatgtp": "ChatGPT", "notcj": "Notch", "ii": "I"])
    }

    func testCanonicalUnicodeKeysAndIgnoredDeduplication() throws {
        let dictionary = try UserDictionary.parse(
            ignoredText: "Café\ncafe\u{301}\nCAFÉ",
            correctionsText: "RENE\u{301}E -> Renée")
        XCTAssertEqual(dictionary.ignoredWords, ["café"])
        XCTAssertEqual(dictionary.corrections["renée"], "Renée")
        XCTAssertEqual(UserDictionary.normalizedKey("CAFE\u{301}"), "café")
    }

    func testReplacementRetainsOriginalUnicodeAndCasing() throws {
        let replacement = "ReNe\u{301}e"
        let dictionary = try UserDictionary.parse(ignoredText: "", correctionsText: "renee -> \(replacement)")
        XCTAssertEqual(Array(dictionary.corrections["renee"]!.unicodeScalars), Array(replacement.unicodeScalars))
    }

    func testCaseAndCanonicalDuplicateCorrectionsRejected() {
        for text in ["teh -> the\nTEH -> The", "Café -> Cafe\ncafe\u{301} -> Coffee", "teh -> the\nteh -> the"] {
            XCTAssertThrowsError(try UserDictionary.parse(ignoredText: "", correctionsText: text)) { error in
                let validation = error as? UserDictionary.ValidationError
                XCTAssertEqual(validation?.section, .corrections)
                XCTAssertEqual(validation?.line, 2)
                XCTAssertTrue(error.localizedDescription.contains("line 1"))
            }
        }
    }

    func testInvalidPairSyntaxAndWords() {
        for line in ["teh the", "-> word", "word ->", "t -> the", "abc123 -> word", "two words -> word", "'word -> word"] {
            XCTAssertThrowsError(try UserDictionary.parse(ignoredText: "", correctionsText: "\n" + line)) { error in
                XCTAssertEqual((error as? UserDictionary.ValidationError)?.line, 2, line)
                XCTAssertTrue(error.localizedDescription.contains("Custom corrections"), line)
            }
        }
    }

    func testInvalidIgnoredWords() {
        for word in ["a", "two words", "hello@example.com", "@Marko", "abc123", "first-last", "'name", "name'", String(repeating: "a", count: 33)] {
            XCTAssertThrowsError(try UserDictionary.parse(ignoredText: "Marko\n\n" + word, correctionsText: "")) { error in
                XCTAssertEqual((error as? UserDictionary.ValidationError)?.section, .ignoredWords)
                XCTAssertEqual((error as? UserDictionary.ValidationError)?.line, 3)
            }
        }
    }

    func testWordLengthsAndInteriorApostrophes() throws {
        let source = String(repeating: "a", count: 32)
        let replacement = String(repeating: "B", count: 120)
        let dictionary = try UserDictionary.parse(ignoredText: "O’Connor\nO'Neill", correctionsText: "\(source) -> \(replacement)\ndont -> don't")
        XCTAssertEqual(dictionary.corrections[source], replacement)
        XCTAssertEqual(dictionary.corrections["dont"], "don't")
        XCTAssertEqual(dictionary.ignoredWords, ["o’connor", "o'neill"])
        XCTAssertThrowsError(try UserDictionary.parse(ignoredText: "", correctionsText: "word -> \(replacement)B"))
        XCTAssertThrowsError(try UserDictionary.parse(ignoredText: "", correctionsText: "\(source)a -> word"))
    }

    func testIgnoredWordMayAlsoHaveCorrectionForEnginePrecedence() throws {
        let dictionary = try UserDictionary.parse(ignoredText: "TEH", correctionsText: "teh -> the")
        XCTAssertTrue(dictionary.ignoredWords.contains("teh"))
        XCTAssertEqual(dictionary.corrections["teh"], "the")
    }

    func testCRLFAndBlankLinesPreserveErrorLineNumbers() {
        XCTAssertThrowsError(try UserDictionary.parse(ignoredText: "", correctionsText: "teh -> the\r\n\r\ninvalid")) { error in
            XCTAssertEqual((error as? UserDictionary.ValidationError)?.line, 3)
        }
    }

    func testCustomPhrasesPreservePunctuationCaseAndEmbeddedArrows() throws {
        let dictionary = try UserDictionary.parse(ignoredText: "", correctionsText: "idk -> I don't know\nomw → On my way!\narrow -> a -> b → c\nemail -> marko@example.com\ni -> I agree (100%).")
        XCTAssertEqual(dictionary.corrections["idk"], "I don't know")
        XCTAssertEqual(dictionary.corrections["omw"], "On my way!")
        XCTAssertEqual(dictionary.corrections["arrow"], "a -> b → c")
        XCTAssertEqual(dictionary.corrections["email"], "marko@example.com")
        XCTAssertEqual(dictionary.corrections["i"], "I agree (100%).")
    }

    func testPhraseValidationRejectsControlsAndBoundaries() {
        for invalid in ["", "   ", "hello\tthere", "hello\nthere", "hello\rthere", "hello\u{2028}there",
                        "hello\0there", "hello\u{1b}there", "hello\u{202E}there", String(repeating: "x", count: 121)] {
            XCTAssertFalse(UserDictionary.isValidReplacement(invalid), invalid.debugDescription)
        }
        for valid in ["I don't know", "On my way!", "@Marko", "hello 😀", "Ça va ?", String(repeating: "x", count: 120)] {
            XCTAssertTrue(UserDictionary.isValidReplacement(valid), valid)
        }
        for invalid in ["word -> hello\t", "word -> \thello", "word -> hello\0there"] {
            XCTAssertThrowsError(try UserDictionary.parse(ignoredText: "", correctionsText: invalid))
        }
    }
}
