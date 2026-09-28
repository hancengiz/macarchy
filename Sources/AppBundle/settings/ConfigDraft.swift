import Foundation

/// TOML value formatting/parsing for draft edits.
enum TomlValue {
    static func format(string: String) -> String {
        if !string.contains("'") { return "'\(string)'" }
        let escaped = string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    static func parseString(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("'"), trimmed.hasSuffix("'"), trimmed.count >= 2 {
            return String(trimmed.dropFirst().dropLast())
        }
        if trimmed.hasPrefix("\""), trimmed.hasSuffix("\""), trimmed.count >= 2 {
            return String(trimmed.dropFirst().dropLast())
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
        }
        return nil
    }

    static func format(int: Int) -> String { String(int) }
    static func format(bool: Bool) -> String { String(bool) }

    static func parseInt(_ raw: String) -> Int? { Int(raw.trimmingCharacters(in: .whitespaces)) }

    static func parseBool(_ raw: String) -> Bool? {
        switch raw.trimmingCharacters(in: .whitespaces) {
            case "true": true
            case "false": false
            default: nil
        }
    }
}

/// One pending change, expressed against the ORIGINAL document.
struct ConfigChange: Equatable, Identifiable {
    let keyPath: String
    let oldValueToml: String?
    let newValueToml: String
    var id: String { keyPath }
}

enum ConfigDraft {
    /// dotted key path -> new TOML value text
    typealias Edits = [String: String]

    static func apply(_ edits: Edits, to original: String) -> String {
        var doc = TomlDocument(text: original)
        for (path, value) in edits.sorted(by: { $0.key < $1.key }) {
            _ = doc.setValue(path: path.split(separator: ".").map(String.init), valueToml: value)
        }
        return doc.text
    }

    static func diff(edits: Edits, original: TomlDocument) -> [ConfigChange] {
        edits.sorted { $0.key < $1.key }.compactMap { path, newValue in
            let old = original.getValue(path: path.split(separator: ".").map(String.init))
            if old == newValue { return nil }
            return ConfigChange(keyPath: path, oldValueToml: old, newValueToml: newValue)
        }
    }
}
