import XCTest
@testable import MacarchySettingsCore

final class SystemShortcutsTest: XCTestCase {
    func testChordMatchesKnownSystemShortcut() {
        let map = SystemShortcuts(lookup: SystemShortcutsTest.staticLookup)
        XCTAssertEqual(map.classify(chord: "cmd-space"), .dead(name: "Spotlight"))
        XCTAssertEqual(map.classify(chord: "ctrl-up"), .dead(name: "Mission Control"))
        XCTAssertEqual(map.classify(chord: "ctrl-down"), .dead(name: "App Windows"))
        XCTAssertEqual(map.classify(chord: "ctrl-space"), .dormant(name: "Input Source"))
        XCTAssertEqual(map.classify(chord: "cmd-tab"), .reserved(name: "App Switcher"))
        XCTAssertEqual(map.classify(chord: "cmd-shift-4"), .reserved(name: "Screenshot selection"))
        XCTAssertEqual(map.classify(chord: "alt-j"), nil)
    }

    /// Fixture: Spotlight + Mission Control + App Windows enabled; Input Source disabled.
    static func staticLookup(_ id: Int) -> (enabled: Bool, keycode: Int, modifiers: Int)? {
        switch id {
            case 64: (true, 49, 0x0100)
            case 32: (true, 126, 0x1000)
            case 33: (true, 125, 0x1000)
            case 60: (false, 49, 0x1000)
            default: nil
        }
    }

    func testLiveLookupDoesNotCrash() {
        _ = SystemShortcuts.live().classify(chord: "cmd-space") // smoke: any answer
    }
}
