import AppKit
import Common

enum MouseModifier: String, Sendable {
    case none, alt, ctrl, cmd

    var flags: CGEventFlags {
        switch self {
            case .none: []
            case .alt: .maskAlternate
            case .ctrl: .maskControl
            case .cmd: .maskCommand
        }
    }
}

@MainActor
func syncModifierMouse(_ config: Config) -> Bool {
    if isUnitTest { return true }
    return ModifierMouse.sync(enabled: config.mouseModifier != .none)
}

@MainActor
enum ModifierMouse {
    @MainActor private final class Gesture {
        let window: Window
        let resize: Bool
        let start: CGPoint
        let initialRect: Rect
        let sizing: ManagedResize
        var point: CGPoint
        var finished = false
        var focused = false

        init(window: Window, resize: Bool, point: CGPoint, rect: Rect) {
            self.window = window
            self.resize = resize
            start = point
            self.point = point
            initialRect = rect
            sizing = ManagedResize(window: window, rect: rect, fromLeft: point.x < rect.center.x, fromTop: point.y < rect.center.y)
        }
    }

    private static var tap: CFMachPort?
    private static var source: CFRunLoopSource?
    private static var gesture: Gesture?
    private static var worker: Task<Void, Never>?
    static var isDragging: Bool { gesture != nil }

    static func sync(enabled: Bool) -> Bool {
        if !enabled {
            if let tap { CFMachPortInvalidate(tap) }
            if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
            tap = nil
            source = nil
            if let gesture {
                gesture.finished = true
                drain()
            }
            return true
        }
        if tap != nil { return true }
        let types: [CGEventType] = [.leftMouseDown, .leftMouseDragged, .leftMouseUp,
                                    .rightMouseDown, .rightMouseDragged, .rightMouseUp]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let newTap = unsafe CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                                    options: .defaultTap, eventsOfInterest: mask,
                                                    callback: modifierMouseCallback, userInfo: nil) else { return false }
        tap = newTap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        return true
    }

    static func handle(_ type: CGEventType, flags: CGEventFlags, point: CGPoint) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            if let gesture { gesture.finished = true; drain() }
            return false
        }
        if let gesture {
            let dragged = gesture.resize ? CGEventType.rightMouseDragged : .leftMouseDragged
            let released = gesture.resize ? CGEventType.rightMouseUp : .leftMouseUp
            if type == dragged || type == released {
                gesture.point = point
                gesture.finished = type == released
                drain()
                return true
            }
        }
        let modifiers: CGEventFlags = [.maskAlternate, .maskControl, .maskCommand, .maskShift]
        guard gesture == nil, TrayMenuModel.shared.isEnabled, activeMode == mainModeId,
              config.mouseModifier != .none, flags.intersection(modifiers) == config.mouseModifier.flags,
              type == .leftMouseDown || type == .rightMouseDown,
              let (window, rect) = windowAt(point), !window.isFullscreen,
              !window.isOutsideScrollingViewport,
              window.parent is TilingContainer || window.isFloating else { return false }
        gesture = Gesture(window: window, resize: type == .rightMouseDown, point: point, rect: rect)
        currentlyManipulatedWithMouseWindowId = window.windowId
        resetClosedWindowsCache()
        drain()
        return true
    }

    // WindowServer's front-to-back list avoids dragging a tile behind a floating window.
    private static func windowAt(_ point: CGPoint) -> (Window, Rect)? {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        for info in windows {
            guard let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let cgRect = CGRect(dictionaryRepresentation: bounds as CFDictionary), cgRect.contains(point),
                  let layer = info[kCGWindowLayer as String] as? Int, layer >= 0,
                  let id = info[kCGWindowNumber as String] as? UInt32 else { continue }
            guard let window = Window.get(byId: id) else { return nil }
            return (window, Rect(topLeftX: cgRect.minX, topLeftY: cgRect.minY, width: cgRect.width, height: cgRect.height))
        }
        return nil
    }

    // Coalesce movement while AX is busy. Mouse-up is retained and always finishes the drag.
    private static func drain() {
        guard worker == nil else { return }
        worker = Task { @MainActor in
            defer { worker = nil }
            while let current = gesture {
                let point = current.point
                let finished = current.finished
                guard let token = RunSessionGuard.isServerEnabled, current.window.isBound else {
                    gesture = nil
                    currentlyManipulatedWithMouseWindowId = nil
                    scheduleCancellableCompleteRefreshSession(.globalObserver("modifierMouse"))
                    return
                }
                do {
                    try await runLightSession(.globalObserver("modifierMouse"), token) {
                        if !current.focused {
                            _ = current.window.focusWindow()
                            current.focused = true
                        }
                        apply(current, at: point)
                        if finished {
                            currentlyManipulatedWithMouseWindowId = nil
                        }
                    }
                } catch {
                    gesture = nil
                    currentlyManipulatedWithMouseWindowId = nil
                    scheduleCancellableCompleteRefreshSession(.globalObserver("modifierMouse"))
                    return
                }
                if finished {
                    gesture = nil
                    return
                }
                if current.point == point && !current.finished { return }
            }
        }
    }

    private static func apply(_ gesture: Gesture, at point: CGPoint) {
        let window = gesture.window
        let delta = point - gesture.start
        if gesture.resize {
            let rect = gesture.sizing.draggedRect(delta: delta)
            if window.isFloating {
                window.lastFloatingSize = rect.size
            } else {
                gesture.sizing.apply(width: rect.width, height: rect.height)
            }
            window.setAxFrame(rect.topLeftCorner, rect.size)
        } else {
            if window.isFloating {
                let workspace = point.monitorApproximation.activeWorkspace
                if window.nodeWorkspace != workspace { window.bindAsFloatingWindow(to: workspace) }
            } else {
                moveTilingWindow(window, at: point)
            }
            window.setAxFrame(gesture.initialRect.topLeftCorner + delta, nil)
        }
    }
}

private func modifierMouseCallback(_: CGEventTapProxy, type: CGEventType, event: CGEvent, _: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    let flags = event.flags
    let point = event.location
    // The tap source is installed exclusively on the main run loop.
    let consumed = MainActor.assumeIsolated { ModifierMouse.handle(type, flags: flags, point: point) }
    return unsafe consumed ? nil : Unmanaged.passUnretained(event)
}
