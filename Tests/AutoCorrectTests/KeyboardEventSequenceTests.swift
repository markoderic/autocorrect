import AppKit
import Carbon
import XCTest
import AutoCorrectCore
@testable import AutoCorrect

final class KeyboardEventSequenceTests: XCTestCase {
    private let marker: Int64 = 0x4155434900000000

    private func make(_ text: String, word: String, replacement: String) throws -> (KeyboardReplacementPlan, [CGEvent]) {
        let plan = try XCTUnwrap(KeyboardReplacementPlan.make(text: text, wordRange: (text as NSString).range(of: word), replacement: replacement))
        return (plan, try XCTUnwrap(KeyboardEventSequence.make(plan: plan, marker: marker)))
    }

    func testNativeDecodedMinimalEditMatchesPlan() throws {
        let (plan, events) = try make("I typed teh ", word: "teh", replacement: "the")
        let decoded = try events.map { try XCTUnwrap(NSEvent(cgEvent: $0)) }.filter { $0.type == .keyDown }
        let edit = plan.cursorEdit
        XCTAssertEqual(decoded.count, edit.moveLeft + edit.deleteCount + edit.insertion.count + edit.moveRight)
        XCTAssertTrue(decoded.prefix(edit.moveLeft).allSatisfy { $0.keyCode == UInt16(kVK_LeftArrow) })
        for event in decoded.dropFirst(edit.moveLeft).prefix(edit.deleteCount) {
            XCTAssertEqual(event.keyCode, UInt16(kVK_Delete))
            XCTAssertEqual(event.characters, "\u{7F}")
        }
        XCTAssertEqual(decoded.dropFirst(edit.moveLeft + edit.deleteCount).prefix(edit.insertion.count).compactMap(\.characters).joined(), edit.insertion)
        XCTAssertTrue(decoded.suffix(edit.moveRight).allSatisfy { $0.keyCode == UInt16(kVK_RightArrow) })
    }

    func testEveryEventIsBalancedUnmodifiedAndTagged() throws {
        let (_, events) = try make("Tehh, ", word: "Tehh", replacement: "The")
        XCTAssertEqual(events.count % 2, 0)
        for index in stride(from: 0, to: events.count, by: 2) {
            let down = events[index]
            let up = events[index + 1]
            XCTAssertEqual(down.type, .keyDown)
            XCTAssertEqual(up.type, .keyUp)
            XCTAssertEqual(down.getIntegerValueField(.keyboardEventKeycode), up.getIntegerValueField(.keyboardEventKeycode))
            for event in [down, up] {
                XCTAssertEqual(event.flags, [])
                XCTAssertEqual(event.getIntegerValueField(.eventSourceUserData), marker)
                XCTAssertEqual(event.getIntegerValueField(.keyboardEventAutorepeat), 0)
                let decoded = try XCTUnwrap(NSEvent(cgEvent: event))
                // AppKit classifies arrow key codes as function keys even with raw flags=0.
                let arrow = [UInt16(kVK_LeftArrow), UInt16(kVK_RightArrow)].contains(decoded.keyCode)
                XCTAssertEqual(decoded.modifierFlags.intersection(.deviceIndependentFlagsMask), arrow ? [.function] : [])
                XCTAssertTrue([UInt16(kVK_Delete), UInt16(kVK_ANSI_A), UInt16(kVK_LeftArrow), UInt16(kVK_RightArrow)].contains(decoded.keyCode))
            }
            // AppKit uses Unicode overrides for keyDown text insertion. NSEvent's
            // keyUp conversion can instead report the underlying physical key.
            // Verify balanced raw payloads without assuming keyUp inserts text.
            XCTAssertEqual(unicodePayload(down), unicodePayload(up))
        }
    }

    func testNativeDecodedUnicodeCaseAndContractionsAreExact() throws {
        for replacement in ["The", "iPhone", "don't", "don’t", "café", "cafe\u{301}", "日本語", "𐐀𐐨"] {
            let (plan, events) = try make("🙂 teh). ", word: "teh", replacement: replacement)
            let characters = try events.filter { $0.type == .keyDown && $0.getIntegerValueField(.keyboardEventKeycode) == 0 }.map {
                try XCTUnwrap(NSEvent(cgEvent: $0)?.characters)
            }.joined()
            XCTAssertEqual(Array(characters.utf16), Array(plan.cursorEdit.insertion.utf16), replacement)
            let result = try apply(events, to: "🙂 teh). ")
            XCTAssertEqual(Array(result.text.utf16), Array(plan.expectedText.utf16), replacement)
            XCTAssertEqual(result.caret, plan.expectedCaret)

        }
    }

    func testDecodedEventsPreserveCorrectedWordWhenNextWordArrives() throws {
        let text = "I typed teh "
        let (plan, events) = try make(text, word: "teh", replacement: "the")
        let result = try apply(events, to: text)
        XCTAssertEqual(result.text, plan.expectedText)
        XCTAssertEqual(result.caret, plan.expectedCaret)
        XCTAssertEqual(result.text + "next", "I typed the next")
    }

    func testMinimalEditsPreserveLongSuffixAndUndoContractions() throws {
        for (word, replacement) in [("Its", "It's"), ("it's", "its"), ("lets", "let's"), ("let's", "lets"),
                                    ("helo", "hello"), ("Tehh", "The"), ("doest", "doesn't"), ("dont", "don’t")] {
            for suffix in [" ", ", next ", " \"quoted\" ", " " + String(repeating: "x", count: 90)] {
                let text = "🙂 " + word + suffix
                let (plan, events) = try make(text, word: word, replacement: replacement)
                let result = try apply(events, to: text)
                XCTAssertEqual(result.text, "🙂 " + replacement + suffix)
                XCTAssertEqual(result.caret, plan.expectedCaret)
                XCTAssertGreaterThanOrEqual(plan.cursorEdit.moveLeft, suffix.count)
            }
        }
    }

    private func apply(_ events: [CGEvent], to text: String) throws -> (text: String, caret: Int) {
        var units = Array(text.utf16), caret = text.utf16.count
        for event in events where event.type == .keyDown {
            let native = try XCTUnwrap(NSEvent(cgEvent: event))
            switch native.keyCode {
            case UInt16(kVK_LeftArrow): caret -= 1
            case UInt16(kVK_RightArrow): caret += 1
            case UInt16(kVK_Delete): caret -= 1; units.remove(at: caret)
            default:
                let inserted = Array(try XCTUnwrap(native.characters).utf16)
                units.insert(contentsOf: inserted, at: caret); caret += inserted.count
            }
            XCTAssertTrue((0...units.count).contains(caret))
        }
        return (String(decoding: units, as: UTF16.self), caret)
    }

    func testCompletedFirstWordNeverEmptiesReactiveEditor() throws {
        for (text, word, replacement) in [("its ", "its", "Its"), ("its a test ", "its", "it's"),
                                           ("lets fix this ", "lets", "let's"), ("helo ", "helo", "Hello")] {
            let (plan, events) = try make(text, word: word, replacement: replacement)
            var units = Array(text.utf16)
            var caret = units.count
            var emptied = false
            for event in events where event.type == .keyDown {
                let code = event.getIntegerValueField(.keyboardEventKeycode)
                switch code {
                case Int64(kVK_LeftArrow): caret = max(0, caret - 1)
                case Int64(kVK_RightArrow): caret = min(units.count, caret + 1)
                case Int64(kVK_Delete):
                    if caret > 0 { caret -= 1; units.remove(at: caret) }
                default:
                    let inserted = unicodePayload(event)
                    units.insert(contentsOf: inserted, at: caret); caret += inserted.count
                }
                emptied = emptied || units.isEmpty
            }
            XCTAssertFalse(emptied, "Do not reset a reactive composer by clearing its entire value: \(text)")
            XCTAssertEqual(String(decoding: units, as: UTF16.self), plan.expectedText)
            XCTAssertEqual(caret, plan.expectedCaret)
        }
    }

    private func unicodePayload(_ event: CGEvent) -> [UniChar] {
        var buffer = [UniChar](repeating: 0, count: 128)
        var length = 0
        event.keyboardGetUnicodeString(maxStringLength: buffer.count, actualStringLength: &length, unicodeString: &buffer)
        return Array(buffer.prefix(length))
    }

}
