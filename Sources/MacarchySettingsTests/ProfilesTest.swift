import XCTest
@testable import MacarchySettingsCore

final class TomlDocumentModeReplaceTest: XCTestCase {
    let config = """
        start-at-login = true

        [mode.main.binding]
        # binding comment
        alt-h = 'focus left'
        alt-l = 'layout tiles'

        [mode.resize.binding]
        left = 'resize width -25'
        """

    func testReplaceModeRowsKeepsHeaderAndOtherSections() {
        var doc = TomlDocument(text: config)
        doc.replaceModeBindings(mode: "main", rows: [("alt-h", "'focus right'"), ("alt-j", "'close'")])
        let text = doc.text
        XCTAssertTrue(text.contains("[mode.main.binding]"))
        XCTAssertTrue(text.contains("alt-h = 'focus right'"))
        XCTAssertTrue(text.contains("alt-j = 'close'"))
        XCTAssertFalse(text.contains("'layout tiles'"))
        XCTAssertTrue(text.contains("[mode.resize.binding]"))
        XCTAssertTrue(text.contains("left = 'resize width -25'"))
        XCTAssertTrue(text.contains("start-at-login = true"))
    }

    func testReplaceWithEmptyRemovesAllRows() {
        var doc = TomlDocument(text: config)
        doc.replaceModeBindings(mode: "main", rows: [])
        XCTAssertFalse(doc.text.contains("alt-h"))
        XCTAssertTrue(doc.text.contains("[mode.main.binding]"))
    }

    func testReplaceMissingModeIsNoOp() {
        var doc = TomlDocument(text: config)
        doc.replaceModeBindings(mode: "nope", rows: [("a", "'x'")])
        XCTAssertEqual(doc.text, config)
    }
}

final class ProfileStoreTest: XCTestCase {
    func testSaveListLoadDeleteRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "profiles-test-\(UUID().uuidString)")
        let store = ProfileStore(directory: dir)
        XCTAssertTrue(store.list().isEmpty)
        try store.save("leader", toml: "[mode.main.binding]\nf18 = 'mode macarchy'\n")
        XCTAssertEqual(store.list(), ["leader"])
        XCTAssertEqual(
            try store.load("leader"),
            "[mode.main.binding]\nf18 = 'mode macarchy'\n"
        )
        try store.save("default", toml: "[mode.main.binding]\nalt-h = 'focus left'\n")
        XCTAssertEqual(store.list(), ["default", "leader"])
        try store.delete("leader")
        XCTAssertEqual(store.list(), ["default"])
        XCTAssertNil(try? store.load("leader"))
        try FileManager.default.removeItem(at: dir)
    }

    func testSaveRejectsPathTraversalNames() {
        let dir = FileManager.default.temporaryDirectory.appending(path: "profiles-test-\(UUID().uuidString)")
        let store = ProfileStore(directory: dir)
        XCTAssertThrowsError(try store.save("../evil", toml: "x = 1"))
        try? FileManager.default.removeItem(at: dir)
    }
}
