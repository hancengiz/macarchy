import Foundation

@MainActor
func currentShortcutsDescription(_ config: Config) -> String {
    let modes = config.modes.keys.sorted { lhs, rhs in
        if lhs == "main" { return rhs != "main" }
        if rhs == "main" { return false }
        return lhs < rhs
    }
    return modes.map { mode in
        let rows = config.modes[mode]!.bindings.values.sorted { $0.descriptionWithKeyNotation < $1.descriptionWithKeyNotation }
            .map { "\(chordGlyphs($0.descriptionWithKeyNotation))\n    \($0.commands.shellOfCommandsDescription)" }
        return "\(mode.uppercased())\n\n\(rows.joined(separator: "\n\n"))"
    }.joined(separator: "\n\n\n")
}

/// Config chord notation ("alt-shift-left") → compact macOS glyphs ("⌥⇧←").
/// Mirror of MacarchySettingsCore.ChordGlyph (AppBundle must not depend on the settings targets).
private func chordGlyphs(_ notation: String) -> String {
    var ctrl = false, alt = false, shift = false, cmd = false
    var key: String?
    for segment in notation.split(separator: "-") {
        switch segment {
            case "ctrl", "control": ctrl = true
            case "alt", "option": alt = true
            case "shift": shift = true
            case "cmd", "command": cmd = true
            default: key = key.map { "\($0)-\(segment)" } ?? String(segment)
        }
    }
    var out = ""
    if ctrl { out += "⌃" }
    if alt { out += "⌥" }
    if shift { out += "⇧" }
    if cmd { out += "⌘" }
    return out + keyGlyph(String(key ?? notation))
}

private func keyGlyph(_ key: String) -> String {
    switch key {
        case "left": "←"
        case "right": "→"
        case "up": "↑"
        case "down": "↓"
        case "enter", "return": "↩"
        case "esc", "escape": "⎋"
        case "tab": "⇥"
        case "backspace": "⌫"
        case "space": "␣"
        case "pageUp": "⇞"
        case "pageDown": "⇟"
        case "minus": "-"
        case "equal": "="
        case "comma": ","
        case "period": "."
        case "slash": "/"
        case "semicolon": ";"
        case "quote": "'"
        case "backtick": "`"
        default:
            if key.count == 1 { key.uppercased() }
            else if key.first == "f", key.dropFirst().allSatisfy(\.isNumber) { key.uppercased() }
            else { key }
    }
}
