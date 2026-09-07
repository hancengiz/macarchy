@testable import AppBundle
import AppKit
import XCTest

@MainActor
final class ManagedResizeTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testTileResizeConservesSpaceAndCanReturnToStart() async throws {
        let workspace = focus.workspace
        let root = workspace.rootTilingContainer
        root.layout = .tiles
        let first = TestWindow.new(id: 1, parent: root)
        let second = TestWindow.new(id: 2, parent: root)
        try await workspace.layoutWorkspace()
        let rect = try XCTUnwrap(first.lastAppliedLayoutPhysicalRect)
        let weights = (first.getWeight(.h), second.getWeight(.h))
        let resize = ManagedResize(window: first, rect: rect, fromLeft: false, fromTop: false)
        resize.apply(width: rect.width + 60, height: rect.height)
        XCTAssertEqual(first.getWeight(.h), weights.0 + 60)
        XCTAssertEqual(second.getWeight(.h), weights.1 - 60)
        resize.apply(width: rect.width + 80, height: rect.height)
        XCTAssertEqual(first.getWeight(.h), weights.0 + 80)
        resize.apply(width: rect.width, height: rect.height)
        XCTAssertEqual(first.getWeight(.h), weights.0)
        XCTAssertEqual(second.getWeight(.h), weights.1)
        resize.apply(width: rect.width + 100_000, height: rect.height)
        XCTAssertEqual(first.getWeight(.h) + second.getWeight(.h), weights.0 + weights.1)
        XCTAssertGreaterThanOrEqual(second.getWeight(.h), 100)
    }

    func testNativeColumnResizePersistsAndDoesNotResizeNeighbor() async throws {
        config.adoptNativeWindowResize = true
        let workspace = focus.workspace
        let root = workspace.rootTilingContainer
        root.layout = .scrolling
        let first = TestWindow.new(id: 1, parent: root)
        let second = TestWindow.new(id: 2, parent: root)
        _ = first.focusWindow()
        try await workspace.layoutWorkspace()
        let rect = try XCTUnwrap(first.lastAppliedLayoutPhysicalRect)
        let neighbor = try XCTUnwrap(second.lastAppliedLayoutPhysicalRect)
        let unchanged = try await adoptNativeWindowResize(first)
        XCTAssertFalse(unchanged)
        first.setAxFrame(nil, CGSize(width: rect.width + 75, height: rect.height))
        let adopted = try await adoptNativeWindowResize(first)
        XCTAssertTrue(adopted)
        try await workspace.layoutWorkspace()
        XCTAssertEqual(try XCTUnwrap(first.lastAppliedLayoutPhysicalRect).width, rect.width + 75)
        XCTAssertEqual(try XCTUnwrap(second.lastAppliedLayoutPhysicalRect).width, neighbor.width)
        let repeatEvent = try await adoptNativeWindowResize(first)
        XCTAssertFalse(repeatEvent)
        XCTAssertNil(second.scrollingSize)
    }

    func testCornerResizeAnchorsOppositeCornerAndClamps() {
        let window = TestWindow.new(id: 1, parent: focus.workspace.rootTilingContainer)
        let rect = Rect(topLeftX: 20, topLeftY: 40, width: 500, height: 400)
        let resize = ManagedResize(window: window, rect: rect, fromLeft: true, fromTop: true)
        let expanded = resize.draggedRect(delta: CGPoint(x: -50, y: -60))
        XCTAssertEqual(expanded.width, 550)
        XCTAssertEqual(expanded.height, 460)
        XCTAssertEqual(expanded.maxX, rect.maxX)
        XCTAssertEqual(expanded.maxY, rect.maxY)
        let clamped = resize.draggedRect(delta: CGPoint(x: 900, y: 900))
        XCTAssertEqual(clamped.width, 100)
        XCTAssertEqual(clamped.height, 100)
        XCTAssertEqual(clamped.maxX, rect.maxX)
        XCTAssertEqual(clamped.maxY, rect.maxY)
    }

    func testDisabledNativeAdoptionLeavesWeightsAlone() async throws {
        let window = TestWindow.new(id: 1, parent: focus.workspace.rootTilingContainer)
        try await focus.workspace.layoutWorkspace()
        let rect = try XCTUnwrap(window.lastAppliedLayoutPhysicalRect)
        window.setAxFrame(nil, CGSize(width: rect.width - 100, height: rect.height))
        let adopted = try await adoptNativeWindowResize(window)
        XCTAssertFalse(adopted)
        XCTAssertNil(window.scrollingSize)
    }
}
