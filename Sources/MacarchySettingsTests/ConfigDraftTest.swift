import XCTest
@testable import MacarchySettingsCore

final class TomlValueTest: XCTestCase {
    func testStringRoundTrip() {
        XCTAssertEqual(TomlValue.format(string: "layout tiles"), "'layout tiles'")
        XCTAssertEqual(TomlValue.parseString(TomlValue.format(string: "it's")), "it's")
        XCTAssertEqual(TomlValue.parseString("'plain'"), "plain")
    }

    func testScalars() {
        XCTAssertEqual(TomlValue.format(int: 24), "24")
        XCTAssertEqual(TomlValue.format(bool: false), "false")
        XCTAssertEqual(TomlValue.parseInt("24"), 24)
        XCTAssertEqual(TomlValue.parseBool("true"), true)
        XCTAssertNil(TomlValue.parseInt("true"))
    }
}

final class ConfigDraftTest: XCTestCase {
    let original = "start-at-login = true\ngaps.inner.horizontal = 10\n\n[mode.main.binding]\nalt-q = 'close'\n"

    func testApplyProducesEditedText() {
        let text = ConfigDraft.apply(
            [
                "gaps.inner.horizontal": "24",
                "start-at-login": "false",
            ],
            to: original,
        )
        XCTAssertTrue(text.contains("gaps.inner.horizontal = 24"))
        XCTAssertTrue(text.contains("start-at-login = false"))
        XCTAssertTrue(text.contains("alt-q = 'close'"))
    }

    func testDiffReportsOldAndNew() {
        let changes = ConfigDraft.diff(
            edits: ["gaps.inner.horizontal": "24"],
            original: TomlDocument(text: original),
        )
        XCTAssertEqual(changes.count, 1)
        XCTAssertEqual(changes[0].keyPath, "gaps.inner.horizontal")
        XCTAssertEqual(changes[0].oldValueToml, "10")
        XCTAssertEqual(changes[0].newValueToml, "24")
    }

    func testDiffSkipsNoOpEdits() {
        XCTAssertTrue(ConfigDraft.diff(edits: ["start-at-login": "true"], original: TomlDocument(text: original)).isEmpty)
    }
}
