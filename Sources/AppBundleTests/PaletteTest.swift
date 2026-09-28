@testable import AppBundle
import AppKit
import Common
import XCTest

@MainActor
final class PaletteTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testEveryNamedPaletteResolvesAllRoles() {
        for name in Palette.allNames {
            let palette = Palette(name: name)
            XCTAssertNotNil(palette.focus, name)
            XCTAssertNotNil(palette.inactive, name)
            XCTAssertNotNil(palette.background, name)
            XCTAssertNotNil(palette.text, name)
        }
    }

    func testUnknownNameFallsBackToDefault() {
        XCTAssertEqual(Palette(name: "nope").focus, Palette(name: "default").focus)
        XCTAssertEqual(Palette.allNames.first, "default")
    }

    func testFocusContrastsAgainstBackgroundForOverlays() {
        // WCAG non-text minimum for meaningful UI graphics.
        for name in Palette.allNames {
            let palette = Palette(name: name)
            XCTAssertGreaterThanOrEqual(
                Palette.contrastRatio(palette.focus!, palette.background!),
                3.0,
                "\(name) focus ring must stay visible on its background",
            )
        }
    }

    func testBordersColorPaletteResolvesThroughConfig() {
        let parsed = parseConfig(
            """
            [palette]
            name = 'nord'
            [borders]
            enabled = true
            color = 'palette'
            """)
        assertEquals(parsed.errors, [])
        config = parsed.config
        defer { config = parseConfig("").config }
        XCTAssertEqual(bordersRingColor(config.borders.color, paletteName: config.palette.name), Palette(name: "nord").focus)
    }

    func testPaletteConfigParsesAndDefaults() {
        XCTAssertEqual(parseConfig("").config.palette.name, "default")
        XCTAssertEqual(parseConfig("[palette]\nname = 'dracula'\n").config.palette.name, "dracula")
        XCTAssertFalse(parseConfig("[palette]\nname = 5\n").errors.isEmpty)
    }
}
