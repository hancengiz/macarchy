import XCTest
@testable import MacarchySettingsCore

final class ShortcutConflictAnalysisTest: XCTestCase {
    let config = """
        start-at-login = true

        [mode.main.binding]
        alt-l = 'layout --root scrolling h_tiles'
        alt-left = 'focus --boundaries workspace left'
        cmd-space = 'mode macarchy-menu'
        cmd-tab = 'workspace-back-and-forth'

        [mode.resize.binding]
        left = 'resize width -25'
        """

    func testAnalysisFindsDeadReservedAndTextEditing() {
        let system = SystemShortcuts(lookup: SystemShortcutsTest.staticLookup)
        let analysis = ShortcutConflictAnalysis(configText: config, system: system)
        let rows = analysis.conflictRows()
        XCTAssertEqual(rows.map(\.chord), ["alt-l", "alt-left", "cmd-space", "cmd-tab"]) // sorted
        XCTAssertEqual(rows[0].severity, .textEditing)
        XCTAssertEqual(rows[1].severity, .textEditing)
        XCTAssertEqual(rows[2].severity, .dead(name: "Spotlight"))
        XCTAssertEqual(rows[3].severity, .reserved(name: "App Switcher"))
        XCTAssertEqual(rows[0].mode, "main")
    }

    func testPlainChordsProduceNoRows() {
        let system = SystemShortcuts(lookup: SystemShortcutsTest.staticLookup)
        let analysis = ShortcutConflictAnalysis(
            configText: "[mode.main.binding]\nf18 = 'mode macarchy'\n",
            system: system,
        )
        XCTAssertTrue(analysis.conflictRows().isEmpty)
    }

    func testCatalogListsAllModesWithCommands() {
        let system = SystemShortcuts(lookup: SystemShortcutsTest.staticLookup)
        let analysis = ShortcutConflictAnalysis(configText: config, system: system)
        let catalog = analysis.catalog()
        XCTAssertEqual(catalog.map(\.mode), ["main", "resize"])
        XCTAssertEqual(catalog[0].bindings.first?.chord, "alt-l")
        XCTAssertEqual(catalog[0].bindings.first?.command, "'layout --root scrolling h_tiles'")
        XCTAssertEqual(catalog[1].bindings.first?.chord, "left")
    }
}
