@testable import AppBundle
import AppKit
import Common
import XCTest

@MainActor
final class BarTest: XCTestCase {
    func testBarConfigDefaultsOff() {
        let parsed = parseConfig("")
        assertEquals(parsed.errors, [])
        XCTAssertEqual(parsed.config.bar.enabled, false)
        XCTAssertEqual(parsed.config.bar.height, 28)
        XCTAssertEqual(parsed.config.bar.hideWithMenuBar, true)
    }

    func testMenuBarAwarePlacementAndHiding() {
        // Auto-hidden menu bar: visibleFrame reaches the screen top → bar at the very top.
        let frame = CGRect(x: 0, y: 0, width: 3440, height: 1440)
        let autoHidden = frame
        XCTAssertEqual(barYTop(screenFrame: frame, visibleFrame: autoHidden), frame.maxY)
        // Visible menu bar: bar sits below it.
        let withMenuBar = CGRect(x: 0, y: 25, width: 3440, height: 1415)
        XCTAssertEqual(barYTop(screenFrame: frame, visibleFrame: withMenuBar), withMenuBar.maxY)
        // While the menu bar is revealed by the mouse, the bar hides.
        XCTAssertTrue(barHiddenForMenuBar(mouseY: frame.maxY - 10, screenFrame: frame, visibleFrame: withMenuBar))
        XCTAssertFalse(barHiddenForMenuBar(mouseY: frame.maxY - 200, screenFrame: frame, visibleFrame: withMenuBar))
        // Auto-hidden screens: only hide while the pointer is inside the reveal band.
        XCTAssertTrue(barHiddenForMenuBar(mouseY: frame.maxY - 5, screenFrame: frame, visibleFrame: autoHidden))
        XCTAssertFalse(barHiddenForMenuBar(mouseY: frame.maxY - 60, screenFrame: frame, visibleFrame: autoHidden))
    }

    func testBarConfigParses() {
        let parsed = parseConfig("[bar]\nenabled = true\nheight = 34\n")
        assertEquals(parsed.errors, [])
        XCTAssertEqual(parsed.config.bar.enabled, true)
        XCTAssertEqual(parsed.config.bar.height, 34)
        XCTAssertFalse(parseConfig("bar.height = 'tall'").errors.isEmpty)
    }

    func testCellsGroupByMonitorOrderAndMarkStates() {
        let cells = barCells(
            monitors: [
                BarMonitor(id: 1, activeWorkspace: "1"),
                BarMonitor(id: 2, activeWorkspace: "3"),
            ],
            workspaces: [
                BarWorkspace(name: "1", monitorId: 1, isVisible: true, isEffectivelyEmpty: false),
                BarWorkspace(name: "2", monitorId: 1, isVisible: false, isEffectivelyEmpty: true),
                BarWorkspace(name: "3", monitorId: 2, isVisible: true, isEffectivelyEmpty: false),
                BarWorkspace(name: "scratch", monitorId: nil, isVisible: false, isEffectivelyEmpty: true),
            ],
            focusedWorkspace: "1",
        )
        XCTAssertEqual(cells.count, 2)
        XCTAssertEqual(cells[0].monitorId, 1)
        XCTAssertEqual(cells[0].cells.map(\.name), ["1", "2"])
        XCTAssertEqual(cells[0].cells[0].state, .focused)
        XCTAssertEqual(cells[0].cells[1].state, .hidden)
        XCTAssertEqual(cells[1].monitorId, 2)
        XCTAssertEqual(cells[1].cells.map(\.name), ["3"])
        XCTAssertEqual(cells[1].cells[0].state, .visible)
    }
}
