@testable import AppBundle
import XCTest

final class ScrollingViewportTest: XCTestCase {
    func testPartialNeighborKeepsItsWidth() {
        let view = ScrollingViewport(sizes: [600, 600, 600], extent: 1000, gap: 10, focusedIndex: 0, previousOffset: 0)
        XCTAssertEqual(view.sizes, [600, 600, 600])
        XCTAssertEqual(view.starts, [0, 610, 1220])
        XCTAssertEqual(view.visible, [true, true, false])
        XCTAssertEqual(view.offset, 0)
    }

    func testWalkThroughAllColumnsAndBack() {
        let sizes: [CGFloat] = [490, 490, 490, 490, 490]
        let first = ScrollingViewport(sizes: sizes, extent: 1000, gap: 10, focusedIndex: 0, previousOffset: 0)
        let third = ScrollingViewport(sizes: sizes, extent: 1000, gap: 10, focusedIndex: 2, previousOffset: first.offset)
        XCTAssertEqual(third.offset, 490)
        let last = ScrollingViewport(sizes: sizes, extent: 1000, gap: 10, focusedIndex: 4, previousOffset: third.offset)
        XCTAssertEqual(last.offset, 1490)
        XCTAssertEqual(last.visible, [false, false, false, true, true])
        let back = ScrollingViewport(sizes: sizes, extent: 1000, gap: 10, focusedIndex: 0, previousOffset: last.offset)
        XCTAssertEqual(back.offset, 0)
    }

    func testResizeCloseAndMonitorShrinkClampOffset() {
        let view = ScrollingViewport(sizes: [900], extent: 500, gap: 10, focusedIndex: 0, previousOffset: 2000)
        XCTAssertEqual(view.sizes, [500])
        XCTAssertEqual(view.offset, 0)
        XCTAssertEqual(view.visible, [true])
        let empty = ScrollingViewport(sizes: [], extent: 500, gap: 10, focusedIndex: 0, previousOffset: 2000)
        XCTAssertEqual(empty.offset, 0)
        XCTAssertTrue(empty.visible.isEmpty)
    }

    func testFocusWithinViewportDoesNotScroll() {
        let view = ScrollingViewport(sizes: [490, 490, 490], extent: 1000, gap: 10, focusedIndex: 1, previousOffset: 0)
        XCTAssertEqual(view.offset, 0)
    }
}
