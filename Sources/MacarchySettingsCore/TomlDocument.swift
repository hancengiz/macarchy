import Foundation

/// Surgical, comment-preserving editor for the user's TOML config.
/// Edits single lines in place; never regenerates the file.
public struct TomlDocument {
    private var lines: [String]

    public init(text: String) {
        lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    public var text: String { lines.joined(separator: "\n") }

    // MARK: Sections

    /// Line index of each table header and its normalized name, in order.
    private func tableHeaders() -> [(index: Int, name: String)] {
        lines.enumerated().compactMap { index, line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("["), trimmed.hasSuffix("]"), !trimmed.hasPrefix("[[") else { return nil }
            let name = String(trimmed.dropFirst().dropLast())
            return (index, Self.normalizeKey(name))
        }
    }

    private func sectionBody(mode: String) -> Range<Int>? {
        let target = Self.normalizeKey("mode.\(mode).binding")
        let headers = tableHeaders()
        guard let start = headers.firstIndex(where: { $0.name == target }) else { return nil }
        let from = headers[start].index + 1
        let to = headers.index(after: start) < headers.endIndex ? headers[headers.index(after: start)].index : lines.count
        return from..<to
    }

    // MARK: Top-level and dotted keys

    @discardableResult
    public mutating func setValue(path: [String], valueToml: String) -> Bool {
        let key = Self.normalizeKey(path.joined(separator: "."))
        if let index = lines.firstIndex(where: { Self.keySide(of: $0) == key }) {
            lines[index] = "\(path.joined(separator: ".")) = \(valueToml)"
            return true
        }
        let insertAt = lines.firstIndex(where: Self.isTableHeader) ?? lines.count
        lines.insert("\(path.joined(separator: ".")) = \(valueToml)", at: insertAt)
        return true
    }

    public func getValue(path: [String]) -> String? {
        let key = Self.normalizeKey(path.joined(separator: "."))
        guard let index = lines.firstIndex(where: { Self.keySide(of: $0) == key }) else { return nil }
        return Self.valueSide(of: lines[index])
    }

    // MARK: Mode bindings

    public func bindings(mode: String) -> [(key: String, valueToml: String)] {
        guard let range = sectionBody(mode: mode) else { return [] }
        return lines[range].compactMap { line in
            guard let key = Self.keySideOrNil(of: line) else { return nil }
            return (key, Self.valueSide(of: line) ?? "")
        }
    }

    @discardableResult
    public mutating func setBinding(mode: String, key: String, valueToml: String) -> Bool {
        guard let range = sectionBody(mode: mode) else { return false }
        let normalized = Self.normalizeKey(key)
        for index in range where keySideOrNil(ofLineAt: index) == normalized {
            lines[index] = "\(key) = \(valueToml)"
            return true
        }
        var insertAt = range.lowerBound
        for index in range.reversed() where keySideOrNil(ofLineAt: index) != nil {
            insertAt = index + 1
            break
        }
        lines.insert("\(key) = \(valueToml)", at: insertAt)
        return true
    }

    @discardableResult
    public mutating func removeBinding(mode: String, key: String) -> Bool {
        guard let range = sectionBody(mode: mode) else { return false }
        let normalized = Self.normalizeKey(key)
        guard let index = range.firstIndex(where: { keySideOrNil(ofLineAt: $0) == normalized }) else { return false }
        lines.remove(at: index)
        return true
    }

    // MARK: Line parsing

    private func keySideOrNil(ofLineAt index: Int) -> String? {
        Self.keySideOrNil(of: lines[index])
    }

    private static func keySideOrNil(of line: String) -> String? {
        guard !isTableHeader(line), let eq = line.firstIndex(of: "=") else { return nil }
        return normalizeKey(String(line[..<eq]))
    }

    private static func keySide(of line: String) -> String {
        keySideOrNil(of: line) ?? "\u{0}never-matches"
    }

    private static func valueSide(of line: String) -> String? {
        guard let eq = line.firstIndex(of: "=") else { return nil }
        return String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
    }

    private static func isTableHeader(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("[") && trimmed.hasSuffix("]")
    }

    private static func normalizeKey(_ key: String) -> String {
        key.filter { !$0.isWhitespace }
    }
}
