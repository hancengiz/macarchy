import XCTest
@testable import MacarchySettingsCore

final class ConfigFileLocationTest: XCTestCase {
    func testPrefersHomeDotfile() {
        let result = ConfigFileLocation.resolve(
            home: "/Users/u",
            xdgConfigHome: nil,
            fileExists: { $0 == "/Users/u/.macarchy.toml" }
        )
        XCTAssertEqual(result, .file(URL(filePath: "/Users/u/.macarchy.toml")))
    }

    func testFallsBackToXdg() {
        let result = ConfigFileLocation.resolve(
            home: "/Users/u",
            xdgConfigHome: "/xdg",
            fileExists: { $0 == "/xdg/macarchy/macarchy.toml" }
        )
        XCTAssertEqual(result, .file(URL(filePath: "/xdg/macarchy/macarchy.toml")))
    }

    func testAmbiguousIsError() {
        if case .ambiguousConfigError = ConfigFileLocation.resolve(
            home: "/Users/u", xdgConfigHome: nil, fileExists: { _ in true }
        ) {} else { XCTFail("expected ambiguous") }
    }

    func testNoneExists() {
        XCTAssertEqual(
            ConfigFileLocation.resolve(home: "/Users/u", xdgConfigHome: nil, fileExists: { _ in false }).urlOrNil,
            nil,
        )
    }
}
