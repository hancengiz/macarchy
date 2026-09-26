@testable import AppBundle
import Foundation
import CoreGraphics
import XCTest

final class HiddenWindowPlacementTest: XCTestCase {
    func testWholeWindowAvoidsRightAndLowerDisplays() {
        let displays = [
            CGRect(x: 0, y: 0, width: 1920, height: 804),
            CGRect(x: 0, y: 804, width: 2056, height: 1329),
            CGRect(x: 1920, y: -276, width: 1920, height: 1080),
        ]
        for size in [CGSize(width: 931, height: 773), CGSize(width: 3200, height: 1500)] {
            let origin = hiddenWindowOrigin(size: size, preferred: displays[0], displays: displays)
            let parked = CGRect(origin: origin, size: size)
            let visibleArea = displays.reduce(CGFloat(0)) { area, display in
                let overlap = parked.intersection(display)
                return area + (overlap.isNull ? 0 : overlap.width * overlap.height)
            }
            XCTAssertLessThanOrEqual(visibleArea, 1)
        }
    }

    func testNegativeOriginAndDisconnectedNeighbor() {
        let display = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        let size = CGSize(width: 1200, height: 700)
        let origin = hiddenWindowOrigin(size: size, preferred: display, displays: [display])
        let overlap = CGRect(origin: origin, size: size).intersection(display)
        XCTAssertEqual(overlap.width * overlap.height, 1)
    }
}
