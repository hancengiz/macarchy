import XCTest
@testable import AppBundle

@MainActor
final class CurrentShortcutsDescriptionTest: XCTestCase {
    func testDescriptionUsesGlyphChords() {
        let parsed = parseConfig(
            """
            [mode.main.binding]
            alt-shift-left = 'focus --boundaries workspace left'
            f18 = 'mode macarchy'
            """)
        XCTAssertTrue(parsed.errors.isEmpty, "\(parsed.errors)")
        let description = currentShortcutsDescription(parsed.config)
        XCTAssertTrue(description.contains("⌥⇧←"), description)
        XCTAssertFalse(description.contains("alt-shift-left"), description)
        XCTAssertTrue(description.contains("F18"), description)
        XCTAssertTrue(description.contains("MAIN"), description)
        XCTAssertTrue(description.contains("focus --boundaries workspace left"), description)
    }

    func testModesSortedMainFirst() {
        let parsed = parseConfig(
            """
            [mode.main.binding]
            f18 = 'mode macarchy'
            [mode.zzz.binding]
            a = 'mode main'
            """)
        let description = currentShortcutsDescription(parsed.config)
        let mainPos = description.firstRange(of: "MAIN")!.lowerBound
        let zzzPos = description.firstRange(of: "ZZZ")!.lowerBound
        XCTAssertLessThan(mainPos, zzzPos)
    }
}
