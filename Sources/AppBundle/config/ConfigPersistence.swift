import AppKit
import Common
import TOMLDecoder

struct SettingsError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Edits only a value's source range: comments, ordering and unrelated keys stay intact.
/// A TOML parse both before and after editing is the final authority on validity.
struct ConfigTextEditor {
    private struct Entry {
        let path: [String]
        let keyStart: String.Index
        let value: Range<String.Index>
        let inline: Bool
    }
    private struct Section {
        let path: [String]
        let insertion: String.Index
    }
    private let source: String
    private var entries: [Entry] = []
    private var sections: [Section] = []
    private var firstHeader: String.Index

    init(_ source: String) throws {
        _ = try TOMLTable(source: source)
        self.source = source
        firstHeader = source.endIndex
        var cursor = source.startIndex
        var section: [String] = []
        while cursor < source.endIndex {
            skipSpaceAndComments(&cursor)
            guard cursor < source.endIndex else { break }
            if source[cursor] == "[" {
                firstHeader = min(firstHeader, cursor)
                let start = cursor
                let end = scanValue(from: cursor, inline: false)
                let header = String(source[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
                // Array-of-table entries are never settings targets.
                let array = header.hasPrefix("[[")
                section = try Self.keyPath(String(header.dropFirst(array ? 2 : 1).dropLast(array ? 2 : 1)))
                if array { section.insert("\u{0}", at: 0) }
                cursor = end
                skipToNextLine(&cursor)
                sections.append(Section(path: section, insertion: cursor))
            } else {
                try scanEntry(&cursor, prefix: section, inline: false)
                skipToNextLine(&cursor)
            }
        }
    }

    func setting(_ path: [String], to value: String?) throws -> String {
        var result = source
        if let entry = entries.first(where: { $0.path == path }) {
            if let value {
                result.replaceSubrange(entry.value, with: value)
            } else if entry.inline {
                var end = entry.value.upperBound
                while end < source.endIndex && source[end].isWhitespace { end = source.index(after: end) }
                var start = entry.keyStart
                if end < source.endIndex && source[end] == "," {
                    end = source.index(after: end)
                } else {
                    while start > source.startIndex && source[source.index(before: start)].isWhitespace { start = source.index(before: start) }
                    if start > source.startIndex && source[source.index(before: start)] == "," { start = source.index(before: start) }
                    end = entry.value.upperBound
                }
                result.removeSubrange(start..<end)
            } else {
                // Leave an inline comment in place when deleting its assignment.
                result.removeSubrange(entry.keyStart..<entry.value.upperBound)
            }
        } else if let value {
            if let ancestor = entries.filter({ path.starts(with: $0.path) && source[$0.value].first == "{" }).max(by: { $0.path.count < $1.path.count }) {
                let end = source.index(before: ancestor.value.upperBound)
                let body = source[source.index(after: ancestor.value.lowerBound)..<end].trimmingCharacters(in: .whitespacesAndNewlines)
                let key = path.dropFirst(ancestor.path.count).map(Self.quoteKey).joined(separator: ".")
                result.insert(contentsOf: "\(body.isEmpty ? "" : ", ")\(key) = \(value)", at: end)
            } else if path.count == 2 && path[0] == "app-window-widths"
                && !entries.contains(where: { $0.path.first == path[0] })
                && !sections.contains(where: { $0.path.first == path[0] })
            {
                let newline = source.contains("\r\n") ? "\r\n" : "\n"
                result += "\(newline)[app-window-widths]\(newline)\(Self.quoteString(path[1])) = \(value)\(newline)"
            } else {
                let section = sections.filter { path.starts(with: $0.path) && path.count > $0.path.count }.max { $0.path.count < $1.path.count }
                let key = path.dropFirst(section?.path.count ?? 0).map(Self.quoteKey).joined(separator: ".")
                let insertion = section?.insertion ?? firstHeader
                let newline = source.contains("\r\n") ? "\r\n" : "\n"
                let prefix = insertion > source.startIndex && source[source.index(before: insertion)] != "\n" ? newline : ""
                result.insert(contentsOf: "\(prefix)\(key) = \(value)\(newline)", at: insertion)
            }
        }
        _ = try TOMLTable(source: result)
        return result
    }

    static func quoteKey(_ key: String) -> String {
        if !key.isEmpty && key.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }) { return key }
        return quoteString(key)
    }

    static func quoteString(_ value: String) -> String {
        // JSON basic strings are valid TOML strings, including escaping bundle IDs.
        let data = try! JSONSerialization.data(withJSONObject: [value], options: [.fragmentsAllowed, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self).dropFirst().dropLast().description
    }

    private static func keyPath(_ key: String) throws -> [String] {
        var table: [String: Any] = try Dictionary(TOMLTable(source: "\(key) = 0"))
        var path: [String] = []
        while let name = table.keys.first {
            path.append(name)
            if let child = table[name] as? [String: Any] { table = child } else { break }
        }
        return path
    }

    private mutating func scanEntry(_ cursor: inout String.Index, prefix: [String], inline: Bool) throws {
        let keyStart = cursor
        var quote: Character?
        var escaped = false
        while cursor < source.endIndex {
            let char = source[cursor]
            if let current = quote {
                if escaped { escaped = false }
                else if char == "\\" && current == "\"" { escaped = true }
                else if char == current { quote = nil }
            } else if char == "\"" || char == "'" { quote = char }
            else if char == "=" { break }
            cursor = source.index(after: cursor)
        }
        guard cursor < source.endIndex else { throw SettingsError("Cannot locate a configuration value.") }
        let path = try prefix + Self.keyPath(String(source[keyStart..<cursor]))
        cursor = source.index(after: cursor)
        while cursor < source.endIndex && source[cursor].isWhitespace { cursor = source.index(after: cursor) }
        let start = cursor
        let end = scanValue(from: start, inline: inline)
        entries.append(Entry(path: path, keyStart: keyStart, value: start..<end, inline: inline))
        if source[start] == "{" {
            var child = source.index(after: start)
            while child < end {
                skipSpaceAndComments(&child)
                if source[child] == "}" { break }
                if source[child] == "," { child = source.index(after: child); continue }
                try scanEntry(&child, prefix: path, inline: true)
            }
        }
        cursor = end
    }

    private func scanValue(from start: String.Index, inline: Bool) -> String.Index {
        var cursor = start
        var quote: Character?
        var triple = false
        var escaped = false
        var depth = 0
        var last = start
        while cursor < source.endIndex {
            let char = source[cursor]
            let next = source.index(after: cursor)
            if let current = quote {
                if escaped { escaped = false }
                else if char == "\\" && current == "\"" { escaped = true }
                else if char == current {
                    if triple {
                        if source[cursor...].hasPrefix(String(repeating: String(current), count: 3)) {
                            cursor = source.index(cursor, offsetBy: 3)
                            // TOML permits one or two literal quotes immediately
                            // before a multiline string's closing delimiter.
                            for _ in 0..<2 where cursor < source.endIndex && source[cursor] == current {
                                cursor = source.index(after: cursor)
                            }
                            quote = nil
                            last = cursor
                            continue
                        }
                    } else { quote = nil }
                }
            } else if char == "\"" || char == "'" {
                quote = char
                triple = source[cursor...].hasPrefix(String(repeating: String(char), count: 3))
                if triple { cursor = source.index(cursor, offsetBy: 3); last = cursor; continue }
            } else if char == "#" {
                if depth == 0 { return last }
                skipToNextLine(&cursor)
                continue
            } else if depth == 0 && (char == "\n" || char == "\r" || (inline && (char == "," || char == "}"))) { return last }
            else if char == "[" || char == "{" { depth += 1 }
            else if char == "]" || char == "}" { depth -= 1 }
            cursor = next
            if quote != nil || !char.isWhitespace { last = cursor }
        }
        return last
    }

    private func skipSpaceAndComments(_ cursor: inout String.Index) {
        while cursor < source.endIndex {
            if source[cursor].isWhitespace { cursor = source.index(after: cursor) }
            else if source[cursor] == "#" { skipToNextLine(&cursor) }
            else { return }
        }
    }

    private func skipToNextLine(_ cursor: inout String.Index) {
        while cursor < source.endIndex {
            let char = source[cursor]
            cursor = source.index(after: cursor)
            if char == "\n" { return }
        }
    }
}

@MainActor
enum ConfigPersistence {
    static func activeURL() throws -> URL {
        if configUrl.standardizedFileURL != defaultConfigUrl.standardizedFileURL { return configUrl.resolvingSymlinksInPath() }
        if let explicit = serverArgs.configLocation { return URL(filePath: explicit).resolvingSymlinksInPath() }
        switch findCustomConfigUrl() {
            case .file(let url): return url.resolvingSymlinksInPath()
            case .noCustomConfigExists: return FileManager.default.homeDirectoryForCurrentUser.appending(path: configDotfileName)
            case .ambiguousConfigError(let urls): throw SettingsError("Several configuration files exist. Select one with --config-path:\n" + urls.map(\.path).joined(separator: "\n"))
        }
    }

    static func ensureFile() throws -> URL {
        let url = try activeURL()
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: defaultConfigUrl, to: url)
        }
        return url
    }

    static func set(_ path: [String], value: String?) throws -> URL {
        let url = try activeURL()
        let exists = FileManager.default.fileExists(atPath: url.path)
        let original = try String(contentsOf: exists ? url : defaultConfigUrl, encoding: .utf8)
        let updated = try ConfigTextEditor(original).setting(path, to: value)
        let parsed = parseConfig(updated)
        guard parsed.errors.isEmpty else {
            throw SettingsError("Configuration was not changed. Fix these errors first:\n" + parsed.errors.map { $0.description(.error) }.joined(separator: "\n"))
        }
        if exists {
            guard try String(contentsOf: url, encoding: .utf8) == original else { throw SettingsError("Configuration changed in another editor. Reload Settings and try again.") }
        } else {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        try updated.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func reload(_ url: URL) async throws -> String {
        let parsed = readConfig(forceConfigUrl: url).parseConfigResult
        guard parsed.errors.isEmpty else {
            throw SettingsError("Configuration was not reloaded:\n" + parsed.errors.map { $0.description(.error) }.joined(separator: "\n"))
        }
        let result = await reloadConfig_nonCancellable(args: ReloadConfigCmdArgs(rawArgs: []).copy(\.noGui, true), forceConfigUrl: url)
        guard result.isOk else { throw SettingsError("Configuration could not be reloaded:\n" + [result.stdout, result.stderr].filter { !$0.isEmpty }.joined(separator: "\n")) }
        return [result.stderr, startAtLoginError].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    static func open() async throws {
        let url = try ensureFile()
        _ = try await NSWorkspace.shared.open([url], withApplicationAt: getTextEditorToOpenConfig(for: url), configuration: NSWorkspace.OpenConfiguration())
    }
}
