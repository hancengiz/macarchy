import Foundation

/// Chord string ("alt-shift-left", the config spelling) → macOS glyph sequence.
enum ChordGlyph {
    static func glyphs(chord: String) -> [String] {
        var ctrl = false, alt = false, shift = false, cmd = false
        var key: String?
        for segment in chord.split(separator: "-").map(String.init) {
            switch segment {
                case "ctrl", "control": ctrl = true
                case "alt", "option": alt = true
                case "shift": shift = true
                case "cmd", "command": cmd = true
                default: key = key.map { "\($0)-\(segment)" } ?? segment
            }
        }
        var modifiers: [String] = []
        if ctrl { modifiers.append("⌃") }
        if alt { modifiers.append("⌥") }
        if shift { modifiers.append("⇧") }
        if cmd { modifiers.append("⌘") }
        return modifiers + [keyGlyph(key ?? chord)]
    }

    static func display(chord: String) -> String {
        glyphs(chord: chord).joined()
    }

    private static func keyGlyph(_ key: String) -> String {
        switch key {
            case "left": "←"
            case "right": "→"
            case "up": "↑"
            case "down": "↓"
            case "minus": "-"
            case "equal": "="
            case "comma": ","
            case "period": "."
            case "slash": "/"
            case "backslash": "\\"
            case "semicolon": ";"
            case "quote": "'"
            case "backtick": "`"
            case "bracketLeft": "["
            case "bracketRight": "]"
            case "enter", "return": "↩"
            case "esc", "escape": "⎋"
            case "tab": "⇥"
            case "backspace": "⌫"
            case "delete": "⌦"
            case "space": "␣"
            case "pageUp": "⇞"
            case "pageDown": "⇟"
            case "home": "↖"
            case "end": "↘"
            default:
                if key.count == 1 { key.uppercased() }
                else if key.first == "f", key.dropFirst().allSatisfy(\.isNumber) { key.uppercased() }
                else { key }
        }
    }
}
