import XCTest
@testable import MacarchySettingsCore

final class ChordGlyphTest: XCTestCase {
    func testModifierOrderIsCtrlAltShiftCmd() {
        XCTAssertEqual(ChordGlyph.glyphs(chord: "cmd-ctrl-alt-shift-a"), ["⌃", "⌥", "⇧", "⌘", "A"])
    }

    func testArrowsAndSpecialKeys() {
        XCTAssertEqual(ChordGlyph.glyphs(chord: "alt-left"), ["⌥", "←"])
        XCTAssertEqual(ChordGlyph.glyphs(chord: "alt-right"), ["⌥", "→"])
        XCTAssertEqual(ChordGlyph.glyphs(chord: "alt-up"), ["⌥", "↑"])
        XCTAssertEqual(ChordGlyph.glyphs(chord: "alt-down"), ["⌥", "↓"])
        XCTAssertEqual(ChordGlyph.glyphs(chord: "alt-shift-enter"), ["⌥", "⇧", "↩"])
        XCTAssertEqual(ChordGlyph.glyphs(chord: "alt-esc"), ["⌥", "⎋"])
        XCTAssertEqual(ChordGlyph.glyphs(chord: "alt-tab"), ["⌥", "⇥"])
        XCTAssertEqual(ChordGlyph.glyphs(chord: "alt-backtick"), ["⌥", "`"])
        XCTAssertEqual(ChordGlyph.glyphs(chord: "alt-shift-minus"), ["⌥", "⇧", "-"])
        XCTAssertEqual(ChordGlyph.glyphs(chord: "alt-pageUp"), ["⌥", "⇞"])
        XCTAssertEqual(ChordGlyph.glyphs(chord: "alt-pageDown"), ["⌥", "⇟"])
        XCTAssertEqual(ChordGlyph.glyphs(chord: "f18"), ["F18"])
    }

    func testSingleLetterUppercased() {
        XCTAssertEqual(ChordGlyph.glyphs(chord: "alt-l"), ["⌥", "L"])
        XCTAssertEqual(ChordGlyph.glyphs(chord: "alt-shift-esc"), ["⌥", "⇧", "⎋"])
    }

    func testDisplayString() {
        XCTAssertEqual(ChordGlyph.display(chord: "alt-shift-left"), "⌥⇧←")
    }

    func testUnknownFallsBackToRawSegment() {
        XCTAssertEqual(ChordGlyph.glyphs(chord: "alt-hyper-xyz"), ["⌥", "hyper-xyz"])
    }
}
