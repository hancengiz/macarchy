import Foundation

public enum ConfigFileLocation: Equatable {
    case file(URL)
    case ambiguousConfigError(_ candidates: [URL])
    case noCustomConfigExists

    public var urlOrNil: URL? {
        switch self {
            case .file(let url): url
            case .ambiguousConfigError, .noCustomConfigExists: nil
        }
    }

    public static func resolve(
        home: String,
        xdgConfigHome: String?,
        fileExists: (String) -> Bool,
    ) -> ConfigFileLocation {
        let xdgRoot = xdgConfigHome.map { URL(filePath: $0) }
            ?? URL(filePath: home).appending(path: ".config/")
        let candidates = [
            URL(filePath: home).appending(path: ".macarchy.toml"),
            xdgRoot.appending(path: "macarchy").appending(path: "macarchy.toml"),
        ]
        let existing = candidates.filter { fileExists($0.path(percentEncoded: false)) }
        switch existing.count {
            case 0: return .noCustomConfigExists
            case 1: return .file(existing[0])
            default: return .ambiguousConfigError(existing)
        }
    }

    /// Real resolution for the app process. Mirrors `findCustomConfigUrl` in AppBundle.
    public static func live() -> ConfigFileLocation {
        resolve(
            home: FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false),
            xdgConfigHome: ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"],
            fileExists: { FileManager.default.fileExists(atPath: $0) },
        )
    }
}
