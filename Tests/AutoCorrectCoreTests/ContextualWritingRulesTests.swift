import XCTest
@testable import AutoCorrectCore

final class ContextualWritingRulesTests: XCTestCase {
    func testAmbiguousTypoUsesCompletedDeadlineOrPurchaseContext() {
        for text in ["lets do that byu this date ", "Let's finish it byu the deadline ",
                     "Let’s send them byu that time ", "please review this byu this evening "] {
            XCTAssertEqual(ContextualWritingRules.candidate(in: text)?.replacement, "by", text)
        }
        for text in ["I want to byu a book ", "we need to byu some food ", "going to byu this phone "] {
            XCTAssertEqual(ContextualWritingRules.candidate(in: text)?.replacement, "buy", text)
        }
        for text in ["do that byu ", "do that byu this ", "do that byu this dat", "byu this date ",
                     "do that buy this date ", "we buy this book ", "I want to byu this date ",
                     "I want to byu a ", "study at BYU this year ", "do that byu this book ",
                     "do that byu.this date ", "`do that byu this date ", "path/do that byu this date ",
                     "she lets go ", "the app lets users type "] {
            XCTAssertNil(ContextualWritingRules.candidate(in: text), text)
        }
    }

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
                     "its going ", "its ", "lets ", "its a long lovely day ",
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

    /// Owner-reported misses (October 5, 2026): the invitation sat after a short run of
    /// discourse words ("Ok then", "No") rather than after a single listed opener. The rule
    /// looks back at most three completed words, so in live typing "No lets do it in claude"
    /// is caught at the "do " boundary; the fixtures reflect that boundary.
    func testInvitationAfterShortDiscourseRuns() throws {
        for text in ["Ok then lets go ", "No lets do it ", "No lets do ", "Yes please lets start ",
                     "Alright then lets try ", "ok, so lets begin ", "Oh no lets not go ", "Sure, lets see ", "No, lets all go "] {
            let candidate = try XCTUnwrap(ContextualWritingRules.candidate(in: text), text)
            XCTAssertEqual(candidate.original, "lets", text)
            XCTAssertEqual(candidate.replacement, "let's", text)
            XCTAssertTrue(candidate.automatic, text)
        }
    }

    func testVerbUsesOfLetsStayWhenAnythingButDiscourseWordsPrecede() {
        for text in ["The app lets users export ", "She then lets go of the rope ", "He lets me choose ", "No one lets him in ",
                     "Then she lets go ", "Well he lets us ", "ok the app lets users go ", "No lets ", "No lets d",
                     "no lets users go ", "Mom lets us go "] {
            XCTAssertNil(ContextualWritingRules.candidate(in: text), text)
        }
    }
}
