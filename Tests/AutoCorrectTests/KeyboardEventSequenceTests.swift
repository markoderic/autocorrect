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

    func testNativeDecodedBackspacesPrecedeInsertion() throws {
        let (plan, events) = try make("I typed teh ", word: "teh", replacement: "the")
        let decoded = try events.map { try XCTUnwrap(NSEvent(cgEvent: $0)) }
        let down = decoded.filter { $0.type == .keyDown }
        XCTAssertEqual(down.count, plan.deleteCount + plan.insertion.count)
        for event in down.prefix(plan.deleteCount) {
            XCTAssertEqual(event.keyCode, UInt16(kVK_Delete))
            XCTAssertEqual(event.characters, "\u{7F}")
        }
        XCTAssertEqual(down.dropFirst(plan.deleteCount).compactMap(\.characters).joined(), "the ")
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
                XCTAssertEqual(decoded.modifierFlags.intersection(.deviceIndependentFlagsMask), [])
                XCTAssertTrue([UInt16(kVK_Delete), UInt16(kVK_ANSI_A)].contains(decoded.keyCode))
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
            let characters = try events.dropFirst(plan.deleteCount * 2).enumerated().compactMap { index, event -> String? in
                guard index % 2 == 0 else { return nil }
                return try XCTUnwrap(NSEvent(cgEvent: event)?.characters)
            }.joined()
            // Compare UTF-16 units so canonical equivalence cannot hide a changed payload.
            XCTAssertEqual(Array(characters.utf16), Array((replacement + "). ").utf16), replacement)
        }
    }

    func testDecodedEventsPreserveCorrectedWordWhenNextWordArrives() throws {
        let text = "I typed teh "
        let (plan, events) = try make(text, word: "teh", replacement: "the")
        var result = text
        for event in events where event.type == .keyDown {
            let decoded = try XCTUnwrap(NSEvent(cgEvent: event))
            if decoded.keyCode == UInt16(kVK_Delete) {
                result.removeLast()
            } else {
                result += try XCTUnwrap(decoded.characters)
            }
        }
        XCTAssertEqual(result, plan.expectedText)
        result += "next"
        XCTAssertEqual(result, "I typed the next")
    }

    private func unicodePayload(_ event: CGEvent) -> [UniChar] {
        var buffer = [UniChar](repeating: 0, count: 128)
        var length = 0
        event.keyboardGetUnicodeString(maxStringLength: buffer.count, actualStringLength: &length, unicodeString: &buffer)
        return Array(buffer.prefix(length))
    }

}
