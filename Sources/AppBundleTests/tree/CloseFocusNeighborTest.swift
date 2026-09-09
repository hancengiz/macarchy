@testable import AppBundle
import XCTest

@MainActor
final class CloseFocusNeighborTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testFocusedCloseRedirectsToLeftNeighbor() {
        let workspace = Workspace.get(byName: name)
        workspace.rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            TestWindow.new(id: 2, parent: $0)
            TestWindow.new(id: 3, parent: $0)
        }
        let middle = Window.get(byId: 2)
        XCTAssertTrue(middle!.focusWindow())

        let redirect = middle!.focusRedirectionOnClose()

        XCTAssertEqual(redirect?.windowOrNil?.windowId, 1)
        XCTAssertEqual(redirect?.workspace.name, workspace.name)
    }

    func testFocusedLeftmostCloseRedirectsToRightNeighbor() {
        let workspace = Workspace.get(byName: name)
        workspace.rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            TestWindow.new(id: 2, parent: $0)
        }
        let leftmost = Window.get(byId: 1)
        XCTAssertTrue(leftmost!.focusWindow())

        XCTAssertEqual(leftmost!.focusRedirectionOnClose()?.windowOrNil?.windowId, 2)
    }

    func testCloseInsideNestedContainerRedirectsToSibling() {
        Workspace.get(byName: name).rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                TestWindow.new(id: 2, parent: $0)
                TestWindow.new(id: 3, parent: $0)
            }
        }
        let closing = Window.get(byId: 3)
        XCTAssertTrue(closing!.focusWindow())

        XCTAssertEqual(closing!.focusRedirectionOnClose()?.windowOrNil?.windowId, 2)
    }

    func testCloseNextToContainerRedirectsToItsMruLeaf() {
        Workspace.get(byName: name).rootTilingContainer.apply {
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                TestWindow.new(id: 1, parent: $0)
                TestWindow.new(id: 2, parent: $0)
            }
            TestWindow.new(id: 3, parent: $0)
        }
        Window.get(byId: 1)!.markAsMostRecentChild()
        let closing = Window.get(byId: 3)
        XCTAssertTrue(closing!.focusWindow())

        XCTAssertEqual(closing!.focusRedirectionOnClose()?.windowOrNil?.windowId, 1)
    }

    func testUnfocusedCloseKeepsMruBehavior() {
        Workspace.get(byName: name).rootTilingContainer.apply {
            _ = TestWindow.new(id: 1, parent: $0).focusWindow()
            TestWindow.new(id: 2, parent: $0)
        }

        XCTAssertNil(Window.get(byId: 2)?.focusRedirectionOnClose())
    }

    func testFocusedFloatingCloseKeepsMruBehavior() {
        let workspace = Workspace.get(byName: name)
        let floating = TestWindow.new(
            id: 1,
            parent: workspace.floatingWindowsContainer,
            rect: Rect(topLeftX: 0, topLeftY: 0, width: 100, height: 100),
        )
        XCTAssertTrue(floating.focusWindow())

        XCTAssertNil(floating.focusRedirectionOnClose())
    }

    func testSingleWindowCloseHasNoNeighbor() {
        let workspace = Workspace.get(byName: name)
        let only = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        XCTAssertTrue(only.focusWindow())

        XCTAssertNil(only.focusRedirectionOnClose())
    }
}
