import AppKit
import Common

@MainActor
private var activeRefreshTask: Task<(), any Error>? = nil

@MainActor
func scheduleCancellableCompleteRefreshSession(
    _ event: RefreshSessionEvent,
    optimisticallyPreLayoutWorkspaces: Bool = false,
) {
    guard isUnitTest || !SessionState.shared.isRestoring else { return }
    activeRefreshTask?.cancel()
    activeRefreshTask = Task.startUnstructured { @MainActor in
        try checkCancellation()
        await runHeavyCompleteRefreshSession(
            event,
            assumeCancellable: true,
            optimisticallyPreLayoutWorkspaces: optimisticallyPreLayoutWorkspaces,
        )
    }
}

@MainActor
func runHeavyCompleteRefreshSession(
    _ event: RefreshSessionEvent,
    assumeCancellable: Bool,
    layoutWorkspaces shouldLayoutWorkspaces: Bool = true,
    optimisticallyPreLayoutWorkspaces: Bool = false,
) async {
    let state = signposter.beginInterval(#function, "event: \(event) axTaskLocalAppThreadToken: \(axTaskLocalAppThreadToken?.idForDebug)")
    defer { signposter.endInterval(#function, state) }
    if !TrayMenuModel.shared.isEnabled { return }
    let res = await Result {
        try await $refreshSessionEvent.withValue(event) {
            let nativeFocused = try await getNativeFocusedWindow(.cancellable)
            if let nativeFocused { try await debugWindowsIfRecording(nativeFocused, .cancellable) }
            updateFocusCache(nativeFocused)

            if shouldLayoutWorkspaces && optimisticallyPreLayoutWorkspaces { try await layoutWorkspaces() }

            await refreshModel_nonCancellable()
            try await refresh()
            gcMonitors()

            updateTrayText()
            SecureInputPanel.shared.refresh()
            refreshSystemModePanel()
            try await normalizeLayoutReason()
            if shouldLayoutWorkspaces { try await layoutWorkspaces() }
            SessionState.shared.scheduleSave()
            // Covers focus changes not driven by commands (clicks, ⌘-Tab, app
            // activation): those never pass through the light-session raise.
            scheduleFloatingWindowsRaise()
        }
    }
    switch res {
        case .success(()): break
        case .failure(let err as CancellationError): check(assumeCancellable, "Non cancellable refresh session was canceled: \(err) (\(type(of: err)))")
        case .failure(let err): die("Illegal error: \(err)")
    }
}

@MainActor
func runLightSession<T>(
    _ event: RefreshSessionEvent,
    _: RunSessionGuard,
    body: @MainActor () async throws -> T,
) async throws -> T {
    let state = signposter.beginInterval(#function, "event: \(event) axTaskLocalAppThreadToken: \(axTaskLocalAppThreadToken?.idForDebug)")
    defer { signposter.endInterval(#function, state) }
    activeRefreshTask?.cancel() // Give priority to runSession
    activeRefreshTask = nil
    return try await $refreshSessionEvent.withValue(event) {
        let nativeFocused = try await getNativeFocusedWindow(.cancellable)
        if let nativeFocused { try await debugWindowsIfRecording(nativeFocused, .cancellable) }
        updateFocusCache(nativeFocused)
        let focusBefore = focus.windowOrNil

        await refreshModel_nonCancellable()
        let result = try await body()
        if isMacarchyRestartPrepared { return result }
        await refreshModel_nonCancellable()

        let focusAfter = focus.windowOrNil

        updateTrayText()
        SecureInputPanel.shared.refresh()
        refreshSystemModePanel()
        if !event.isFocusFollowsMouse { try await layoutWorkspaces() }

        if focusBefore != focusAfter {
            focusAfter?.nativeFocus() // syncFocusToMacOs
            // Hyprland-style layering (Omarchy): floating windows live above the tiling
            // layer. nativeFocus enqueues async AX jobs whose activation reorders windows
            // at unpredictable times, so the raise is coalesced and retried — a single
            // fixed delay loses the race.
            if !(focusAfter?.isFloating ?? false) {
                scheduleFloatingWindowsRaise()
            }
        }
        if !event.isFocusFollowsMouse { scheduleCancellableCompleteRefreshSession(event) }
        SessionState.shared.scheduleSave()
        return result
    }
}

/// Hyprland-style layering: floating windows stay above the tiling layer.
@MainActor
func raiseFloatingWindows(workspace: Workspace?) {
    guard config.keepFloatingWindowsOnTop, !isUnitTest, let workspace else { return }
    // A focused floating window is already at the top via activation; raising the
    // other floats would stack them above the focused one.
    if focus.windowOrNil?.isFloating == true { return }
    for window in workspace.floatingWindows {
        (window as? MacWindow)?.nativeRaise()
    }
}

@MainActor
private var floatingRaiseTask: Task<(), Never>? = nil

/// Re-raises floating windows after the AppKit z-order settles. App activations
/// land asynchronously and can arrive after any fixed delay, so the raise retries
/// with backoff; bursts coalesce (the last call wins).
@MainActor
func scheduleFloatingWindowsRaise() {
    guard config.keepFloatingWindowsOnTop, !isUnitTest else { return }
    floatingRaiseTask?.cancel()
    floatingRaiseTask = Task.startUnstructured { @MainActor in
        for delay: Duration in [.milliseconds(100), .milliseconds(300), .milliseconds(700)] {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            raiseFloatingWindows(workspace: focus.workspace)
        }
    }
}

struct RunSessionGuard: Sendable {
    @MainActor
    static var isServerEnabled: RunSessionGuard? { TrayMenuModel.shared.isEnabled ? forceRun : nil }
    @MainActor
    static func isServerEnabled(orIsEnableCommand command: (any Command)?) -> RunSessionGuard? {
        command is EnableCommand ? .forceRun : .isServerEnabled
    }
    @MainActor
    static func checkServerIsEnabledOrDie(
        file: StaticString = #fileID,
        line: Int = #line,
        column: Int = #column,
        function: String = #function,
    ) -> RunSessionGuard {
        .isServerEnabled ?? dieT("server is disabled", file: file, line: line, column: column, function: function)
    }
    static let forceRun = RunSessionGuard()
    private init() {}
}

@MainActor
func refreshModel_nonCancellable() async {
    if refreshSessionEvent?.isFocusFollowsMouse == true {
        await checkOnFocusChangedCallbacks_nonCancellable()
    } else {
        Workspace.garbageCollectUnusedWorkspaces()
        await checkOnFocusChangedCallbacks_nonCancellable()
        normalizeContainers()
    }
}

@MainActor
private func refresh() async throws {
    // Garbage collect terminated apps and windows before working with all windows
    let mapping = try await MacApp.refreshAllAndGetAliveWindowIds(frontmostAppBundleId: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    let aliveWindowIds = mapping.values.flatMap(id).toSet()

    for window in MacWindow.allWindows {
        if !aliveWindowIds.contains(window.windowId) {
            window.garbageCollect(skipClosedWindowsCache: false)
        }
    }
    for (app, windowIds) in mapping {
        for windowId in windowIds {
            try await MacWindow.getOrRegister(windowId: windowId, macApp: app)
        }
    }

    // Garbage collect workspaces after apps, because workspaces contain apps.
    Workspace.garbageCollectUnusedWorkspaces()
}

func refreshObs(_: AXObserver, _: AXUIElement, notif: CFString, _: UnsafeMutableRawPointer?) {
    let notif = notif as String
    Task.startUnstructured { @MainActor in
        if !TrayMenuModel.shared.isEnabled { return }
        scheduleCancellableCompleteRefreshSession(.ax(notif))
    }
}

@MainActor
private func layoutWorkspaces() async throws {
    if !TrayMenuModel.shared.isEnabled {
        for workspace in Workspace.all {
            workspace.allLeafWindowsRecursive.forEach { ($0 as! MacWindow).unhideFromCorner() } // todo as!
            try await workspace.layoutWorkspace() // Unhide tiling windows from corner
        }
        return
    }
    let monitors = monitorInfos
    let displayFrames = monitors.map { $0.rect.cgRect }

    // to reduce flicker, first unhide visible workspaces, then hide invisible ones
    for monitor in monitors {
        let workspace = monitor.activeWorkspace
        workspace.allLeafWindowsRecursive.filter { !$0.isOutsideScrollingViewport }
            .forEach { ($0 as! MacWindow).unhideFromCorner() } // todo as!
        try await workspace.layoutWorkspace(displayFrames: displayFrames)
    }
    for workspace in Workspace.all where !workspace.isVisible {
        for window in workspace.allLeafWindowsRecursive {
            try await (window as! MacWindow).hideInCorner(displayFrames) // todo as!
        }
    }
}

@MainActor
private func normalizeContainers() {
    // Can't do it only for visible workspace because most of the commands support --window-id and --workspace flags
    for workspace in Workspace.all {
        workspace.normalizeContainers()
    }
}
