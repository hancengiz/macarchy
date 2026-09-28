import XCTest
@testable import MacarchySettingsCore

final class TomlDocumentTest: XCTestCase {
    let sample = """
        # top comment
        config-version = 2
        start-at-login = true
        gaps.inner.horizontal = 10
        gaps.outer.left = 10

        [mode.main.binding]
        # focus walks the row
        alt-left = 'focus --boundaries workspace left'
        alt-j = 'layout horizontal vertical'
        alt-enter = ['mode main', 'exec-and-forget x']

        [mode.resize.binding]
        left = 'resize width -25'
        """

    func testRoundTripPreservesTextExactly() {
        XCTAssertEqual(TomlDocument(text: sample).text, sample)
    }

    func testSetExistingDottedKeyPreservesComments() {
        var doc = TomlDocument(text: sample)
        XCTAssertTrue(doc.setValue(path: ["gaps", "inner", "horizontal"], valueToml: "24"))
        XCTAssertEqual(doc.text, sample.replacingOccurrences(
            of: "gaps.inner.horizontal = 10",
            with: "gaps.inner.horizontal = 24",
        ))
    }

    func testSetMissingTopLevelKeyInsertsBeforeFirstTable() {
        var doc = TomlDocument(text: sample)
        XCTAssertTrue(doc.setValue(path: ["accordion-padding"], valueToml: "20"))
        let lines = doc.text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let inserted = lines.firstIndex(of: "accordion-padding = 20")!
        let firstTable = lines.firstIndex(of: "[mode.main.binding]")!
        XCTAssertLessThan(inserted, firstTable)
    }

    func testSetMissingDottedKeyInsertsBeforeFirstTable() {
        var doc = TomlDocument(text: sample)
        XCTAssertTrue(doc.setValue(path: ["gaps", "inner", "vertical"], valueToml: "12"))
        XCTAssertTrue(doc.text.contains("gaps.inner.vertical = 12"))
    }

    func testSetValueWritesIntoExistingTableSection() {
        let tableForm = "start-at-login = true\n\n[bar]\nenabled = false\nheight = 28\n"
        var doc = TomlDocument(text: tableForm)
        XCTAssertTrue(doc.setValue(path: ["bar", "enabled"], valueToml: "true"))
        XCTAssertEqual(doc.text, "start-at-login = true\n\n[bar]\nenabled = true\nheight = 28\n")

        // Missing key inside an existing table appends there, not at top level.
        let withTable = "[borders]\nenabled = true\n"
        var doc2 = TomlDocument(text: withTable)
        XCTAssertTrue(doc2.setValue(path: ["borders", "width"], valueToml: "6"))
        XCTAssertEqual(doc2.text, "[borders]\nenabled = true\nwidth = 6\n")
    }

    func testSetInDocumentWithoutTablesAppends() {
        var doc = TomlDocument(text: "a = 1")
        XCTAssertTrue(doc.setValue(path: ["b"], valueToml: "2"))
        XCTAssertEqual(doc.text, "a = 1\nb = 2")
    }

    func testGetValueReadsRawTomlValue() {
        let doc = TomlDocument(text: sample)
        XCTAssertEqual(doc.getValue(path: ["start-at-login"]), "true")
        XCTAssertEqual(doc.getValue(path: ["gaps", "outer", "left"]), "10")
        XCTAssertNil(doc.getValue(path: ["missing"]))
    }

    func testBindingsListIsOrderedAndComplete() {
        let doc = TomlDocument(text: sample)
        let rows = doc.bindings(mode: "main")
        XCTAssertEqual(rows.map(\.key), ["alt-left", "alt-j", "alt-enter"])
        XCTAssertEqual(rows[2].valueToml, "['mode main', 'exec-and-forget x']")
    }

    func testSetBindingReplacesRowInPlace() {
        var doc = TomlDocument(text: sample)
        XCTAssertTrue(doc.setBinding(mode: "main", key: "alt-j", valueToml: "'layout accordion tiles'"))
        XCTAssertTrue(doc.text.contains("alt-j = 'layout accordion tiles'"))
        XCTAssertFalse(doc.text.contains("'layout horizontal vertical'"))
    }

    func testSetMissingBindingAppendsInsideSection() {
        var doc = TomlDocument(text: sample)
        XCTAssertTrue(doc.setBinding(mode: "main", key: "alt-x", valueToml: "'close'"))
        let lines = doc.text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let inserted = lines.firstIndex(of: "alt-x = 'close'")!
        let resizeHeader = lines.firstIndex(of: "[mode.resize.binding]")!
        XCTAssertLessThan(inserted, resizeHeader)
    }

    func testSetBindingInMissingModeSectionFails() {
        var doc = TomlDocument(text: sample)
        XCTAssertFalse(doc.setBinding(mode: "nonexistent", key: "a", valueToml: "'x'"))
    }

    func testRemoveBindingDeletesOnlyThatRow() {
        var doc = TomlDocument(text: sample)
        XCTAssertTrue(doc.removeBinding(mode: "main", key: "alt-left"))
        XCTAssertFalse(doc.text.contains("alt-left ="))
        XCTAssertTrue(doc.text.contains("# focus walks the row"))
        XCTAssertTrue(doc.text.contains("alt-j ="))
    }
}
