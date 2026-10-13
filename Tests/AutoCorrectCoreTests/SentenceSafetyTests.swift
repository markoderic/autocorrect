import XCTest
@testable import AutoCorrectCore

final class SentenceSafetyTests: XCTestCase {
    private func proposal(_ a: String, _ b: String, _ category: String = "grammar") -> ProposedEdit {
        ProposedEdit(original: a, replacement: b, category: category, explanation: "test")
    }
    private func applyRules(_ sentence: String) -> String {
        let edits = SuggestionValidator.validate(sentence: sentence, edits: SentenceRules.proposals(in: sentence))
        var output = sentence as NSString
        for edit in edits.reversed() { output = output.replacingCharacters(in: edit.range, with: edit.replacement) as NSString }
        return output as String
    }

    func testQuotationProtectionIncludesStraightCurlySingleAndUnfinishedQuotes() {
        for text in ["He wrote \"ur late lol\" yesterday.", "He wrote “ur late lol” yesterday.",
                     "He wrote 'ur late lol' yesterday.", "He wrote ‘ur late lol’ yesterday.",
                     "He wrote \"ur late lol", "🙂 He wrote \"ur late lol\" yesterday."] {
            XCTAssertTrue(SuggestionValidator.validate(sentence: text, edits: [proposal("ur", "you")]).isEmpty, text)
        }
        XCTAssertEqual(applyRules("She said \"could of\" but he could of waited."),
                       "She said \"could of\" but he could of waited.", "Repeated originals stay ambiguous")
        XCTAssertEqual(applyRules("She said \"all fine\" but he could of waited."),
                       "She said \"all fine\" but he could have waited.")
        XCTAssertEqual(applyRules("Don't change 'we was late' in the transcript."), "Don't change 'we was late' in the transcript.")
        for quote in ["'don't change we was late'", "‘don’t change we was late’", "'don't change we was late"] {
            let text = "He wrote " + quote
            XCTAssertEqual(applyRules(text), text)
        }
    }

    func testUnsupportedModelParaphrasesAndMalformedRepairsAreRejected() {
        for (sentence, original, replacement) in [
            ("The meeting was a mess.", "mess", "disaster"),
            ("Each of the students have a laptop.", "Each", "Every"),
            ("Your going to need a jacket.", "Your", "You"),
            ("This coffee is more better.", "better", "gooder"),
            ("We got there late the show had already started.", "late the show", "late"),
            ("The concert had already started.", "had already", "was already")
        ] {
            XCTAssertTrue(SuggestionValidator.validate(sentence: sentence, edits: [proposal(original, replacement)]).isEmpty)
        }
    }

    func testRulesGeneralizeAcrossSubjectsAndPreserveCorrectControls() {
        for (source, expected) in [
            ("Each of those machines have a label.", "Each of those machines has a label."),
            ("Every one of our printers require a cable.", "Every one of our printers requires a cable."),
            ("You should of checked the address.", "You should have checked the address."),
            ("The the parcel is here.", "The parcel is here."),
            ("This route is more worse than before.", "This route is worse than before."),
            ("She had went upstairs.", "She had gone upstairs."),
            ("There going to arrive soon.", "They're going to arrive soon."),
            ("Your going to arrive soon.", "You're going to arrive soon."),
            ("They was waiting outside.", "They were waiting outside."),
            ("He don't understand the question.", "He doesn't understand the question.")
        ] { XCTAssertEqual(applyRules(source), expected) }
        for text in ["If I were going, I would tell you.", "Your going away party is tomorrow.",
                     "She had had enough.", "That is very very nice!", "Each machine has a label.",
                     "They were waiting outside.", "Read `could of` as written."] {
            XCTAssertEqual(applyRules(text), text)
        }
    }

    func testPunctuationUsesExistingSafeTransportAndUndo() throws {
        let sentence = "The update , we reviewed it today."
        let edits = SuggestionValidator.validate(sentence: sentence, edits: [proposal("update ,", "update,", "punctuation")])
        let edit = try XCTUnwrap(edits.first)
        XCTAssertEqual(edit.original, "update , we")
        let text = sentence + " next"
        let plan = try XCTUnwrap(KeyboardReplacementPlan.make(text: text, wordRange: edit.range, replacement: edit.replacement))
        XCTAssertEqual(plan.expectedText, "The update, we reviewed it today. next")
        let undo = try XCTUnwrap(KeyboardReplacementPlan.make(text: plan.expectedText,
            wordRange: NSRange(location: edit.range.location, length: edit.replacement.utf16.count), replacement: edit.original))
        XCTAssertEqual(undo.expectedText, text)
        XCTAssertTrue(SuggestionValidator.validate(sentence: "Are you coming.", edits: [proposal("coming.", "coming?", "punctuation")]).isEmpty)
        XCTAssertEqual(applyRules("I can' t wait,please hurry."), "I can't wait, please hurry.")
    }
}
