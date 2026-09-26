@testable import AppBundle
import TOMLDecoder
import XCTest

final class ConfigPersistenceTest: XCTestCase {
    func testDottedAndTableKeysUpdateWithoutRedefiningTables() throws {
        let source = """
        # Keep this explanation.
        gaps.inner.horizontal = 10 # spacing
        [gaps.outer]
        left = 12
        [app-window-widths]
        "com.example.Editor" = 49 # logical width
        """
        var updated = try ConfigTextEditor(source).setting(["gaps", "inner", "horizontal"], to: "20")
        updated = try ConfigTextEditor(updated).setting(["gaps", "outer", "right"], to: "15")
        updated = try ConfigTextEditor(updated).setting(["app-window-widths", "com.example.Editor"], to: "67")
        let table = try TOMLTable(source: updated)
        let gaps = try table.table(forKey: "gaps")
        XCTAssertEqual(try gaps.table(forKey: "inner").integer(forKey: "horizontal"), 20)
        XCTAssertEqual(try gaps.table(forKey: "outer").integer(forKey: "left"), 12)
        XCTAssertEqual(try gaps.table(forKey: "outer").integer(forKey: "right"), 15)
        XCTAssertEqual(try table.table(forKey: "app-window-widths").integer(forKey: "com.example.Editor"), 67)
        XCTAssertTrue(updated.contains("# Keep this explanation."))
        XCTAssertTrue(updated.contains("# spacing"))
        XCTAssertTrue(updated.contains("# logical width"))
    }

    func testMultilineStringsAndUnknownContentAreNotMistakenForSettings() throws {
        let source = #"""
        unknown = '''
        enable-mouse-edge-focus = false
        [app-window-widths]
        '''
        "enable-mouse-edge-focus" = false # actual setting
        """#
        let updated = try ConfigTextEditor(source).setting(["enable-mouse-edge-focus"], to: "true")
        let old = try TOMLTable(source: source)
        let table = try TOMLTable(source: updated)
        XCTAssertEqual(try old.string(forKey: "unknown"), try table.string(forKey: "unknown"))
        XCTAssertTrue(try table.bool(forKey: "enable-mouse-edge-focus"))
        XCTAssertTrue(updated.contains("# actual setting"))
    }

    func testInlineAppTableCanUpdateAddAndRemoveWithoutLosingOtherApps() throws {
        let source = #"app-window-widths = { "com.example.One" = 30, "com.example.Two" = 60 } # apps"#
        var updated = try ConfigTextEditor(source).setting(["app-window-widths", "com.example.One"], to: "40")
        updated = try ConfigTextEditor(updated).setting(["app-window-widths", "com.example.Three"], to: "80")
        updated = try ConfigTextEditor(updated).setting(["app-window-widths", "com.example.Two"], to: nil)
        let table = try TOMLTable(source: updated).table(forKey: "app-window-widths")
        XCTAssertEqual(try table.integer(forKey: "com.example.One"), 40)
        XCTAssertEqual(try table.integer(forKey: "com.example.Three"), 80)
        XCTAssertFalse(table.contains(key: "com.example.Two"))
        XCTAssertTrue(updated.contains("# apps"))
    }

    func testDottedAppKeysCanAddDefaultsWithoutAnExplicitTableCollision() throws {
        let source = #"app-window-widths."com.example.One" = 30"# + "\n[mode.main.binding]\nalt-w = 'close'\n"
        let updated = try ConfigTextEditor(source).setting(["app-window-widths", "com.example.Two"], to: "55")
        let table = try TOMLTable(source: updated).table(forKey: "app-window-widths")
        XCTAssertEqual(try table.integer(forKey: "com.example.One"), 30)
        XCTAssertEqual(try table.integer(forKey: "com.example.Two"), 55)
    }

    @MainActor
    func testAppWidthValidationAcceptsBoundariesAndRejectsNonPercentages() {
        let valid = parseConfig("[app-window-widths]\n\"com.example.Small\" = 1\n\"com.example.Large\" = 100")
        XCTAssertTrue(valid.errors.isEmpty)
        XCTAssertEqual(valid.config.appWindowWidths, ["com.example.Small": 1, "com.example.Large": 100])
        for value in ["0", "101", "49.5", "'49'"] {
            XCTAssertFalse(parseConfig("[app-window-widths]\n\"com.example.App\" = \(value)").errors.isEmpty)
        }
    }
}
