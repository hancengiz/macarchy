import XCTest
@testable import MacarchySettingsCore

final class ThemeTest: XCTestCase {
    func testTextContrastMeetsWCAGAA() {
        for palette in [Theme.light, Theme.dark] {
            XCTAssertGreaterThanOrEqual(
                Theme.contrastRatio(palette.primaryTextRgb, palette.backgroundRgb), 7,
                "primary text must hit AAA on \(palette.name)")
            XCTAssertGreaterThanOrEqual(
                Theme.contrastRatio(palette.secondaryTextRgb, palette.backgroundRgb), 4.5,
                "secondary text must hit AA on \(palette.name)")
            XCTAssertGreaterThanOrEqual(
                Theme.contrastRatio(palette.accentRgb, palette.backgroundRgb), 4.5,
                "accent must hit AA on \(palette.name)")
            XCTAssertGreaterThanOrEqual(
                Theme.contrastRatio(palette.primaryTextRgb, palette.cardBackgroundRgb), 7,
                "primary text must hit AAA on cards (\(palette.name))")
        }
    }
}
