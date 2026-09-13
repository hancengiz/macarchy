@testable import AppBundle
import Common
import XCTest

@MainActor
final class ScrollingLayoutTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testFocusResizeAndToggleOnSameWorkspace() async throws {
        let workspace = focus.workspace
        let root = workspace.rootTilingContainer
        let windows = (1 ... 5).map { TestWindow.new(id: UInt32($0), parent: root) }
        XCTAssertTrue(windows[0].focusWindow())
        let toggle = parseCommand("layout --root scrolling h_tiles").cmdOrDie
        let result = await toggle.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(result.exitCode.rawValue, 0)
        XCTAssertEqual(root.layout, .scrolling)
        try await workspace.layoutWorkspace()
        let width = try await windows[0].getAxSize(.nonCancellable)?.width
        XCTAssertNotNil(width)
        XCTAssertTrue(windows[4].isOutsideScrollingViewport)

        for window in windows.dropFirst() {
            let result = await parseCommand("focus --boundaries workspace right").cmdOrDie.run(.defaultEnv, .emptyStdin)
            XCTAssertEqual(result.exitCode.rawValue, 0)
            XCTAssertEqual(focus.windowOrNil, window)
            try await workspace.layoutWorkspace()
            XCTAssertFalse(window.isOutsideScrollingViewport)
            XCTAssertTrue(focus.workspace === workspace)
        }
        XCTAssertGreaterThan(root.scrollingOffset, 0)
        let before = try XCTUnwrap(windows[4].lastAppliedLayoutPhysicalRect).width
        let resize = await parseCommand("resize width +100").cmdOrDie.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(resize.exitCode.rawValue, 0)
        try await workspace.layoutWorkspace()
        XCTAssertEqual(try XCTUnwrap(windows[4].lastAppliedLayoutPhysicalRect).width, before + 100, accuracy: 0.1)
        XCTAssertNil(windows[0].scrollingSize)

        _ = await toggle.run(.defaultEnv, .emptyStdin)
        try await workspace.layoutWorkspace()
        XCTAssertEqual(root.layout, .tiles)
        XCTAssertTrue(windows.allSatisfy { !$0.isOutsideScrollingViewport })
        XCTAssertTrue(focus.workspace === workspace)
    }

    func testSizesSurviveScrollingTilesRoundTrip() async throws {
        let workspace = focus.workspace
        let root = workspace.rootTilingContainer
        let windows = (1 ... 3).map { TestWindow.new(id: UInt32($0), parent: root) }
        XCTAssertTrue(windows[0].focusWindow())
        root.layout = .scrolling
        try await workspace.layoutWorkspace()

        // Widen the focused column; the other two keep the default width
        _ = await parseCommand("resize width +200").cmdOrDie.run(.defaultEnv, .emptyStdin)
        try await workspace.layoutWorkspace()
        let scrollingWidths = windows.map { try XCTUnwrap($0.lastAppliedLayoutPhysicalRect).width }
        XCTAssertEqual(scrollingWidths[1], scrollingWidths[2], accuracy: 0.1)
        XCTAssertGreaterThan(scrollingWidths[0], scrollingWidths[1])

        // Switching to tiles must carry the proportions over instead of equalizing
        _ = await parseCommand("layout --root h_tiles").cmdOrDie.run(.defaultEnv, .emptyStdin)
        try await workspace.layoutWorkspace()
        let tilesWidths = windows.map { try XCTUnwrap($0.lastAppliedLayoutPhysicalRect).width }
        XCTAssertEqual(tilesWidths[0] / tilesWidths[1], scrollingWidths[0] / scrollingWidths[1], accuracy: 0.02)
        XCTAssertEqual(tilesWidths[1], tilesWidths[2], accuracy: 0.1)

        // And back to scrolling: proportions are preserved (absolute widths of an
        // offscreen tape cannot map into an equal-extent tiles row and back)
        _ = await parseCommand("layout --root scrolling").cmdOrDie.run(.defaultEnv, .emptyStdin)
        try await workspace.layoutWorkspace()
        let restoredWidths = windows.map { try XCTUnwrap($0.lastAppliedLayoutPhysicalRect).width }
        XCTAssertEqual(restoredWidths[0] / restoredWidths[1], scrollingWidths[0] / scrollingWidths[1], accuracy: 0.02)
        XCTAssertEqual(restoredWidths[1], restoredWidths[2], accuracy: 0.1)
    }

    func testProfileAndColumnWidthValidation() throws {
        let url = projectRoot.appending(path: "docs/config-examples/omarchy.toml")
        let parsed = parseConfig(try String(contentsOf: url, encoding: .utf8))
        XCTAssertTrue(parsed.errors.isEmpty, "\(parsed.errors)")
        XCTAssertEqual(parsed.config.defaultRootContainerLayout, .scrolling)
        XCTAssertEqual(parsed.config.mouseModifier, .alt)
        XCTAssertTrue(parsed.config.adoptNativeWindowResize)
        XCTAssertTrue(parsed.config.warnAboutShortcutConflicts)
        for invalid in [0, 9, 101] {
            XCTAssertFalse(parseConfig("scrolling-column-width = \(invalid)").errors.isEmpty)
        }
    }

    func testSplitToggleKeepsScrollingHorizontal() async {
        let root = focus.workspace.rootTilingContainer
        let window = TestWindow.new(id: 1, parent: root)
        _ = window.focusWindow()
        root.layout = .scrolling
        let split = parseCommand("layout horizontal vertical").cmdOrDie
        _ = await split.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(root.orientation, .h)
        _ = await parseCommand("layout --root h_tiles").cmdOrDie.run(.defaultEnv, .emptyStdin)
        _ = await split.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(root.orientation, .v)
        _ = await split.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(root.orientation, .h)
    }
}
