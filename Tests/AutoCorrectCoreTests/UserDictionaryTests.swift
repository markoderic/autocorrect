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
        for line in ["teh the", "teh -> the -> then", "teh → the -> then", "-> word", "word ->", "t -> the", "abc123 -> word", "two words -> word", "word -> two words", "word -> hello!", "word -> @name", "word -> ''", "word -> a'b'c", "'word -> word", "word -> word'"] {
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
        let replacement = String(repeating: "B", count: 64)
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
}
