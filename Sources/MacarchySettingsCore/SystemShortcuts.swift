import CoreFoundation
import Foundation

public enum SystemShortcutClass: Equatable {
    /// macOS owns the chord right now (symbolic hotkey enabled): the binding never fires.
    case dead(name: String)
    /// The chord matches a system shortcut that is currently disabled: works today, breaks if the user enables it.
    case dormant(name: String)
    /// Hard-wired macOS chord, no user switch.
    case reserved(name: String)
}

public struct SystemShortcuts {
    struct Entry {
        let name: String
        let symbolicHotKeyId: Int?
        let chordParts: Set<String>
    }

    let entries: [Entry]
    private let lookup: (Int) -> (enabled: Bool, keycode: Int, modifiers: Int)?

    /// Static table + live symbolic-hotkey state.
    public static func live() -> SystemShortcuts {
        SystemShortcuts(lookup: SystemShortcuts.readSymbolicHotkey)
    }

    public init(lookup: @escaping (Int) -> (enabled: Bool, keycode: Int, modifiers: Int)?) {
        self.entries = [
            Entry(name: "Spotlight", symbolicHotKeyId: 64, chordParts: ["cmd", "space"]),
            Entry(name: "Spotlight search field", symbolicHotKeyId: 65, chordParts: ["cmd", "alt", "space"]),
            Entry(name: "Input Source", symbolicHotKeyId: 60, chordParts: ["ctrl", "space"]),
            Entry(name: "Mission Control", symbolicHotKeyId: 32, chordParts: ["ctrl", "up"]),
            Entry(name: "App Windows", symbolicHotKeyId: 33, chordParts: ["ctrl", "down"]),
            Entry(name: "App Switcher", symbolicHotKeyId: nil, chordParts: ["cmd", "tab"]),
            Entry(name: "Screenshot", symbolicHotKeyId: nil, chordParts: ["cmd", "shift", "3"]),
            Entry(name: "Screenshot selection", symbolicHotKeyId: nil, chordParts: ["cmd", "shift", "4"]),
            Entry(name: "Screenshot tool", symbolicHotKeyId: nil, chordParts: ["cmd", "shift", "5"]),
        ]
        self.lookup = lookup
    }

    public func classify(chord: String) -> SystemShortcutClass? {
        let parts = Set(Self.normalize(chord))
        for entry in entries where entry.chordParts == parts {
            if let id = entry.symbolicHotKeyId, let state = lookup(id) {
                return state.enabled ? .dead(name: entry.name) : .dormant(name: entry.name)
            }
            return .reserved(name: entry.name)
        }
        return nil
    }

    static func normalize(_ chord: String) -> [String] {
        chord.split(separator: "-").map { segment in
            switch segment {
                case "control": "ctrl"
                case "option": "alt"
                case "command": "cmd"
                default: String(segment)
            }
        }
    }

    /// Reads `com.apple.symbolichotkeys` → id → (enabled, keycode, carbon modifiers).
    static func readSymbolicHotkey(_ id: Int) -> (enabled: Bool, keycode: Int, modifiers: Int)? {
        guard
            let values = CFPreferencesCopyValue(
                "AppleSymbolicHotKeys" as CFString,
                "com.apple.symbolichotkeys" as CFString,
                kCFPreferencesCurrentUser,
                kCFPreferencesAnyHost
            ) as? [String: Any],
            let entry = values[String(id)] as? [String: Any],
            let enabled = entry["enabled"] as? Bool,
            let value = entry["value"] as? [String: Any],
            let parameters = value["parameters"] as? [Any], parameters.count >= 3,
            let keycode = parameters[1] as? Int,
            let modifiers = parameters[2] as? Int
        else { return nil }
        return (enabled, keycode, modifiers)
    }
}
