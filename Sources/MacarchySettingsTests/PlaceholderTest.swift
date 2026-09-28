import XCTest
@testable import MacarchySettingsCore

final class PlaceholderTest: XCTestCase {
    func testVersionIsExposed() {
        XCTAssertEqual(MacarchySettingsCoreInfo.version, "0.1.0")
    }
}
