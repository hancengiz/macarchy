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
            .map { "\($0.descriptionWithKeyNotation)\n    \($0.commands.shellOfCommandsDescription)" }
        return "\(mode.uppercased())\n\n\(rows.joined(separator: "\n\n"))"
    }.joined(separator: "\n\n\n")
}
