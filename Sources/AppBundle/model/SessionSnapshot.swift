import Foundation
import Darwin

/// Disk format intentionally contains no AX objects and never causes apps to launch.
struct SessionSnapshot: Codable, Sendable {
    static let currentVersion = 1
    var version = currentVersion
    var windows: [SessionWindow]
    var workspaces: [SessionWorkspace]
    var focusedWindow: UInt32?
    var focusedWorkspace: String

    func validate() throws {
        guard version == Self.currentVersion else { throw SessionStoreError.unsupportedVersion(version) }
        guard Set(windows.map(\.id)).count == windows.count,
              Set(workspaces.map(\.name)).count == workspaces.count else {
            throw SessionStoreError.invalidSnapshot
        }
        let ids = Set(windows.map(\.id))
        var used = Set<UInt32>()
        func validateNode(_ node: SessionNode, depth: Int) throws {
            guard depth < 128, node.weight.isFinite, node.weight > 0,
                  node.scrollingSize.map({ $0.isFinite && $0 > 0 }) ?? true,
                  node.scrollingOffset.isFinite else { throw SessionStoreError.invalidSnapshot }
            if let id = node.window {
                guard ids.contains(id), used.insert(id).inserted, node.children.isEmpty else {
                    throw SessionStoreError.invalidSnapshot
                }
            } else {
                guard ["tiles", "accordion", "scrolling"].contains(node.layout),
                      ["h", "v"].contains(node.orientation) else { throw SessionStoreError.invalidSnapshot }
                for child in node.children { try validateNode(child, depth: depth + 1) }
            }
        }
        for workspace in workspaces {
            guard !workspace.name.isEmpty, workspace.root.window == nil else { throw SessionStoreError.invalidSnapshot }
            try validateNode(workspace.root, depth: 0)
            for id in workspace.floating + workspace.nativeFullscreen + workspace.hidden {
                guard ids.contains(id), used.insert(id).inserted else { throw SessionStoreError.invalidSnapshot }
            }
        }
        for window in windows {
            guard window.frame?.isValid ?? true,
                  window.scrollingSize.map({ $0.isFinite && $0 > 0 }) ?? true,
                  window.floatingSize.map({ $0.width.isFinite && $0.height.isFinite && $0.width > 0 && $0.height > 0 }) ?? true else {
                throw SessionStoreError.invalidSnapshot
            }
        }
    }
}

struct SessionWindow: Codable, Sendable {
    var id: UInt32
    var pid: Int32
    var launchDate: Date?
    var bundleID: String?
    var title: String
    var frame: SessionFrame?
    var floatingSize: SessionSize?
    var scrollingSize: Double? = nil
    var fullscreen: Bool
    var noOuterGaps: Bool
    var nativeFullscreen: Bool
    var previouslyFloating: Bool
}

struct SessionSize: Codable, Sendable {
    var width: Double
    var height: Double
}

struct SessionWorkspace: Codable, Sendable {
    var name: String
    var displayUUID: String?
    var visible: Bool
    var root: SessionNode
    var floating: [UInt32]
    var nativeFullscreen: [UInt32]
    var hidden: [UInt32]
}

struct SessionNode: Codable, Sendable {
    var window: UInt32?
    var weight: Double
    var scrollingSize: Double?
    var layout: String
    var orientation: String
    var scrollingOffset: Double
    var children: [SessionNode]
    var mostRecentWindow: UInt32? = nil
}

struct SessionFrame: Codable, Sendable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    var isValid: Bool { x.isFinite && y.isFinite && width.isFinite && height.isFinite && width > 0 && height > 0 }

    func fitted(to bounds: SessionFrame) -> SessionFrame {
        let width = min(width, bounds.width)
        let height = min(height, bounds.height)
        return SessionFrame(
            x: min(max(x, bounds.x), bounds.x + bounds.width - width),
            y: min(max(y, bounds.y), bounds.y + bounds.height - height),
            width: width,
            height: height,
        )
    }
}

/// Exact IDs are meaningful only within the same process incarnation. The title
/// fallback is deliberately one-to-one on BOTH sides, and only across relaunch.
func matchSessionWindows(saved: [SessionWindow], live: [SessionWindow]) -> [UInt32: UInt32] {
    let current = Dictionary(uniqueKeysWithValues: live.map { ($0.id, $0) })
    var matches: [UInt32: UInt32] = [:]
    var used = Set<UInt32>()
    for old in saved {
        if let window = current[old.id], let launch = old.launchDate,
           window.pid == old.pid, window.launchDate == launch,
           window.bundleID == old.bundleID {
            matches[old.id] = window.id
            used.insert(window.id)
        }
    }
    struct TitleKey: Hashable {
        let bundle: String
        let title: String
    }
    func key(_ window: SessionWindow) -> TitleKey? {
        guard let bundle = window.bundleID, !bundle.isEmpty, !window.title.isEmpty else { return nil }
        return TitleKey(bundle: bundle, title: window.title)
    }
    let oldGroups = Dictionary(grouping: saved.compactMap { window in key(window).map { ($0, window) } }, by: { $0.0 })
    let newGroups = Dictionary(grouping: live.compactMap { window in key(window).map { ($0, window) } }, by: { $0.0 })
    for (key, oldGroup) in oldGroups where oldGroup.count == 1 {
        guard let newGroup = newGroups[key], newGroup.count == 1 else { continue }
        let old = oldGroup[0].1
        let new = newGroup[0].1
        guard matches[old.id] == nil, !used.contains(new.id),
              let oldLaunch = old.launchDate, let newLaunch = new.launchDate,
              old.pid != new.pid || oldLaunch != newLaunch else { continue }
        matches[old.id] = new.id
        used.insert(new.id)
    }
    return matches
}

enum SessionStoreError: LocalizedError {
    case unsupportedVersion(Int)
    case invalidSnapshot
    case notReady

    var errorDescription: String? {
        switch self {
            case .unsupportedVersion(let version): "Session format \(version) is not supported by this version of Macarchy."
            case .invalidSnapshot: "The saved session contains invalid or duplicate window data."
            case .notReady: "Macarchy is still registering windows. Try restarting again after startup completes."
        }
    }
}

extension SessionSnapshot {
    /// Atomic replacement plus a durability barrier before restart is permitted.
    /// An invalid capture leaves the previously saved session intact.
    func writeAtomically(to url: URL) throws {
        try validate()
        let data = try JSONEncoder().encode(self)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let file = try FileHandle(forWritingTo: url)
        defer { try? file.close() }
        try file.synchronize()
        let directory = unsafe open(url.deletingLastPathComponent().path, O_RDONLY)
        guard directory >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { _ = close(directory) }
        guard fsync(directory) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
    }
}
