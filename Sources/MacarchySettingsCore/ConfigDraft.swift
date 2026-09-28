import Foundation

/// TOML value formatting/parsing for draft edits.
public enum TomlValue {
    public static func format(string: String) -> String {
        if !string.contains("'") { return "'\(string)'" }
        let escaped = string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    public static func parseString(_ raw: String) -> String? {
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

    public static func format(int: Int) -> String { String(int) }
    public static func format(bool: Bool) -> String { String(bool) }

    public static func parseInt(_ raw: String) -> Int? { Int(raw.trimmingCharacters(in: .whitespaces)) }

    public static func parseBool(_ raw: String) -> Bool? {
        switch raw.trimmingCharacters(in: .whitespaces) {
            case "true": true
            case "false": false
            default: nil
        }
    }
}

/// One pending change, expressed against the ORIGINAL document.
public struct ConfigChange: Equatable, Identifiable {
    public let keyPath: String
    public let oldValueToml: String?
    public let newValueToml: String
    public var id: String { keyPath }
}

public enum ConfigDraft {
    /// dotted key path -> new TOML value text
    public typealias Edits = [String: String]

    public static func apply(_ edits: Edits, to original: String) -> String {
        var doc = TomlDocument(text: original)
        for (path, value) in edits.sorted(by: { $0.key < $1.key }) {
            _ = doc.setValue(path: path.split(separator: ".").map(String.init), valueToml: value)
        }
        return doc.text
    }

    public static func diff(edits: Edits, original: TomlDocument) -> [ConfigChange] {
        edits.sorted { $0.key < $1.key }.compactMap { path, newValue in
            let old = original.getValue(path: path.split(separator: ".").map(String.init))
            if old == newValue { return nil }
            return ConfigChange(keyPath: path, oldValueToml: old, newValueToml: newValue)
        }
    }
}
