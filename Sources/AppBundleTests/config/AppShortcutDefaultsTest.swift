@testable import AppBundle
import HotKey
import XCTest

final class AppShortcutDefaultsTest: XCTestCase {
    private func installedBundleIds(_ ids: String...) -> (String) -> Bool { ids.contains }

    func testExactMatchWithInstalledAppDefault() {
        let reason = appShortcutConflict(
            combo: KeyCombo(key: .z, modifiers: [.option]),
            bindingNotation: "alt-z",
            installed: installedBundleIds("com.microsoft.VSCode"),
        )
        XCTAssertTrue(reason?.contains("VS Code") == true)
        XCTAssertTrue(reason?.contains("Toggle Word Wrap") == true)
        XCTAssertTrue(reason?.contains("alt-ctrl-z") == true)
    }

    func testNearMatchFlagsOneModifierAway() {
        let reason = appShortcutConflict(
            combo: KeyCombo(key: .s, modifiers: [.option]),
            bindingNotation: "alt-s",
            installed: installedBundleIds("com.googlecode.iterm2"),
        )
        XCTAssertTrue(reason?.contains("iTerm2") == true)
        XCTAssertTrue(reason?.contains("Secure Keyboard Entry") == true)
        XCTAssertTrue(reason?.contains("cmd-alt-s") == true)
        XCTAssertTrue(reason?.contains("alt-ctrl-s") == true)
    }

    func testNoConflictWhenAppIsNotInstalled() {
        XCTAssertNil(appShortcutConflict(
            combo: KeyCombo(key: .s, modifiers: [.option]),
            bindingNotation: "alt-s",
            installed: installedBundleIds("com.apple.finder2"),
        ))
    }

    func testDifferentKeyNeverConflicts() {
        XCTAssertNil(appShortcutConflict(
            combo: KeyCombo(key: .k, modifiers: [.option]),
            bindingNotation: "alt-k",
            installed: installedBundleIds("com.googlecode.iterm2", "com.apple.finder"),
        ))
    }

    func testUnrelatedModifierSetDoesNotConflict() {
        // ctrl-s shares no subset relation with cmd-alt-s
        XCTAssertNil(appShortcutConflict(
            combo: KeyCombo(key: .s, modifiers: [.control]),
            bindingNotation: "ctrl-s",
            installed: installedBundleIds("com.googlecode.iterm2"),
        ))
    }

    func testSuggestedAlternativeBinding() {
        XCTAssertEqual(suggestedAlternativeBinding("alt-s"), "alt-ctrl-s")
        XCTAssertEqual(suggestedAlternativeBinding("alt-ctrl-s"), "alt-shift-ctrl-s")
        XCTAssertEqual(suggestedAlternativeBinding("alt-shift-ctrl-s"), "alt-shift-ctrl-s")
        XCTAssertEqual(suggestedAlternativeBinding("s"), "s")
    }
}
