@testable import AppBundle
import Common
import XCTest

@MainActor
final class ToggleSplitCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testParse() {
        assertNil(parseCommand("toggle-split vertical").errorOrNil)
        assertNil(parseCommand("toggle-split opposite --window-id 1").errorOrNil)
        XCTAssertNotNil(parseCommand("toggle-split diagonal").errorOrNil)
        XCTAssertNotNil(parseCommand("toggle-split").errorOrNil)
    }

    func testNextWindowWrapsVerticallyInHorizontalTilesRoot() async {
        let workspace = focus.workspace
        let root = workspace.rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
        }

        let result = await parseCommand("toggle-split opposite").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(result.stdout, ["The next new window will join the focused window in a vertical split"])

        let binding = unbindAndGetBindingDataForNewTilingWindow(workspace, window: nil)
        let parent = consumeSplitHint(binding.splitHint.orDie()) ?? binding.parent
        _ = TestWindow.new(id: 2, parent: parent, adaptiveWeight: binding.adaptiveWeight)

        assertEquals(root.layoutDescription, .h_tiles([
            .v_tiles([.window(1), .window(2)]),
        ]))
        // The hint is consumed after one use
        XCTAssertNil(workspace.mostRecentWindowRecursive?.nextSplitOrientation)
    }

    func testNextWindowWrapsVerticallyInsideScrollingColumn() async throws {
        let workspace = focus.workspace
        let root = workspace.rootTilingContainer
        root.layout = .scrolling
        _ = TestWindow.new(id: 1, parent: root).focusWindow()

        _ = await parseCommand("toggle-split opposite").cmdOrDie.run(.defaultEnv, .emptyStdin)

        let binding = unbindAndGetBindingDataForNewTilingWindow(workspace, window: nil)
        let parent = consumeSplitHint(binding.splitHint.orDie()) ?? binding.parent
        _ = TestWindow.new(id: 2, parent: parent, adaptiveWeight: binding.adaptiveWeight)

        let column = try XCTUnwrap(root.children.singleOrNil() as? TilingContainer)
        XCTAssertEqual(column.orientation, .v)
        XCTAssertEqual(column.layout, .tiles)
        XCTAssertEqual(column.children.compactMap { ($0 as? Window)?.windowId }, [1, 2])
    }

    func testArmedDirectionMatchingParentInsertsFlat() async {
        let workspace = focus.workspace
        let root = workspace.rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
        }

        // .h root: arming "horizontal" matches the parent, so the next window
        // binds as a plain sibling (same-orientation nesting is pointless)
        _ = await parseCommand("toggle-split horizontal").cmdOrDie.run(.defaultEnv, .emptyStdin)
        let binding = unbindAndGetBindingDataForNewTilingWindow(workspace, window: nil)
        let parent = consumeSplitHint(binding.splitHint.orDie()) ?? binding.parent
        _ = TestWindow.new(id: 2, parent: parent, adaptiveWeight: binding.adaptiveWeight)

        assertEquals(root.layoutDescription, .h_tiles([.window(1), .window(2)]))
    }

    func testOppositeTogglesArmedDirectionBackAndForth() async {
        let workspace = focus.workspace
        let window = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        _ = window.focusWindow()

        _ = await parseCommand("toggle-split opposite").cmdOrDie.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(window.nextSplitOrientation, .v)
        _ = await parseCommand("toggle-split opposite").cmdOrDie.run(.defaultEnv, .emptyStdin)
        XCTAssertEqual(window.nextSplitOrientation, .h)
    }

    func testFailsForNonTilingWindow() async {
        let window = TestWindow.new(id: 1, parent: focus.workspace.floatingWindowsContainer)
        _ = window.focusWindow()

        let result = await parseCommand("toggle-split opposite").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 2)
    }
}
