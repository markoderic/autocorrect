import XCTest
@testable import AutoCorrectCore

final class CompletedWordBacklogTests: XCTestCase {
    func testFastTypingRetainsCompletedIAndFollowingWords() {
        var queue = CompletedWordBacklog()
        for character in "i ths next" { queue.append(String(character)) }
        XCTAssertEqual(queue.boundaries.map { $0.completedPrefix(in: "i ths next") }, ["i ", "i ths "])
        let first = queue.boundaries[0].id
        queue.remove(first)
        // Changing the earlier word's length leaves distances from the caret intact.
        XCTAssertEqual(queue.boundaries.first?.completedPrefix(in: "I'm ths next"), "I'm ths ")
    }
    func testRepeatedSeparatorsDoNotRevisitAnUndoneWord() {
        var queue = CompletedWordBacklog()
        for character in "teh. " { queue.append(String(character)) }
        queue.remove(queue.boundaries[0].id)
        for character in "  " { queue.append(String(character)) }
        XCTAssertTrue(queue.boundaries.isEmpty)
    }
    func testResetAndBounds() {
        var queue = CompletedWordBacklog()
        for character in String(repeating: "a ", count: 12) { queue.append(String(character)) }
        XCTAssertEqual(queue.boundaries.count, 8)
        for _ in 0..<97 { queue.append("a") }
        XCTAssertTrue(queue.boundaries.isEmpty)
        queue.append(" ")
        queue.append("é")
        XCTAssertTrue(queue.boundaries.isEmpty)
        queue.append(" ")
        XCTAssertTrue(queue.boundaries.isEmpty)
    }
    func testChangedEditorTextFailsBoundaryValidation() {
        var queue = CompletedWordBacklog()
        for character in "i next" { queue.append(String(character)) }
        XCTAssertNil(queue.boundaries.first?.completedPrefix(in: "changed"))
    }
    func testEachBoundaryAllowsOnlyOneSpellingAndOneContextEdit() throws {
        var backlog = CompletedWordBacklog()
        for char in "its a " { backlog.append(String(char)) }
        let id = try XCTUnwrap(backlog.boundaries.last?.id)
        backlog.recordCorrection(id, contextual: false)
        XCTAssertTrue(try XCTUnwrap(backlog.boundaries.last).spellingCorrected)
        XCTAssertFalse(try XCTUnwrap(backlog.boundaries.last).contextCorrected)
        backlog.append("n")
        XCTAssertTrue(try XCTUnwrap(backlog.boundaries.last).spellingCorrected)
        backlog.recordCorrection(id, contextual: true)
        XCTAssertTrue(try XCTUnwrap(backlog.boundaries.last).contextCorrected)
        backlog.remove(id)
        XCTAssertFalse(backlog.boundaries.contains { $0.id == id })
        for char in "ext " { backlog.append(String(char)) }
        XCTAssertFalse(try XCTUnwrap(backlog.boundaries.last).spellingCorrected)
        XCTAssertFalse(try XCTUnwrap(backlog.boundaries.last).contextCorrected)
        backlog.reset()
        XCTAssertTrue(backlog.boundaries.isEmpty)
    }

}
