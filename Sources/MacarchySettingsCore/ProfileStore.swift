import Foundation

/// Named shortcut profiles: whole-keymap snapshots (all `[mode.*.binding]`
/// tables) stored as TOML files under `~/.config/macarchy/profiles/`.
/// Layer-style profiles, macarchy-shaped: a profile IS the full mode set.
public final class ProfileStore: @unchecked Sendable {
    public let directory: URL

    public convenience init() {
        self.init(directory: FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".config/macarchy/profiles"))
    }

    public init(directory: URL) {
        self.directory = directory
    }

    /// Profile names sorted alphabetically.
    public func list() -> [String] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls
            .filter { $0.pathExtension == "toml" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    public func save(_ name: String, toml: String) throws {
        guard !name.isEmpty, name.allSatisfy({ !$0.isWhitespace && $0 != "/" }) else {
            throw ProfileError.invalidName(name)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try toml.write(to: directory.appending(path: "\(name).toml"), atomically: true, encoding: .utf8)
    }

    public func load(_ name: String) throws -> String? {
        guard !name.isEmpty, name.allSatisfy({ !$0.isWhitespace && $0 != "/" }) else { return nil }
        let url = directory.appending(path: "\(name).toml")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try String(contentsOf: url, encoding: .utf8)
    }

    public func delete(_ name: String) throws {
        guard !name.isEmpty, name.allSatisfy({ !$0.isWhitespace && $0 != "/" }) else { return }
        try? FileManager.default.removeItem(at: directory.appending(path: "\(name).toml"))
    }
}

public enum ProfileError: Error, CustomStringConvertible {
    case invalidName(String)

    public var description: String {
        switch self {
            case .invalidName(let name): "Invalid profile name '\(name)'"
        }
    }
}
