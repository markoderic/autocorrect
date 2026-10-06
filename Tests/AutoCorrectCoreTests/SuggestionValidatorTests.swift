import XCTest
@testable import AutoCorrectCore

final class SuggestionValidatorTests: XCTestCase {
    private func edit(_ original: String, _ replacement: String, _ category: String = "grammar", _ why: String = "test") -> ProposedEdit {
        ProposedEdit(original: original, replacement: replacement, category: category, explanation: why)
    }

    func testAcceptsAMinimalUnambiguousGrammarFix() throws {
        let out = SuggestionValidator.validate(sentence: "She don't like the new design.", edits: [edit("don't", "doesn't", "grammar", "Subject-verb agreement")])
        let s = try XCTUnwrap(out.first)
        XCTAssertEqual(s.category, .grammar)
        XCTAssertEqual(s.original, "don't"); XCTAssertEqual(s.replacement, "doesn't")
        XCTAssertEqual(("She don't like the new design." as NSString).substring(with: s.range), "don't")
        XCTAssertEqual(s.explanation, "Subject-verb agreement")
        XCTAssertEqual(s.sentence, "She don't like the new design.")
    }

    func testRejectsAmbiguousOriginals() {
        XCTAssertTrue(SuggestionValidator.validate(sentence: "I think it is what it is.", edits: [edit("it is", "it's")]).isEmpty, "occurs twice")
        XCTAssertTrue(SuggestionValidator.validate(sentence: "The report is ready.", edits: [edit("port", "ports")]).isEmpty, "inside a word")
        XCTAssertTrue(SuggestionValidator.validate(sentence: "The report is ready.", edits: [edit("missing", "present")]).isEmpty, "absent")
        XCTAssertTrue(SuggestionValidator.validate(sentence: "The report is ready.", edits: [edit("ready", "ready")]).isEmpty, "identical")
        XCTAssertTrue(SuggestionValidator.validate(sentence: "The report is ready.", edits: [edit("", "x")]).isEmpty, "empty")
    }

    func testRejectsChangesToNumbersNamesNegationAndProtectedTokens() {
        XCTAssertTrue(SuggestionValidator.validate(sentence: "Pay 10 by Friday.", edits: [edit("Pay 10", "Pay 12")]).isEmpty, "number changed")
        XCTAssertTrue(SuggestionValidator.validate(sentence: "Pay by Friday.", edits: [edit("Pay", "Pay 500")]).isEmpty, "number added")
        XCTAssertTrue(SuggestionValidator.validate(sentence: "Send it to Marko tomorrow.", edits: [edit("Marko", "Marco")]).isEmpty, "name changed")
        XCTAssertTrue(SuggestionValidator.validate(sentence: "I don't like it.", edits: [edit("don't like", "like")]).isEmpty, "negation dropped")
        XCTAssertTrue(SuggestionValidator.validate(sentence: "I like it.", edits: [edit("like", "don't like")]).isEmpty, "negation added")
        XCTAssertTrue(SuggestionValidator.validate(sentence: "Run `npm instal` now.", edits: [edit("`npm instal`", "`npm install`")]).isEmpty, "code span")
        XCTAssertTrue(SuggestionValidator.validate(sentence: "See https://example.com/docs,check it.", edits: [edit("https://example.com/docs,check", "https://example.com/docs, check")]).isEmpty, "URL inside the span")
        XCTAssertTrue(SuggestionValidator.validate(sentence: "Open settings.json first.", edits: [edit("settings.json", "settings.jason")]).isEmpty, "filename")
    }

    func testAllowsReplacementsThatKeepNamesNumbersAndNegation() {
        XCTAssertEqual(SuggestionValidator.validate(sentence: "Send it to Tom and I by Friday.", edits: [edit("Tom and I", "Tom and me")]).count, 1)
        XCTAssertEqual(SuggestionValidator.validate(sentence: "The outage didn't effect the EU customers.", edits: [edit("effect", "affect")]).count, 1)
        XCTAssertEqual(SuggestionValidator.validate(sentence: "I bought apples bananas and oranges.", edits: [edit("apples bananas and oranges", "apples, bananas, and oranges", "punctuation", "List commas")]).count, 1)
        XCTAssertTrue(SuggestionValidator.validate(sentence: "Revenue was 4,200,000 dollars , up 12 %.", edits: [edit("dollars ,", "dollars,", "punctuation")]).isEmpty,
                      "a span ending in punctuation cannot be applied by the keyboard edit plan, so it is not offered")
        XCTAssertEqual(SuggestionValidator.validate(sentence: "Thanks Maria I owe you one.", edits: [edit("Thanks Maria I", "Thanks, Maria, I", "punctuation")]).count, 1)
    }

    func testCategoryFiltersAndUnknownCategories() {
        let edits = [edit("don't", "doesn't", "grammar"), edit("like the new", "like, the new", "punctuation"), edit("new", "latest", "style")]
        let sentence = "She don't like the new design."
        XCTAssertEqual(SuggestionValidator.validate(sentence: sentence, edits: edits).map(\.category), [.grammar, .punctuation])
        XCTAssertEqual(SuggestionValidator.validate(sentence: sentence, edits: edits, options: .init(allowGrammar: false)).map(\.category), [.punctuation])
        XCTAssertEqual(SuggestionValidator.validate(sentence: sentence, edits: edits, options: .init(allowPunctuation: false)).map(\.category), [.grammar])
        XCTAssertTrue(SuggestionValidator.validate(sentence: sentence, edits: edits, options: .init(allowGrammar: false, allowPunctuation: false)).isEmpty)
    }

    func testOverlappingEditsKeepTheFirstAndOverlongReplacementsAreDropped() {
        let sentence = "He walk to work every day."
        let out = SuggestionValidator.validate(sentence: sentence, edits: [edit("walk", "walks"), edit("walk to work", "commutes")])
        XCTAssertEqual(out.map(\.replacement), ["walks"])
        XCTAssertTrue(SuggestionValidator.validate(sentence: sentence, edits: [edit("walk", String(repeating: "x", count: 40))]).isEmpty)
    }

    func testLastCompleteSentenceSelection() throws {
        let text = "First one here. The the report is ready for review. "
        let found = try XCTUnwrap(SuggestionValidator.lastCompleteSentence(in: text))
        XCTAssertEqual(found.sentence, "The the report is ready for review.")
        XCTAssertEqual((text as NSString).substring(with: found.range), found.sentence)
        XCTAssertNil(SuggestionValidator.lastCompleteSentence(in: "No terminator yet "), "a pause is not a sentence end")
        XCTAssertNil(SuggestionValidator.lastCompleteSentence(in: "Ok. "), "too short to analyze")
        XCTAssertEqual(SuggestionValidator.lastCompleteSentence(in: "Call me.\nPick up the dry cleaning on the way back.")?.sentence, "Pick up the dry cleaning on the way back.")
        XCTAssertEqual(SuggestionValidator.lastCompleteSentence(in: "Version 2.3 shipped today. Are you coming to the party?")?.sentence, "Are you coming to the party?")
        XCTAssertNil(SuggestionValidator.lastCompleteSentence(in: String(repeating: "word ", count: 120) + "end."), "over the length bound")
    }

    func testEmojiAtWindowEndDoesNotCrashSentenceEligibility() {
        let text = "This is a normal message 🙂"
        XCTAssertNil(SuggestionValidator.analysisUnit(in: text))
        XCTAssertEqual(SuggestionValidator.analysisUnit(in: text, allowUnterminated: true)?.sentence, text)
    }

    func testTerminatedOrWhitespacePrefixedTruncatedWindowsAreRejected() {
        for text in ["like the new design.", " like the new design.", " like the new design"] {
            XCTAssertNil(SuggestionValidator.analysisUnit(in: text, windowStart: 30, allowUnterminated: true))
        }
        XCTAssertEqual(SuggestionValidator.analysisUnit(in: "old tail. This sentence is complete.", windowStart: 30)?.sentence,
                       "This sentence is complete.")
    }
}
