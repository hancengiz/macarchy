import AppKit
import Common

@MainActor private var workspaceNameToWorkspace: [String: Workspace] = [:]

@MainActor private var screenPointToPrevVisibleWorkspace: [CGPoint: String] = [:]
@MainActor private var screenPointToVisibleWorkspace: [CGPoint: Workspace] = [:]
@MainActor private var visibleWorkspaceToScreenPoint: [Workspace: CGPoint] = [:]
@MainActor private var displayUUIDToScreenPoint: [String: CGPoint] = [:]

// The returned workspace must be invisible and it must belong to the requested monitor
@MainActor func getStubWorkspace(for monitor: MonitorInfo) -> Workspace {
    getStubWorkspace(forPoint: monitor.rect.topLeftCorner)
}

@MainActor
private func getStubWorkspace(forPoint point: CGPoint) -> Workspace {
    if let prev = screenPointToPrevVisibleWorkspace[point].map({ Workspace.get(byName: $0) }),
       !prev.isVisible && prev.workspaceMonitor.rect.topLeftCorner == point && prev.forceAssignedMonitor == nil
    {
        return prev
    }
    if let candidate = Workspace.all
        .first(where: { !$0.isVisible && $0.workspaceMonitor.rect.topLeftCorner == point })
    {
        return candidate
    }
    return (1 ... Int.max).lazy
        .map { Workspace.get(byName: String($0)) }
        .first { $0.isEffectivelyEmpty && !$0.isVisible && !config.persistentWorkspaces.contains($0.name) && $0.forceAssignedMonitor == nil }
        .orDie("Can't create empty workspace")
}

final class Workspace: TreeNode, NonLeafTreeNodeObject, Hashable, Comparable {
    let name: String
    nonisolated private let nameLogicalSegments: StringLogicalSegments
    /// `assignedMonitorPoint` must be interpreted only when the workspace is invisible
    fileprivate var assignedMonitorPoint: CGPoint? = nil
    fileprivate var assignedDisplayUUID: String? = nil

    @MainActor
    private init(_ name: String) {
        self.name = name
        self.nameLogicalSegments = name.toLogicalSegments()
        super.init(parent: NilTreeNode.instance, adaptiveWeight: 0, index: 0)
    }

    @MainActor static var all: [Workspace] {
        workspaceNameToWorkspace.values.sorted()
    }

    @MainActor static func get(byName name: String) -> Workspace {
        if let existing = workspaceNameToWorkspace[name] {
            return existing
        } else {
            let workspace = Workspace(name)
            workspaceNameToWorkspace[name] = workspace
            return workspace
        }
    }

    @MainActor
    func restoreMonitorAssignment(displayUUID: String?) {
        assignedDisplayUUID = displayUUID
        assignedMonitorPoint = monitorInfos.first(where: { $0.sessionDisplayUUID == displayUUID && displayUUID != nil })?.rect.topLeftCorner
            ?? monitorInfos.first?.rect.topLeftCorner
    }

    @MainActor
    var rememberedDisplayUUID: String? {
        return assignedDisplayUUID ?? workspaceMonitor.sessionDisplayUUID
    }

    nonisolated static func < (lhs: Workspace, rhs: Workspace) -> Bool {
        lhs.nameLogicalSegments < rhs.nameLogicalSegments
    }

    override func getWeight(_ targetOrientation: Orientation) -> CGFloat {
        workspaceMonitor.visibleRectPaddedByOuterGaps.getDimension(targetOrientation)
    }

    override func setWeight(_ targetOrientation: Orientation, _ newValue: CGFloat) {
        die("It's not possible to change weight of Workspace")
    }

    @MainActor
    var description: String {
        let description = [
            ("name", name),
            ("isVisible", String(isVisible)),
            ("isEffectivelyEmpty", String(isEffectivelyEmpty)),
            ("doKeepAlive", String(config.persistentWorkspaces.contains(name))),
        ].map { "\($0.0): \(String(describing: $0.1).singleQuoted)" }.joined(separator: ", ")
        return "Workspace(\(description))"
    }

    @MainActor
    static func garbageCollectUnusedWorkspaces() {
        for name in config.persistentWorkspaces {
            _ = get(byName: name) // Make sure that all persistent workspaces are "cached"
        }
        workspaceNameToWorkspace = workspaceNameToWorkspace.filter { (_, workspace: Workspace) in
            config.persistentWorkspaces.contains(workspace.name) ||
                !workspace.isEffectivelyEmpty ||
                workspace.isVisible ||
                workspace.name == focus.workspace.name
        }
    }

    nonisolated static func == (lhs: Workspace, rhs: Workspace) -> Bool {
        check((lhs === rhs) == (lhs.name == rhs.name), "lhs: \(lhs) rhs: \(rhs)")
        return lhs === rhs
    }

    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(name) }
}

extension Workspace {
    @MainActor
    var isVisible: Bool { visibleWorkspaceToScreenPoint.keys.contains(self) }
    @MainActor
    var workspaceMonitor: MonitorInfo {
        forceAssignedMonitor
            ?? visibleWorkspaceToScreenPoint[self]?.monitorApproximation
            ?? assignedDisplayUUID.flatMap { uuid in monitorInfos.first(where: { $0.sessionDisplayUUID == uuid }) }
            ?? (assignedDisplayUUID == nil ? assignedMonitorPoint?.monitorApproximation : monitorInfos.first)
            ?? mainMonitorInfo
    }
}

extension MonitorInfo {
    @MainActor
    var activeWorkspace: Workspace {
        if let existing = screenPointToVisibleWorkspace[rect.topLeftCorner] {
            return existing
        }
        // What if monitor configuration changed? (frame.origin is changed)
        rearrangeWorkspacesOnMonitors()
        // Normally, recursion should happen only once more because we must take the value from the cache
        // (Unless, monitor configuration data race happens)
        return self.activeWorkspace
    }

    @MainActor
    func setActiveWorkspace(_ workspace: Workspace) -> Bool {
        rect.topLeftCorner.setActiveWorkspace(workspace)
    }
}

@MainActor
func gcMonitors() {
    let monitors = monitorInfos
    let displayMoved = monitors.contains { monitor in
        guard let uuid = monitor.sessionDisplayUUID else { return false }
        return displayUUIDToScreenPoint[uuid] != monitor.rect.topLeftCorner
    }
    if screenPointToVisibleWorkspace.count != monitors.count || displayMoved {
        rearrangeWorkspacesOnMonitors()
    }
}

extension CGPoint {
    @MainActor
    fileprivate func setActiveWorkspace(_ workspace: Workspace) -> Bool {
        if !isValidAssignment(workspace: workspace, screen: self) {
            return false
        }
        if let prevMonitorPoint = visibleWorkspaceToScreenPoint[workspace] {
            visibleWorkspaceToScreenPoint.removeValue(forKey: workspace)
            screenPointToPrevVisibleWorkspace[prevMonitorPoint] =
                screenPointToVisibleWorkspace.removeValue(forKey: prevMonitorPoint)?.name
        }
        if let prevWorkspace = screenPointToVisibleWorkspace[self] {
            screenPointToPrevVisibleWorkspace[self] =
                screenPointToVisibleWorkspace.removeValue(forKey: self)?.name
            visibleWorkspaceToScreenPoint.removeValue(forKey: prevWorkspace)
        }
        visibleWorkspaceToScreenPoint[workspace] = self
        screenPointToVisibleWorkspace[self] = workspace
        if workspace.assignedMonitorPoint != self || workspace.assignedDisplayUUID == nil {
            workspace.assignedDisplayUUID = monitorInfos.first(where: { $0.rect.topLeftCorner == self })?.sessionDisplayUUID
        }
        workspace.assignedMonitorPoint = self
        return true
    }
}

@MainActor
private func rearrangeWorkspacesOnMonitors() {
    let monitors = monitorInfos
    displayUUIDToScreenPoint = [:]
    for monitor in monitors {
        if let uuid = monitor.sessionDisplayUUID { displayUUIDToScreenPoint[uuid] = monitor.rect.topLeftCorner }
    }
    let newScreens = monitors.map(\.rect.topLeftCorner)
    var newScreenToOldScreenMapping: [CGPoint: CGPoint] = [:]
    // Match display identity before geometry: swapping screen positions must not
    // swap their workspaces. An unavailable remembered screen falls back to first.
    let oldAssignments = screenPointToVisibleWorkspace.sorted { lhs, rhs in
        let leftConnected = monitors.contains { $0.sessionDisplayUUID == lhs.value.assignedDisplayUUID && lhs.value.assignedDisplayUUID != nil }
        let rightConnected = monitors.contains { $0.sessionDisplayUUID == rhs.value.assignedDisplayUUID && rhs.value.assignedDisplayUUID != nil }
        if leftConnected != rightConnected { return leftConnected }
        return lhs.value.name < rhs.value.name
    }
    for (oldScreen, workspace) in oldAssignments {
        let monitor = workspace.forceAssignedMonitor
            ?? monitors.first(where: { $0.sessionDisplayUUID == workspace.assignedDisplayUUID && workspace.assignedDisplayUUID != nil })
            ?? monitors.first
        guard let monitor else { continue }
        let newScreen = monitor.rect.topLeftCorner
        if newScreenToOldScreenMapping[newScreen] == nil {
            newScreenToOldScreenMapping[newScreen] = oldScreen
        }
    }

    let oldScreenPointToVisibleWorkspace = screenPointToVisibleWorkspace
    screenPointToVisibleWorkspace = [:]
    visibleWorkspaceToScreenPoint = [:]

    for newScreen in newScreens {
        if let existingVisibleWorkspace = newScreenToOldScreenMapping[newScreen].flatMap({ oldScreenPointToVisibleWorkspace[$0] }) {
            existingVisibleWorkspace.restoreMonitorAssignment(displayUUID: existingVisibleWorkspace.assignedDisplayUUID)
            if newScreen.setActiveWorkspace(existingVisibleWorkspace) { continue }
        }
        let stubWorkspace = getStubWorkspace(forPoint: newScreen)
        check(newScreen.setActiveWorkspace(stubWorkspace),
              "getStubWorkspace generated incompatible stub workspace (\(stubWorkspace)) for the monitor (\(newScreen)")
    }
}

@MainActor
private func isValidAssignment(workspace: Workspace, screen: CGPoint) -> Bool {
    switch workspace.forceAssignedMonitor {
        case let forceAssigned? where forceAssigned.rect.topLeftCorner != screen: false
        default: true
    }
}
