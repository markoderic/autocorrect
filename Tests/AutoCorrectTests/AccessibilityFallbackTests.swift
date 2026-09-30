import XCTest
@testable import AutoCorrect

final class AccessibilityFallbackTests: XCTestCase {
    func testContentEditableWithoutCharacterCount() {
        XCTAssertEqual(AccessibilityText.boundedSubstring("teh ", reportedCount: nil, range: CFRange(location: 0, length: 4)), "teh ")
        XCTAssertEqual(AccessibilityText.boundedSubstring("🙂 teh ", reportedCount: nil, range: CFRange(location: 3, length: 4)), "teh ")
    }
    func testRejectsOversizeStaleAndInvalidRanges() {
        XCTAssertNil(AccessibilityText.boundedSubstring(String(repeating: "a", count: 16_385), reportedCount: nil, range: CFRange(location: 0, length: 4)))
        for range in [CFRange(location: -1, length: 1), CFRange(location: 0, length: -1), CFRange(location: Int.max, length: 1), CFRange(location: 1, length: Int.max), CFRange(location: 2, length: 3)] {
            XCTAssertNil(AccessibilityText.boundedSubstring("teh ", reportedCount: nil, range: range))
        }
        XCTAssertNil(AccessibilityText.boundedSubstring("teh ", reportedCount: 3, range: CFRange(location: 0, length: 3)))
        XCTAssertEqual(AccessibilityText.boundedSubstring("teh ", reportedCount: 4, range: CFRange(location: 0, length: 4)), "teh ")
    }
    func testAttributedRangeFallbackRequiresAnExactBoundedResponse() {
        let value = NSAttributedString(string: "🙂 speoll ")
        XCTAssertEqual(AccessibilityText.attributedSubstring(value, expectedLength: 10), "🙂 speoll ")
        for length in [-1, 9, 11, 513, Int.max] {
            XCTAssertNil(AccessibilityText.attributedSubstring(value, expectedLength: length))
        }
        XCTAssertNil(AccessibilityText.attributedSubstring("teh ", expectedLength: 4))
        XCTAssertNil(AccessibilityText.attributedSubstring(nil, expectedLength: 4))
    }

    func testDetectsClaudeElectronFrameworkAndLeavesNativeAppsAlone() {
        let bundle = URL(fileURLWithPath: "/Applications/Claude.app")
        XCTAssertTrue(AccessibilityText.needsManualAccessibility(bundleURL: bundle) {
            $0 == "/Applications/Claude.app/Contents/Frameworks/Electron Framework.framework"
        })
        XCTAssertFalse(AccessibilityText.needsManualAccessibility(bundleURL: bundle) { _ in false })
        XCTAssertTrue(AccessibilityText.needsManualAccessibility(bundleURL: URL(fileURLWithPath: "/Applications/Google Chrome.app")) {
            $0.hasSuffix("/Google Chrome Framework.framework")
        })
    }

}

extension AccessibilityFallbackTests {
    func testVerificationReturnsTheHostTextWhenOnlySmartPunctuationDiffers() {
        XCTAssertEqual(AccessibilityText.confirmedText(observed: "it don’t next", expected: "it don't next"), "it don’t next")
        XCTAssertEqual(AccessibilityText.confirmedText(observed: "it don't next", expected: "it don't next"), "it don't next")
        XCTAssertNil(AccessibilityText.confirmedText(observed: "it dont next", expected: "it don't next"))
        XCTAssertNil(AccessibilityText.confirmedText(observed: nil, expected: "it don't next"))
    }
}
