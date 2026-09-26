import AppKit
import Common

@MainActor
final class SessionState {
    static let shared = SessionState()
    private(set) var isRestoring = true
    private var pendingSave: Task<Void, Never>?
    private var metadata: [UInt32: SessionWindow] = [:]
    private var lastSaveError: String?

    static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("macarchy", isDirectory: true)
            .appendingPathComponent(isDebug ? "session-debug.json" : "session.json")
    }

    /// Throttle, rather than debounce indefinitely while a window is being moved.
    /// Refreshes only enqueue one capture/write for a settled model at a time.
    func scheduleSave() {
        guard !isUnitTest, !isRestoring, !serverArgs.isReadOnly, pendingSave == nil else { return }
        pendingSave = Task { @MainActor in
            defer { pendingSave = nil }
            do {
                try await Task.sleep(for: .milliseconds(750))
                await refreshMetadata()
                try Task.checkCancellation()
                try writeSnapshot()
            } catch is CancellationError {
                // Explicit restart/termination flush owns the final write.
            } catch {
                reportSaveError(error)
            }
        }
    }

    func saveBeforeRestart() async throws {
        guard !isRestoring else { throw SessionStoreError.notReady }
        pendingSave?.cancel()
        pendingSave = nil
        if serverArgs.isReadOnly { return }
        await refreshMetadata()
        try writeSnapshot()
    }

    /// Termination cannot suspend the main actor. Refresh AX metadata on each app's
    /// existing worker thread, then atomically flush the current tree before unhide.
    func saveBeforeTermination() {
        guard !isUnitTest, !isRestoring, !serverArgs.isReadOnly else { return }
        pendingSave?.cancel()
        pendingSave = nil
        for window in MacWindow.allWindows {
            let info = window.macApp.getSessionInfoForTermination(window.windowId)
            metadata[window.windowId] = captureWindow(window, title: info?.title ?? metadata[window.windowId]?.title ?? "", rect: info?.rect, nativeFullscreen: info?.fullscreen ?? true)
        }
        do { try writeSnapshot() } catch { reportSaveError(error) }
    }

    @discardableResult
    func restore() async -> Bool {
        defer { isRestoring = false }
        guard !isUnitTest, !serverArgs.isReadOnly,
              FileManager.default.fileExists(atPath: Self.fileURL.path) else { return false }
        do {
            let snapshot = try JSONDecoder().decode(SessionSnapshot.self, from: Data(contentsOf: Self.fileURL))
            try snapshot.validate()
            await refreshMetadata()
            let matches = matchSessionWindows(saved: snapshot.windows, live: Array(metadata.values))
            apply(snapshot, matches: matches)
            return true
        } catch {
            reportSessionFailure("Could not restore the saved session", error: error)
            return false
        }
    }

    private func refreshMetadata() async {
        var result: [UInt32: SessionWindow] = [:]
        for window in MacWindow.allWindows {
            if Task.isCancelled { return }
            let title = (try? await window.getTitle(.nonCancellable)) ?? ""
            let rect = try? await window.getAxRect(.nonCancellable)
            // Unknown native state must never authorize a frame mutation.
            let native = (try? await window.isMacosFullscreen(.nonCancellable)) ?? true
            guard MacWindow.allWindowsMap[window.windowId] === window else { continue }
            result[window.windowId] = captureWindow(window, title: title, rect: rect, nativeFullscreen: native)
        }
        if Task.isCancelled { return }
        metadata = result
    }

    private func captureWindow(_ window: MacWindow, title: String, rect: Rect?, nativeFullscreen: Bool) -> SessionWindow {
        let previouslyFloating: Bool
        if case .macos(let kind) = window.layoutReason {
            previouslyFloating = kind == .floatingWindowsContainer
        } else {
            previouslyFloating = window.isFloating
        }
        return SessionWindow(
            id: window.windowId,
            pid: window.macApp.pid,
            launchDate: window.macApp.nsApp.launchDate,
            bundleID: window.macApp.rawAppBundleId,
            title: title,
            frame: nativeFullscreen
                ? metadata[window.windowId]?.frame
                : window.sessionFloatingRect(currentRect: rect).map(SessionFrame.init),
            floatingSize: window.lastFloatingSize.map { SessionSize(width: $0.width, height: $0.height) },
            scrollingSize: window.scrollingSize.map { Double($0) },
            fullscreen: window.isFullscreen,
            noOuterGaps: window.noOuterGapsInFullscreen,
            nativeFullscreen: nativeFullscreen,
            previouslyFloating: previouslyFloating,
        )
    }

    private func snapshot() -> SessionSnapshot {
        func node(_ value: TreeNode) -> SessionNode {
            let container = value as? TilingContainer
            let weight = (value.parent as? TilingContainer).map { value.getWeight($0.orientation) } ?? 1
            return SessionNode(
                window: (value as? Window)?.windowId,
                weight: weight > 0 && weight.isFinite ? weight : 1,
                scrollingSize: value.scrollingSize.map { Double($0) },
                layout: container?.layout.rawValue ?? "tiles",
                orientation: container?.orientation == .v ? "v" : "h",
                scrollingOffset: Double(container?.scrollingOffset ?? 0),
                children: value.children.map(node),
                mostRecentWindow: container?.mostRecentWindowRecursive?.windowId,
            )
        }
        let windows = MacWindow.allWindows.map { window -> SessionWindow in
            let cached = metadata[window.windowId].flatMap { info in
                info.pid == window.macApp.pid && info.launchDate == window.macApp.nsApp.launchDate ? info : nil
            }
            var info = cached ?? captureWindow(
                window, title: "", rect: window.lastAppliedLayoutPhysicalRect,
                nativeFullscreen: window.parent is MacosFullscreenWindowsContainer,
            )
            // Layout may have changed while metadata AX reads suspended.
            info.fullscreen = window.isFullscreen
            info.noOuterGaps = window.noOuterGapsInFullscreen
            info.floatingSize = window.lastFloatingSize.map { SessionSize(width: $0.width, height: $0.height) }
            info.scrollingSize = window.scrollingSize.map { Double($0) }
            if case .macos(let kind) = window.layoutReason { info.previouslyFloating = kind == .floatingWindowsContainer }
            else { info.previouslyFloating = window.isFloating }
            return info
        }
        return SessionSnapshot(
            windows: windows,
            workspaces: Workspace.all.map { workspace in
                SessionWorkspace(
                    name: workspace.name,
                    displayUUID: workspace.rememberedDisplayUUID,
                    visible: workspace.isVisible,
                    root: node(workspace.rootTilingContainer),
                    floating: workspace.floatingWindows.map(\.windowId),
                    nativeFullscreen: workspace.macOsNativeFullscreenWindowsContainer.children.compactMap { ($0 as? Window)?.windowId },
                    hidden: workspace.macOsNativeHiddenAppsWindowsContainer.children.compactMap { ($0 as? Window)?.windowId },
                )
            },
            focusedWindow: focus.windowOrNil?.windowId,
            focusedWorkspace: focus.workspace.name,
        )
    }

    private func writeSnapshot() throws {
        try snapshot().writeAtomically(to: Self.fileURL)
        lastSaveError = nil
    }

    private func reportSaveError(_ error: any Error) {
        let message = error.localizedDescription
        guard lastSaveError != message else { return }
        lastSaveError = message
        reportSessionFailure("Could not save the window session", error: error)
    }

    private func apply(_ snapshot: SessionSnapshot, matches: [UInt32: UInt32]) {
        let savedWindows = Dictionary(uniqueKeysWithValues: snapshot.windows.map { ($0.id, $0) })
        var originalRoots: [String: TilingContainer] = [:]
        var roots: [String: TilingContainer] = [:]
        for saved in snapshot.workspaces {
            let workspace = Workspace.get(byName: saved.name)
            workspace.restoreMonitorAssignment(displayUUID: saved.displayUUID)
            let old = workspace.rootTilingContainer
            old.unbindFromParent()
            originalRoots[saved.name] = old
            roots[saved.name] = TilingContainer(parent: workspace, adaptiveWeight: 1, saved.root.orientation == "v" ? .v : .h, Layout(rawValue: saved.root.layout) ?? .tiles, index: INDEX_BIND_LAST)
        }
        var usedDisplays = Set<Int>()
        let monitors = monitorInfos
        // Connected remembered displays take precedence over disconnected fallback.
        let visible = snapshot.workspaces.filter(\.visible).sorted { lhs, rhs in
            let leftConnected = lhs.displayUUID.map { uuid in monitors.contains { $0.sessionDisplayUUID == uuid } } ?? false
            let rightConnected = rhs.displayUUID.map { uuid in monitors.contains { $0.sessionDisplayUUID == uuid } } ?? false
            if leftConnected != rightConnected { return leftConnected }
            if lhs.name == snapshot.focusedWorkspace { return true }
            if rhs.name == snapshot.focusedWorkspace { return false }
            return lhs.name < rhs.name
        }
        for saved in visible {
            let workspace = Workspace.get(byName: saved.name)
            let monitor = workspace.forceAssignedMonitor
                ?? monitors.first(where: { $0.sessionDisplayUUID == saved.displayUUID && saved.displayUUID != nil })
                ?? monitors.first
            guard let monitor, usedDisplays.insert(monitor.monitorAppKitNsScreenScreensId).inserted else { continue }
            _ = monitor.setActiveWorkspace(workspace)
        }
        func restoreWindow(_ id: UInt32, parent: NonLeafTreeNodeObject, workspace: Workspace, weight: Double, scrollingSize: Double? = nil) {
            guard let liveID = matches[id], let window = MacWindow.allWindowsMap[liveID], let saved = savedWindows[id] else { return }
            let live = metadata[liveID]
            let destination: NonLeafTreeNodeObject
            if live?.nativeFullscreen != false {
                destination = workspace.macOsNativeFullscreenWindowsContainer
                window.layoutReason = .macos(prevParentKind: saved.previouslyFloating ? .floatingWindowsContainer : .tilingContainer)
            } else if window.parent is MacosMinimizedWindowsContainer {
                destination = macosMinimizedWindowsContainer
                window.layoutReason = .macos(prevParentKind: saved.previouslyFloating ? .floatingWindowsContainer : .tilingContainer)
            } else if window.parent is MacosHiddenAppsWindowsContainer {
                destination = workspace.macOsNativeHiddenAppsWindowsContainer
                window.layoutReason = .macos(prevParentKind: saved.previouslyFloating ? .floatingWindowsContainer : .tilingContainer)
            } else {
                destination = parent
                window.layoutReason = .standard
            }
            window.bind(to: destination, adaptiveWeight: weight, index: INDEX_BIND_LAST)
            window.scrollingSize = (scrollingSize ?? saved.scrollingSize).map { CGFloat($0) }
            window.lastFloatingSize = saved.floatingSize.map { CGSize(width: $0.width, height: $0.height) }
            window.isFullscreen = saved.fullscreen
            window.noOuterGapsInFullscreen = saved.noOuterGaps
            if window.isFloating, live?.nativeFullscreen == false, let frame = saved.frame {
                let fitted = frame.fitted(to: SessionFrame(workspace.workspaceMonitor.visibleRect))
                window.lastFloatingSize = CGSize(width: fitted.width, height: fitted.height)
                window.setAxFrame(CGPoint(x: fitted.x, y: fitted.y), window.lastFloatingSize)
            }
        }
        func populate(_ saved: SessionNode, container: TilingContainer, workspace: Workspace) {
            container.scrollingSize = saved.scrollingSize.map { CGFloat($0) }
            container.scrollingOffset = saved.scrollingOffset
            for child in saved.children {
                if let id = child.window {
                    restoreWindow(id, parent: container, workspace: workspace, weight: child.weight, scrollingSize: child.scrollingSize)
                } else {
                    let nested = TilingContainer(parent: container, adaptiveWeight: child.weight, child.orientation == "v" ? .v : .h, Layout(rawValue: child.layout) ?? .tiles, index: INDEX_BIND_LAST)
                    populate(child, container: nested, workspace: workspace)
                    if nested.children.isEmpty { nested.unbindFromParent() }
                }
            }
            if let savedID = saved.mostRecentWindow, let liveID = matches[savedID],
               let window = MacWindow.allWindowsMap[liveID],
               window.parentsWithSelf.contains(where: { $0 === container }) {
                window.markAsMostRecentChild()
            }
        }
        for saved in snapshot.workspaces {
            let workspace = Workspace.get(byName: saved.name)
            guard let root = roots[saved.name] else { continue }
            populate(saved.root, container: root, workspace: workspace)
            for id in saved.floating { restoreWindow(id, parent: workspace.floatingWindowsContainer, workspace: workspace, weight: 1) }
            for id in saved.nativeFullscreen + saved.hidden {
                let destination: NonLeafTreeNodeObject = savedWindows[id]?.previouslyFloating == true ? workspace.floatingWindowsContainer : root
                restoreWindow(id, parent: destination, workspace: workspace, weight: 1)
            }
        }
        // Append the remainder of the initial registration tree; new windows are
        // never discarded just because they were absent from the last snapshot.
        for (name, old) in originalRoots {
            guard let root = roots[name] else { continue }
            for child in old.children {
                let weight = child.getWeight(old.orientation)
                child.bind(to: root, adaptiveWeight: weight, index: INDEX_BIND_LAST)
            }
        }
        if let id = snapshot.focusedWindow.flatMap({ matches[$0] }), let window = MacWindow.allWindowsMap[id], window.toLiveFocusOrNil() != nil {
            if window.focusWindow() { window.nativeFocus() }
        } else if let saved = snapshot.workspaces.first(where: { $0.name == snapshot.focusedWorkspace }) {
            _ = Workspace.get(byName: saved.name).focusWorkspace()
        }
    }
}

extension SessionFrame {
    init(_ rect: Rect) {
        self.init(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
    }
}

extension MonitorInfo {
    var sessionDisplayUUID: String? {
        if isUnitTest { return nil }
        let screens = NSScreen.screens
        let index = monitorAppKitNsScreenScreensId - 1
        guard screens.indices.contains(index),
              let number = screens[index].deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }
}

@MainActor
func reportSessionFailure(_ title: String, error: any Error) {
    NSLog("%@ — %@", title, error.localizedDescription)
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = title
    alert.informativeText = error.localizedDescription
    alert.addButton(withTitle: "OK")
    // Never block termination or a socket reply on a modal alert.
    Task { @MainActor in alert.runModal() }
}
