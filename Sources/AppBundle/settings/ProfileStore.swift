import Foundation

/// Named shortcut profiles: whole-keymap snapshots (all `[mode.*.binding]`
/// tables) stored as TOML files under `~/.config/macarchy/profiles/`.
/// Layer-style profiles, macarchy-shaped: a profile IS the full mode set.
final class ProfileStore: @unchecked Sendable {
    let directory: URL

    public convenience init() {
        self.init(directory: FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".config/macarchy/profiles"))
    }

    init(directory: URL) {
        self.directory = directory
    }

    /// Profile names sorted alphabetically.
    func list() -> [String] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return urls
            .filter { $0.pathExtension == "toml" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    func save(_ name: String, toml: String) throws {
        guard !name.isEmpty, name.allSatisfy({ !$0.isWhitespace && $0 != "/" }) else {
            throw ProfileError.invalidName(name)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try toml.write(to: directory.appending(path: "\(name).toml"), atomically: true, encoding: .utf8)
    }

    func load(_ name: String) throws -> String? {
        guard !name.isEmpty, name.allSatisfy({ !$0.isWhitespace && $0 != "/" }) else { return nil }
        let url = directory.appending(path: "\(name).toml")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try String(contentsOf: url, encoding: .utf8)
    }

    func delete(_ name: String) throws {
        guard !name.isEmpty, name.allSatisfy({ !$0.isWhitespace && $0 != "/" }) else { return }
        try? FileManager.default.removeItem(at: directory.appending(path: "\(name).toml"))
    }
}

enum ProfileError: Error, CustomStringConvertible {
    case invalidName(String)

    var description: String {
        switch self {
            case .invalidName(let name): "Invalid profile name '\(name)'"
        }
    }
}
