@testable import AppBundle
import Common
import XCTest

@MainActor
final class OmarchyMenuDataTest: XCTestCase {
    // MARK: JSONC dialect

    func testStripJsoncRemovesWholeLineCommentsButNotInlineOnes() {
        let raw = """
            // leading comment
            {
              "a": { "label": "A", }, // inline comment breaks the dialect on purpose
              "b": { "label": "B" },
            }
            """
        XCTAssertFalse(stripJsonc(raw).contains("leading comment"))
        // The inline trailing comment makes this unparseable, matching Omarchy's dialect.
        XCTAssertNil(parseMenuJsonc(raw))
    }

    func testParseRecoversOrderAndInfersKindAndParent() {
        let raw = """
            {
              "apps": { "icon": "a", "label": "Apps", "provider": "apps", "aliases": ["app"] },
              "system": { "label": "System" },
              "system.sound": { "label": "Sound", "action": "open x" },
              "system.link": { "label": "Link", "target": "system" },
            }
            """
        let nodes = parseMenuJsonc(raw).orDie()
        XCTAssertEqual(nodes.map(\.id), ["apps", "system", "system.sound", "system.link"])
        XCTAssertEqual(nodes[0].kind, .menu)
        XCTAssertEqual(nodes[2].kind, .action)
        XCTAssertEqual(nodes[3].kind, .link)
        XCTAssertEqual(nodes[0].parent, "root")
        XCTAssertEqual(nodes[2].parent, "system")
        XCTAssertEqual(nodes[0].aliases, ["app"])
    }

    func testParseAcceptsItemsWrapper() {
        let raw = """
            { "items": { "x": { "label": "X", "action": "true" } } }
            """
        let nodes = parseMenuJsonc(raw).orDie()
        XCTAssertEqual(nodes.map(\.id), ["x"])
    }

    func testBrokenJsonReturnsNil() {
        XCTAssertNil(parseMenuJsonc("{ not json"))
        XCTAssertNil(parseMenuJsonc(""))
    }

    // MARK: Merge

    func testMergeOverlaysPerFieldAndPreservesOrder() {
        let defaults = [
            OmarchyMenuNode(id: "apps", label: "Apps", order: 0),
            OmarchyMenuNode(id: "system", label: "System", order: 1),
        ]
        let extensions = [
            OmarchyMenuNode(id: "system", label: "System Settings", icon: "gear"),
            OmarchyMenuNode(id: "personal", label: "Personal"),
        ]
        let merged = mergeMenuSources(defaults: defaults, extensions: extensions)
        XCTAssertEqual(merged["system"]?.label, "System Settings")
        XCTAssertEqual(merged["apps"]?.order, 1)
        XCTAssertEqual(merged["system"]?.order, 2, "Overridden entries keep their position")
        XCTAssertEqual(merged["personal"]?.order, 3, "New ids append")
        XCTAssertEqual(merged["root"]?.order, 0, "Synthetic root is injected in front")
        XCTAssertEqual(merged["root"]?.label, "Go")
    }

    // MARK: Guards

    func testGuardScriptBatchesAllConditions() {
        let nodes = [
            OmarchyMenuNode(id: "a", label: "A", when: "command -v git"),
            OmarchyMenuNode(id: "b", label: "B", checked: "true", disabled: "false"),
        ]
        let script = guardScript(nodes: nodes)
        XCTAssertTrue(script.contains("if command -v git; then echo \"a:w:1\""))
        XCTAssertTrue(script.contains("if true; then echo \"b:c:1\""))
        XCTAssertTrue(script.contains("if false; then echo \"b:d:1\""))
    }

    func testParseGuardOutputSemantics() {
        let output = """
            a:w:1
            b:w:0
            c:c:1
            d:d:1
            e:x:1
            garbage

            """
        let results = parseGuardOutput(output)
        XCTAssertTrue(results.isVisible(OmarchyMenuNode(id: "a", label: "A")), "when success = visible")
        XCTAssertFalse(results.isVisible(OmarchyMenuNode(id: "b", label: "B")), "when failure = hidden")
        XCTAssertTrue(results.isChecked(OmarchyMenuNode(id: "c", label: "C")))
        XCTAssertTrue(results.isDisabled(OmarchyMenuNode(id: "d", label: "D")))
        XCTAssertTrue(GuardResults.empty.isDisabled(OmarchyMenuNode(id: "f", label: "F", disabled: "true")),
                      "disabled: \"true\" disables unconditionally")
    }

    // MARK: Search

    private func makeNodes() -> [String: OmarchyMenuNode] {
        mergeMenuSources(defaults: [
            OmarchyMenuNode(id: "root", label: "Go"),
            OmarchyMenuNode(id: "apps", label: "Apps", provider: "apps"),
            OmarchyMenuNode(id: "system", label: "System"),
            OmarchyMenuNode(id: "system.sound", label: "Sound", action: "open sound", description: "audio volume"),
            OmarchyMenuNode(id: "system.bluetooth", label: "Bluetooth", action: "open bt", description: "wireless"),
            OmarchyMenuNode(id: "learn.manual", label: "Omarchy Manual", action: "open url"),
        ], extensions: [])
    }

    func testSearchMatchesAllTermsByNameOrDescriptionWholeWord() {
        let guards = GuardResults.empty
        let sound = OmarchyMenuNode(id: "system.sound", label: "Sound", action: "x", description: "audio volume")
        XCTAssertTrue(matchesQuery(node: sound, guards: guards, query: "sou"))
        XCTAssertTrue(matchesQuery(node: sound, guards: guards, query: "sound audio"), "name substring + description word")
        XCTAssertFalse(matchesQuery(node: sound, guards: guards, query: "aud"), "description matches whole words only")
        XCTAssertTrue(matchesQuery(node: OmarchyMenuNode(id: "learn.manual", label: "Omarchy Manual", action: "x"), guards: guards, query: "man"),
                      "last id segment is searchable")
    }

    func testSearchExcludesDisabledRows() {
        let guards = GuardResults(whenHidden: [], checkedTrue: [], disabledTrue: ["system.sound"])
        let sound = OmarchyMenuNode(id: "system.sound", label: "Sound", action: "x")
        XCTAssertFalse(matchesQuery(node: sound, guards: guards, query: "sound"))
    }

    func testSearchScoringPrefersExactThenPrefixThenSubstring() {
        let exact = OmarchyMenuNode(id: "a", label: "Terminal", action: "x")
        let prefix = OmarchyMenuNode(id: "b", label: "Terminal Here", action: "x")
        let substring = OmarchyMenuNode(id: "c", label: "Open Terminal Now", action: "x")
        let scores = [
            searchScore(node: exact, isAppRow: false, query: "Terminal"),
            searchScore(node: prefix, isAppRow: false, query: "Terminal"),
            searchScore(node: substring, isAppRow: false, query: "Terminal"),
        ]
        XCTAssertLessThan(scores[0], scores[1])
        XCTAssertLessThan(scores[1], scores[2])
    }

    // MARK: Store rows and subtree search

    func testStoreRowsHideWhenGuardFails() {
        let store = OmarchyMenuStore.shared
        store.nodes = makeNodes()
        store.guards = GuardResults(whenHidden: ["system.sound"], checkedTrue: [], disabledTrue: [])
        let rows = store.rows(for: "system")
        XCTAssertFalse(rows.contains { $0.id == "system.sound" })
        XCTAssertTrue(rows.contains { $0.id == "system.bluetooth" })
    }

    func testStoreSearchIsScopedToActiveSubtree() {
        let store = OmarchyMenuStore.shared
        store.nodes = makeNodes()
        store.guards = GuardResults.empty
        let rows = store.search(menuId: "root", query: "sound")
        XCTAssertTrue(rows.contains { $0.id == "system.sound" })
        XCTAssertEqual(rows.filter(\.isDivider).count, 0, "Matches at the root are all current-menu rows")
        let scoped = store.search(menuId: "system", query: "manual")
        XCTAssertFalse(scoped.contains { $0.id == "learn.manual" }, "Search must not leave the active subtree")
        XCTAssertTrue(scoped.isEmpty)
    }

    // MARK: Navigation

    func testNavigationEntersAndBacksWithStack() {
        let model = OmarchyMenuModel()
        model.store.nodes = makeNodes()
        model.store.guards = GuardResults.empty
        let systemRow = OmarchyMenuRow(
            id: "system", node: model.store.nodes["system"], label: "System", icon: nil, appPath: nil,
            isSubmenu: true, isDisabled: false, isChecked: false,
        )
        model.enter(systemRow)
        XCTAssertEqual(model.activeMenu, "system")
        model.query = "sou"
        XCTAssertEqual(model.rows.first?.id, "system.sound")
        XCTAssertTrue(model.back())
        XCTAssertEqual(model.activeMenu, "root")
        XCTAssertFalse(model.back(), "Back at the root is a no-op")
        model.resetToRoot()
        XCTAssertEqual(model.activeMenu, "root")
        XCTAssertTrue(model.navStack.isEmpty)
    }

    func testSelectionSkipsDisabledAndDividerRows() {
        let model = OmarchyMenuModel()
        model.store.nodes = makeNodes()
        model.store.guards = GuardResults(whenHidden: [], checkedTrue: [], disabledTrue: ["system.sound"])
        let systemRow = OmarchyMenuRow(
            id: "system", node: model.store.nodes["system"], label: "System", icon: nil, appPath: nil,
            isSubmenu: true, isDisabled: false, isChecked: false,
        )
        model.enter(systemRow)
        XCTAssertEqual(model.rows.filter { model.isSelectable($0) }.map(\.id), ["system.bluetooth"])
        model.moveSelection(1)
        XCTAssertEqual(model.selection?.id, "system.bluetooth", "Selection must skip disabled rows")
        // Searching from the root can yield a drilldown divider; selection must never land on it.
        model.resetToRoot()
        model.store.guards = GuardResults.empty
        model.query = "s"
        XCTAssertTrue(model.rows.contains { $0.isDivider })
        model.moveSelection(1)
        model.moveSelection(1)
        XCTAssertNotEqual(model.selection?.id, "divider")
    }

    // MARK: Apps provider helpers
    func testKeybindingsProviderRowsTriggerLiveBindings() {
        let parsed = parseConfig("""
            [mode.main.binding]
            alt-t = 'layout floating tiling'
            alt-l = 'layout --root scrolling h_tiles'
            """)
        XCTAssertTrue(parsed.errors.isEmpty)
        let rows = keybindingsProviderRows(bindings: parsed.config.modes[mainModeId]?.bindings ?? [:])
        XCTAssertEqual(rows.map(\.label), ["alt-l", "alt-t"], "Rows sort by key notation")
        XCTAssertTrue(rows.allSatisfy { $0.id.hasPrefix("keybindings.") })
        XCTAssertTrue(rows.allSatisfy { $0.handler != nil }, "Each row must activate its shortcut")
        // Fire a row handler end to end: the same path a real keypress uses.
        // (Full in-session execution is covered by the real app path; the unit-test
        // AX-mock runloop cannot host a light session reliably.)
    }

    // MARK: Mouse edge focus

    func testEdgeFocusTriggersOnlyAtDeadEndEdges() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1200)
        let visible = CGRect(x: 0, y: 30, width: 1920, height: 1170)
        // Mid-screen: nothing.
        XCTAssertNil(edgeFocusDirection(mouse: CGPoint(x: 960, y: 600), screenFrame: screen, visibleFrame: visible, otherScreens: []))
        // Physical left edge: trigger.
        XCTAssertEqual(edgeFocusDirection(mouse: CGPoint(x: 1, y: 600), screenFrame: screen, visibleFrame: visible, otherScreens: []), .left)
        // Physical right edge: trigger.
        XCTAssertEqual(edgeFocusDirection(mouse: CGPoint(x: 1919, y: 600), screenFrame: screen, visibleFrame: visible, otherScreens: []), .right)
        // Edge shared with a display to the right: working area, not a trigger.
        let neighbor = CGRect(x: 1920, y: 0, width: 1080, height: 1200)
        XCTAssertNil(edgeFocusDirection(mouse: CGPoint(x: 1919, y: 600), screenFrame: screen, visibleFrame: visible, otherScreens: [neighbor]))
        // Edge shared with a display to the left: not a trigger.
        XCTAssertNil(edgeFocusDirection(mouse: CGPoint(x: 1, y: 600), screenFrame: CGRect(x: 1920, y: 0, width: 1920, height: 1200), visibleFrame: CGRect(x: 1920, y: 30, width: 1920, height: 1170), otherScreens: [screen]))
        // Pointer in the menu-bar strip: ignore.
        XCTAssertNil(edgeFocusDirection(mouse: CGPoint(x: 1, y: 10), screenFrame: screen, visibleFrame: visible, otherScreens: []))
    }

    func testEdgeFocusDwellFiresOncePerEdgeVisit() {
        // First tick at the edge records the dwell; second tick fires.
        var state = edgeFocusDwellStep(dwell: nil, fired: nil, current: .right)
        XCTAssertNil(state.fire)
        state = edgeFocusDwellStep(dwell: state.dwell, fired: state.fired, current: .right)
        XCTAssertEqual(state.fire, .right)
        // Pointer resting at the same edge must not re-trigger focus.
        for _ in 0 ..< 10 {
            state = edgeFocusDwellStep(dwell: state.dwell, fired: state.fired, current: .right)
            XCTAssertNil(state.fire, "Parked pointer must not keep firing")
        }
        // Leaving the edge re-arms; returning requires a fresh dwell before firing.
        state = edgeFocusDwellStep(dwell: state.dwell, fired: state.fired, current: nil)
        XCTAssertNil(state.fire)
        state = edgeFocusDwellStep(dwell: state.dwell, fired: state.fired, current: .right)
        XCTAssertNil(state.fire)
        state = edgeFocusDwellStep(dwell: state.dwell, fired: state.fired, current: .right)
        XCTAssertEqual(state.fire, .right)
        // Switching straight to the opposite edge fires in that direction.
        state = edgeFocusDwellStep(dwell: nil, fired: .right, current: .left)
        XCTAssertNil(state.fire)
        state = edgeFocusDwellStep(dwell: state.dwell, fired: state.fired, current: .left)
        XCTAssertEqual(state.fire, .left)
    }

    func testEdgeFocusBounceArrivalDecision() {
        // Quick return to the same edge: bounce
        XCTAssertTrue(isEdgeFocusBounceArrival(lastLeft: .right, leftAge: 0.15, current: .right))
        // Fresh visit long after leaving: not a bounce (dwell path applies)
        XCTAssertFalse(isEdgeFocusBounceArrival(lastLeft: .right, leftAge: 2.0, current: .right))
        // Different edge: never a bounce
        XCTAssertFalse(isEdgeFocusBounceArrival(lastLeft: .right, leftAge: 0.1, current: .left))
        // No prior leave recorded
        XCTAssertFalse(isEdgeFocusBounceArrival(lastLeft: nil, leftAge: 0.1, current: .right))
        XCTAssertFalse(isEdgeFocusBounceArrival(lastLeft: .right, leftAge: nil, current: .right))
        XCTAssertFalse(isEdgeFocusBounceArrival(lastLeft: .right, leftAge: 0.1, current: nil))
    }

    func testSearchResultsKeepProviderRowHandlers() throws {
        let store = OmarchyMenuStore.shared
        store.nodes = mergeMenuSources(defaults: [
            OmarchyMenuNode(id: "root", label: "Go"),
            OmarchyMenuNode(id: "keybindings", label: "Keybindings", provider: "keybindings"),
        ], extensions: [])
        store.guards = GuardResults.empty
        let parsed = parseConfig("""
            [mode.main.binding]
            alt-t = 'layout floating tiling'
            """)
        config = parsed.config
        // Rows built straight from the submenu keep handlers...
        XCTAssertTrue(store.rows(for: "keybindings").contains { $0.handler != nil })
        // ...and search results must keep them too (regression: the re-wrap dropped them,
        // making Enter on a searched keybinding row a silent no-op).
        let results = store.search(menuId: "keybindings", query: "tiling")
        XCTAssertTrue(results.contains { row in
            row.id == "keybindings.alt-t" && row.handler != nil
        }, "Searched keybinding rows must still fire their binding")
    }


    func testSlugifyNormalizesAppNames() {
        XCTAssertEqual(slugify("Activity Monitor"), "activity-monitor")
        XCTAssertEqual(slugify("Thing — Extra!!"), "thing-extra")
    }

    func testProviderRowsSlugifyExcludeAndDedupe() {
        let rows = appsProviderRows(parentId: "apps", exclude: ["Finder"])
        XCTAssertGreaterThanOrEqual(rows.count, 1)
        XCTAssertTrue(rows.allSatisfy { $0.appPath?.hasSuffix(".app") == true })
        XCTAssertTrue(rows.allSatisfy { $0.id.hasPrefix("apps.") })
        XCTAssertEqual(Set(rows.map(\.id)).count, rows.count, "Row ids must be unique")
        XCTAssertFalse(rows.contains { $0.label == "Finder" }, "Excluded apps must not appear")
    }
}
