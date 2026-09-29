import Foundation
import XCTest
@testable import AutoCorrect

final class CapitalizationPreferencesTests: XCTestCase {
    func testDefaultEnabledAndExplicitDisableEnablePersist() throws {
        let suite = "AutoCorrectTests.Capitalization.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)
        XCTAssertTrue(preferences.capitalizesAfterPeriod)
        preferences.capitalizesAfterPeriod = false
        XCTAssertFalse(Preferences(defaults: defaults).capitalizesAfterPeriod)
        XCTAssertEqual(defaults.object(forKey: "capitalizesAfterPeriod") as? Bool, false)
        preferences.capitalizesAfterPeriod = true
        XCTAssertTrue(Preferences(defaults: defaults).capitalizesAfterPeriod)
        XCTAssertEqual(defaults.object(forKey: "capitalizesAfterPeriod") as? Bool, true)
    }
}
