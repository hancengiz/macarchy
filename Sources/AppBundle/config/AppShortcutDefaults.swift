import AppKit
import Common
import HotKey

/// Default shortcuts of popular macOS applications. macOS provides no API to
/// read another application's shortcut table, so the conflict detector matches
/// macarchy bindings against this curated list of well-known defaults. Entries
/// are advisory: they never pause a binding, they inform and suggest a remap.
/// Extend freely — keep only documented factory defaults.
struct AppShortcutDefault {
    let appBundleId: String
    let appName: String
    let combo: KeyCombo
    let notation: String
    let description: String
}

var popularAppShortcutDefaults: [AppShortcutDefault] { [
    .init(appBundleId: "com.googlecode.iterm2", appName: "iTerm2",
          combo: KeyCombo(key: .s, modifiers: [.option, .command]), notation: "cmd-alt-s",
          description: "Secure Keyboard Entry"),
    .init(appBundleId: "com.apple.finder", appName: "Finder",
          combo: KeyCombo(key: .s, modifiers: [.option, .command]), notation: "cmd-alt-s",
          description: "Hide Sidebar"),
    .init(appBundleId: "com.google.Chrome", appName: "Google Chrome",
          combo: KeyCombo(key: .i, modifiers: [.option, .command]), notation: "cmd-alt-i",
          description: "Developer Tools"),
    .init(appBundleId: "com.google.Chrome", appName: "Google Chrome",
          combo: KeyCombo(key: .j, modifiers: [.option, .command]), notation: "cmd-alt-j",
          description: "JavaScript Console"),
    .init(appBundleId: "com.microsoft.VSCode", appName: "VS Code",
          combo: KeyCombo(key: .z, modifiers: [.option]), notation: "alt-z",
          description: "Toggle Word Wrap"),
] }

/// Advisory check: does `combo` collide with a factory default of one of the
/// known installed apps? `installed` decides whether a bundle id is present.
/// Two rules:
/// - exact combo equality, e.g. binding alt-z vs VS Code's word wrap;
/// - same key where one modifier set is a strict subset of the other, e.g.
///   binding alt-s vs iTerm2's cmd-alt-s: the chords are one missed Command
///   apart, so the wrong action fires routinely while typing in that app.
func appShortcutConflict(combo: KeyCombo, bindingNotation: String, installed: (String) -> Bool) -> String? {
    let candidates = popularAppShortcutDefaults.filter { installed($0.appBundleId) }
    let suggestion = suggestedAlternativeBinding(bindingNotation)
    if let exact = candidates.first(where: { $0.combo == combo }) {
        return "Conflicts with \(exact.appName)'s default '\(exact.description)' (\(exact.notation)). Suggested binding: \(suggestion)"
    }
    if let near = candidates.first(where: { candidate in
        guard candidate.combo.key == combo.key, candidate.combo.modifiers != combo.modifiers else { return false }
        return candidate.combo.modifiers.subtracting(combo.modifiers).isEmpty
            || combo.modifiers.subtracting(candidate.combo.modifiers).isEmpty
    }) {
        return "One modifier away from \(near.appName)'s '\(near.description)' (\(near.notation)) — the wrong action fires easily while typing there. Suggested binding: \(suggestion)"
    }
    return nil
}

/// Deterministic remap suggestion for a colliding binding notation: add ctrl,
/// then shift. App defaults and macOS system shortcuts rarely use ctrl, which
/// makes the first hop a safe escape in practice.
func suggestedAlternativeBinding(_ notation: String) -> String {
    var parts = notation.split(separator: "-").map(String.init)
    guard parts.count > 1 else { return notation }
    if !parts.contains("ctrl") {
        parts.insert("ctrl", at: 1)
    } else if !parts.contains("shift") {
        parts.insert("shift", at: 1)
    } else {
        return notation
    }
    return parts.joined(separator: "-")
}
