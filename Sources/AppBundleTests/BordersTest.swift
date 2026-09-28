@testable import AppBundle
import AppKit
import Common
import XCTest

@MainActor
final class BordersTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testBordersDefaultOff() {
        let parsed = parseConfig("")
        assertEquals(parsed.errors, [])
        XCTAssertEqual(parsed.config.borders.enabled, false)
        XCTAssertEqual(parsed.config.borders.width, 4)
        XCTAssertEqual(parsed.config.borders.color, "auto")
    }

    func testParsesDottedAndTableForms() {
        let dotted = parseConfig("borders.enabled = true\nborders.width = 7\nborders.color = 'blue'\n")
        assertEquals(dotted.errors, [])
        XCTAssertEqual(dotted.config.borders.enabled, true)
        XCTAssertEqual(dotted.config.borders.width, 7)
        XCTAssertEqual(dotted.config.borders.color, "blue")

        let table = parseConfig("[borders]\nenabled = true\n")
        assertEquals(table.errors, [])
        XCTAssertEqual(table.config.borders.enabled, true)
    }

    func testBadWidthIsRejected() {
        XCTAssertFalse(parseConfig("borders.width = 'thick'").errors.isEmpty)
    }

    func testShouldShowGates() {
        let window = TestWindow.new(id: 1, parent: Workspace.get(byName: "a").rootTilingContainer)
        window.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 100, height: 100)
        var enabled = Config(); enabled.borders.enabled = true

        XCTAssertTrue(bordersShouldShow(config: enabled, window: window))
        XCTAssertFalse(bordersShouldShow(config: Config(), window: window), "disabled by default")

        window.isFullscreen = true
        XCTAssertFalse(bordersShouldShow(config: enabled, window: window), "no ring on fullscreen")
        window.isFullscreen = false

        window.lastAppliedLayoutPhysicalRect = nil
        XCTAssertFalse(bordersShouldShow(config: enabled, window: window), "no frame yet")
        window.lastAppliedLayoutPhysicalRect = Rect(topLeftX: 0, topLeftY: 0, width: 100, height: 100)

        _ = window.unbindFromParent()
        XCTAssertFalse(bordersShouldShow(config: enabled, window: window), "unbound window")
    }

    func testRingFrameExpandsByHalfWidth() {
        let rect = CGRect(x: 100, y: 200, width: 300, height: 400)
        XCTAssertEqual(bordersRingFrame(windowRect: rect, width: 4), CGRect(x: 98, y: 198, width: 304, height: 404))
        XCTAssertEqual(bordersRingFrame(windowRect: rect, width: 1), CGRect(x: 99.5, y: 199.5, width: 301, height: 401))
    }

    func testRingColor() {
        XCTAssertEqual(bordersRingColor("auto"), .controlAccentColor)
        XCTAssertEqual(bordersRingColor("blue"), NSColor.blue)
        XCTAssertEqual(bordersRingColor("red"), NSColor.red)
        XCTAssertEqual(bordersRingColor("green"), NSColor.green)
        XCTAssertEqual(bordersRingColor("yellow"), NSColor.yellow)
        XCTAssertEqual(bordersRingColor("cyan"), NSColor.cyan)
        XCTAssertEqual(bordersRingColor("magenta"), NSColor.magenta)
        XCTAssertEqual(bordersRingColor("white"), NSColor.white)
        XCTAssertEqual(bordersRingColor("nonsense"), .controlAccentColor, "unknown falls back to accent")
    }
}
