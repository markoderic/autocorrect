import Foundation
import XCTest
@testable import AutoCorrectCore

final class ManualRewriteProtectionTests: XCTestCase {
    private let field = UUID()
    private func candidate(_ word: String, in text: String) -> CorrectionCandidate {
        CorrectionCandidate(original: word, range: (text as NSString).range(of: word))
    }
    private func record(_ protection: inout ManualRewriteProtection, text: String = "Install homebrew ", now: TimeInterval = 10) {
        protection.recordPostedCorrection(field: field, text: text, windowStart: 0,
                                          range: (text as NSString).range(of: "homebrew"), replacement: "homebred", now: now)
    }
    private func suppressed(_ protection: inout ManualRewriteProtection, word: String = "homebrew",
                            text: String = "Install homebrew ", now: TimeInterval = 10.03) -> Bool {
        protection.suppresses(field: field, candidate: candidate(word, in: text), text: text, windowStart: 0, now: now)
    }

    func testQuickManualRestoreBeforeVerificationStopsRepeatedCorrection() {
        var protection = ManualRewriteProtection()
        record(&protection)
        XCTAssertFalse(suppressed(&protection)) // A stale pre-edit AX read alone proves nothing.
        protection.noteManualEdit(now: 10.001) // Backspace before the 40ms verification.
        XCTAssertTrue(suppressed(&protection, now: 10.03))
        XCTAssertTrue(suppressed(&protection, text: "Install homebrew  ", now: 11))
        protection.noteManualEdit(now: 12)
        XCTAssertTrue(suppressed(&protection, text: "Install homebrew ", now: 13))
        XCTAssertFalse(suppressed(&protection, word: "homebred", text: "Install homebred ", now: 14))
    }

    func testDifferentManualSpellingAndNativeUndoAreProtectedAtSameOccurrence() {
        var protection = ManualRewriteProtection()
        record(&protection)
        protection.noteManualEdit(now: 10.01) // The same signal is used for native Command-Z.
        XCTAssertTrue(suppressed(&protection, word: "homebreww", text: "Install homebreww "))
        XCTAssertTrue(suppressed(&protection, word: "Homebrew", text: "Install Homebrew "))
    }

    func testSameWordElsewhereAndChangedContextAreNotIgnored() {
        var protection = ManualRewriteProtection()
        record(&protection)
        protection.noteManualEdit(now: 10.01)
        XCTAssertFalse(suppressed(&protection, text: "Install another homebrew "))
        XCTAssertFalse(suppressed(&protection, text: "Unpack! homebrew ")) // Same offset, different anchor.
        let text = "Install homebrew "
        XCTAssertFalse(protection.suppresses(field: UUID(), candidate: candidate("homebrew", in: text), text: text, windowStart: 0, now: 11))
        protection.reset() // Focus/permission/settings invalidation.
        XCTAssertFalse(suppressed(&protection, now: 12))
    }

    func testCanceledAndUnconfirmedEditsDoNotCreateProtection() throws {
        var protection = ManualRewriteProtection()
        protection.noteManualEdit(now: 9) // An event canceling a request before it posts.
        XCTAssertFalse(suppressed(&protection))
        let text = "Install homebrew "
        let id = try XCTUnwrap(protection.recordPostedCorrection(field: field, text: text, windowStart: 0,
            range: candidate("homebrew", in: text).range, replacement: "homebred", now: 10))
        XCTAssertFalse(suppressed(&protection)) // Earlier manual actions do not mark a new edit.
        protection.remove(id) // A posted edit subsequently fails verification without manual edits.
        protection.noteManualEdit(now: 10.01)
        XCTAssertFalse(suppressed(&protection))
    }

    func testUnconfirmedExpirationAndClockRollbackFailClosed() {
        var protection = ManualRewriteProtection()
        record(&protection)
        protection.noteManualEdit(now: 11)
        XCTAssertFalse(suppressed(&protection, now: 130.001))
        record(&protection, now: 200)
        protection.noteManualEdit(now: 201)
        XCTAssertFalse(suppressed(&protection, now: 199))
    }

    func testConfirmedManualRewriteDoesNotRestartAfterTwoMinutes() {
        var protection = ManualRewriteProtection()
        record(&protection)
        protection.noteManualEdit(now: 11)
        XCTAssertTrue(suppressed(&protection, now: 12))
        XCTAssertTrue(suppressed(&protection, now: 10000))
        protection.reset()
        XCTAssertFalse(suppressed(&protection, now: 10001))
    }

    func testSnapshotMovementRequiresEntireOriginalPrefixAnchor() {
        var protection = ManualRewriteProtection()
        let text = String(repeating: "x", count: 60) + " homebrew "
        record(&protection, text: text)
        protection.noteManualEdit(now: 10.01)
        let shifted = String(text.dropFirst(20))
        XCTAssertTrue(protection.suppresses(field: field, candidate: candidate("homebrew", in: shifted),
                                            text: shifted, windowStart: 20, now: 11))
        let clipped = String(text.dropFirst(40))
        XCTAssertFalse(protection.suppresses(field: field, candidate: candidate("homebrew", in: clipped),
                                             text: clipped, windowStart: 40, now: 11))
    }

    func testHistoryIsBoundedToEightOccurrences() {
        var protection = ManualRewriteProtection()
        for index in 0..<9 {
            let text = String(repeating: "x ", count: index) + "homebrew "
            record(&protection, text: text)
        }
        protection.noteManualEdit(now: 10.01)
        XCTAssertFalse(suppressed(&protection, text: "homebrew "))
        XCTAssertTrue(suppressed(&protection, text: String(repeating: "x ", count: 8) + "homebrew "))
    }

    func testInvalidSnapshotAndRangesCannotMatchOrRegister() {
        var protection = ManualRewriteProtection()
        XCTAssertNil(protection.recordPostedCorrection(field: field, text: "teh ", windowStart: Int.max,
            range: NSRange(location: 0, length: 3), replacement: "the", now: 10))
        XCTAssertNil(protection.recordPostedCorrection(field: field, text: "e\u{301} ", windowStart: 0,
            range: NSRange(location: 0, length: 1), replacement: "e", now: 10))
        XCTAssertNil(protection.recordPostedCorrection(field: field, text: "teh ", windowStart: 100,
            range: NSRange(location: 0, length: 3), replacement: "the", now: 10))
        record(&protection)
        protection.noteManualEdit(now: 10.01)
        XCTAssertFalse(protection.suppresses(field: field, candidate: CorrectionCandidate(original: "homebrew", range: NSRange(location: 8, length: Int.max)),
            text: "Install homebrew ", windowStart: 0, now: 11))
    }
}
