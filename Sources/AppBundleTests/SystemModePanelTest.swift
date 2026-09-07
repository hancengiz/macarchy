@testable import AppBundle
import AppKit
import XCTest

@MainActor
final class SystemModePanelTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testProfileRowsDescribeActualActionsAndExitKeys() throws {
        let profile = try String(contentsOf: projectRoot.appending(path: "docs/config-examples/omarchy.toml"), encoding: .utf8)
        let parsed = parseConfig(profile)
        XCTAssertTrue(parsed.errors.isEmpty)
        XCTAssertTrue(parsed.config.showSystemModeOverlay)
        let rows = systemModeShortcuts(parsed.config)
        XCTAssertEqual(rows.count, parsed.config.modes["system"]?.bindings.count)
        XCTAssertEqual(rows.first { $0.id == "b" }?.action, "Bluetooth")
        XCTAssertEqual(rows.first { $0.id == "c" }?.action, "Screenshot")
        XCTAssertEqual(rows.first { $0.id == "alt-shift-esc" }?.key, "Opt+Shift+Esc")
        XCTAssertEqual(rows.filter(\.isExit).count, 2)
        XCTAssertTrue(rows.suffix(2).allSatisfy(\.isExit))
    }

    func testCustomBindingNeverGetsMisleadingDefaultLabel() {
        let parsed = parseConfig("""
            [mode.system.binding]
            b = 'focus left'
            """)
        let rows = systemModeShortcuts(parsed.config)
        XCTAssertEqual(rows.first?.action, "focus left")
        XCTAssertFalse(rows.first?.isExit ?? true)
    }

    func testOverlayFitsBottomLeftIncludingNegativeMonitorCoordinates() {
        for visible in [CGRect(x: 0, y: 50, width: 1440, height: 850),
                        CGRect(x: -1920, y: -200, width: 1920, height: 1080),
                        CGRect(x: 0, y: 0, width: 240, height: 280)]
        {
            let frame = systemModePanelFrame(visibleFrame: visible, contentSize: CGSize(width: 330, height: 410))
            XCTAssertEqual(frame.minX, visible.minX + 16)
            XCTAssertEqual(frame.minY, visible.minY + 16)
            XCTAssertTrue(visible.contains(frame))
        }
    }

    func testCurrentReferenceUsesLoadedBindingsAndGroupsMainFirst() {
        let parsed = parseConfig("""
            [mode.main.binding]
            alt-t = 'layout floating tiling'
            [mode.system.binding]
            esc = 'mode main'
            """)
        let text = currentShortcutsDescription(parsed.config)
        XCTAssertTrue(text.hasPrefix("MAIN\n"))
        XCTAssertTrue(text.contains("alt-t\n    layout floating tiling"))
        XCTAssertTrue(text.contains("SYSTEM\n"))
        XCTAssertFalse(text.contains("alt-esc"))
    }
}
