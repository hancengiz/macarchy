import AppKit
import Common
import Foundation

// Omarchy-style mouse edge focus: parking the pointer at the far left/right edge
// of a screen moves focus to the previous/next window in the workspace, like
// pressing Super+Left/Right. Only physical screen edges adjacent to no other
// display qualify. Two trigger styles: a brief dwell (two poll ticks), or the
// push-bounce-push gesture — push into the edge, pull slightly back, push again —
// which fires immediately and repeats for every bounce.

enum MouseEdgeFocusDirection: Equatable {
    case left
    case right
}

@MainActor
enum MouseEdgeFocus {
    static var loop: Task<Void, Never>?
    static var dwellDirection: MouseEdgeFocusDirection?
    static var firedDirection: MouseEdgeFocusDirection?
    static var lastLeftEdge: MouseEdgeFocusDirection?
    static var lastLeftAt: Date?
    static var enabled = false

    static func sync(enabled: Bool) {
        MouseEdgeFocus.enabled = enabled
        loop?.cancel()
        loop = nil
        guard enabled, !isUnitTest else { return }
        loop = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(60))
                guard !Task.isCancelled else { return }
                tick()
            }
        }
    }

    private static func tick() {
        guard TrayMenuModel.shared.isEnabled, activeMode == mainModeId, !ModifierMouse.isDragging else {
            dwellDirection = nil
            firedDirection = nil
            lastLeftEdge = nil
            return
        }
        let mouse = NSEvent.mouseLocation
        let screens = NSScreen.screens
        guard let screen = screens.first(where: { $0.frame.contains(mouse) }) else {
            dwellDirection = nil
            firedDirection = nil
            lastLeftEdge = nil
            return
        }
        let direction = edgeFocusDirection(
            mouse: mouse,
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            otherScreens: screens.filter { $0 != screen }.map(\.frame),
        )
        let now = Date()
        // Leaving the edge zone (after dwelling or firing) arms the bounce: a
        // quick return to the same edge is the deliberate push-bounce-push gesture.
        if direction == nil, let left = dwellDirection ?? firedDirection {
            lastLeftEdge = left
            lastLeftAt = now
        }
        let step = edgeFocusDwellStep(dwell: dwellDirection, fired: firedDirection, current: direction)
        dwellDirection = step.dwell
        firedDirection = step.fired
        if isEdgeFocusBounceArrival(
            lastLeft: lastLeftEdge,
            leftAge: lastLeftAt.map { now.timeIntervalSince($0) },
            current: direction
        ), firedDirection != direction {
            dwellDirection = nil
            firedDirection = direction
            lastLeftEdge = nil
            fire(direction: direction!)
        } else if let toFire = step.fire {
            fire(direction: toFire)
        }
    }

    private static func fire(direction: MouseEdgeFocusDirection) {
        Task.startUnstructured {
            guard let token: RunSessionGuard = .isServerEnabled else { return }
            try await runLightSession(.globalObserver("mouseEdgeFocus"), token) {
                let args = FocusCmdArgs(rawArgs: ["--boundaries", "workspace"], cardinalOrDfsDirection: .direction(direction == .left ? .left : .right))
                _ = await FocusCommand(args: args).run(.defaultEnv, CmdIoImpl.emptyStdinIgnoringOut)
            }
        }
    }
}

/// Pure decision: returns the edge direction when the pointer sits in the edge
/// zone of a screen whose edge is not adjacent to another display.
/// `visibleFrame` drives the usable area (menu bar and Dock excluded).
func edgeFocusDirection(
    mouse: CGPoint,
    screenFrame: CGRect,
    visibleFrame: CGRect,
    otherScreens: [CGRect],
    threshold: CGFloat = 2,
) -> MouseEdgeFocusDirection? {
    guard mouse.y >= visibleFrame.minY, mouse.y <= visibleFrame.maxY else { return nil }
    let nearLeft = mouse.x <= visibleFrame.minX + threshold
    let nearRight = mouse.x >= visibleFrame.maxX - threshold
    guard nearLeft || nearRight else { return nil }
    // An edge shared with another display is a normal place to park the pointer
    // while working on the neighbor; only dead-end edges trigger.
    let probeLeft = CGPoint(x: screenFrame.minX - 2, y: mouse.y)
    let probeRight = CGPoint(x: screenFrame.maxX + 2, y: mouse.y)
    if nearLeft, !otherScreens.contains(where: { $0.insetBy(dx: -2, dy: -2).contains(probeLeft) }) {
        return .left
    }
    if nearRight, !otherScreens.contains(where: { $0.insetBy(dx: -2, dy: -2).contains(probeRight) }) {
        return .right
    }
    return nil
}

/// Pure bounce decision: true when the pointer just arrived at the same dead-end
/// edge zone it left moments ago — the push-bounce-push gesture — which fires
/// immediately instead of waiting for the two-tick dwell. `leftAge` is the time
/// since the pointer left that edge zone.
func isEdgeFocusBounceArrival(
    lastLeft: MouseEdgeFocusDirection?,
    leftAge: TimeInterval?,
    current: MouseEdgeFocusDirection?,
    window: TimeInterval = 0.8
) -> Bool {
    guard let lastLeft, let leftAge, let current else { return false }
    return lastLeft == current && leftAge >= 0 && leftAge <= window
}

/// Pure dwell state machine for one poll tick. The pointer must sit in the same
/// dead-end edge zone on two consecutive ticks before `fire` is emitted. After
/// firing, the direction stays `fired` until the pointer leaves that edge zone,
/// so parking the pointer fires exactly once instead of re-triggering forever.
func edgeFocusDwellStep(
    dwell: MouseEdgeFocusDirection?,
    fired: MouseEdgeFocusDirection?,
    current: MouseEdgeFocusDirection?
) -> (dwell: MouseEdgeFocusDirection?, fired: MouseEdgeFocusDirection?, fire: MouseEdgeFocusDirection?) {
    if let fired, fired == current {
        return (dwell: nil, fired: fired, fire: nil)
    }
    if let current, current == dwell {
        return (dwell: nil, fired: current, fire: current)
    }
    return (dwell: current, fired: nil, fire: nil)
}
