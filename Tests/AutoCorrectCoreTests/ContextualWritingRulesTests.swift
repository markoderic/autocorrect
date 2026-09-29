import XCTest
@testable import AutoCorrectCore

final class ContextualWritingRulesTests: XCTestCase {
    func testContractionContextsAfterOneToThreeCompletedWords() throws {
        for text in ["its a ", "its an example ", "its a good day ", "its been ", "its not ready ", "its going to ", "its going to work "] {
            let candidate = try XCTUnwrap(ContextualWritingRules.candidate(in: text), text)
            XCTAssertEqual(candidate.original, "its")
            XCTAssertEqual(candidate.replacement, "it's")
            XCTAssertEqual((text as NSString).substring(with: candidate.range), candidate.original)
            XCTAssertFalse(candidate.explanation.isEmpty)
        }
    }

    func testPossessiveNeedsAdditionalEvidence() throws {
        for text in ["check it's color ", "changed it's name ", "with it’s battery ", "it's color is ", "It's size was small "] {
            let candidate = try XCTUnwrap(ContextualWritingRules.candidate(in: text), text)
            XCTAssertEqual(candidate.replacement.lowercased(), "its")
            XCTAssertEqual((text as NSString).substring(with: candidate.range), candidate.original)
        }
    }

    func testInvitationsAndCase() throws {
        for (text, expected) in [("lets build ", "let's"), ("Lets go ", "Let's"), ("Done. lets all start ", "let's"), ("(lets try again) ", "let's"), ("Its a test ", "It's")] {
            XCTAssertEqual(try XCTUnwrap(ContextualWritingRules.candidate(in: text), text).replacement, expected)
        }
    }

    func testCorrectAndInsufficientContextsRemainUntouched() {
        for text in ["its color ", "its going rate ", "it's raining ", "it's color ", "it's color not shape ",
                     "she lets us ", "she lets go ", "the app lets users work ", "lets user ", "lets users ",
                     "lets count ", "its going ", "its ", "lets ", "its a long lovely day ",
                     "ITS A ", "iTs a ", "LETS GO ", "it's good ", "let's go "] {
            XCTAssertNil(ContextualWritingRules.candidate(in: text), text)
        }
    }

    func testNoPartialStructuredOrCrossSentenceMatch() {
        for text in ["its a", "its a  ", "its a\n", "its a\t", "its. a ", "its\na ", "its\ta ",
                     "obj.its a ", "@its a ", "/its a ", "_its a ", "its a_file ", "its a123 ",
                     "its a@ ", "its an-example ", "its a🙂 ", "its aaaaaaaaaaaaaaaaaaaaaaaaaaaa\n"] {
            XCTAssertNil(ContextualWritingRules.candidate(in: text), text)
        }
        XCTAssertNil(ContextualWritingRules.candidate(in: String(repeating: "x", count: 256) + " its a "))
    }

    func testUTF16OffsetsAndReplacementPreserveSurroundingText() throws {
        let text = "🙂 café: check it’s color "
        let candidate = try XCTUnwrap(ContextualWritingRules.candidate(in: text))
        XCTAssertEqual(candidate.range, (text as NSString).range(of: "it’s"))
        XCTAssertEqual((text as NSString).replacingCharacters(in: candidate.range, with: candidate.replacement), "🙂 café: check its color ")
    }
}
