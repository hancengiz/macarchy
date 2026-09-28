import AppKit
import Common

// Pure decision helpers (testable without AppKit windows).

@MainActor
func bordersShouldShow(config: Config, window: Window) -> Bool {
    config.borders.enabled
        && window.isBound
        && !window.isFullscreen
        && window.lastAppliedLayoutPhysicalRect != nil
}

func bordersRingFrame(windowRect: CGRect, width: Int) -> CGRect {
    let w = CGFloat(max(1, min(16, width)))
    return windowRect.insetBy(dx: -w / 2, dy: -w / 2)
}

func bordersRingColor(_ name: String, paletteName: String = "default") -> NSColor {
    switch name {
        case "auto": .controlAccentColor
        case "palette": Palette(name: paletteName).focus ?? .controlAccentColor
        case "blue": .blue
        case "red": .red
        case "green": .green
        case "yellow": .yellow
        case "cyan": .cyan
        case "magenta": .magenta
        case "white": .white
        default: .controlAccentColor
    }
}

@MainActor
func refreshBordersPanel() {
    if !isUnitTest { BordersPanel.shared.refresh() }
}

/// Focus ring overlay around the focused window. Rulings (donor borders.md, ported):
/// no ring on fullscreen windows. The layout pass after every engine event is
/// authoritative (engine's `lastAppliedLayoutPhysicalRect`); while the user
/// drags/resizes with the mouse, a global drag monitor re-reads the window's
/// LIVE AX frame so the ring follows the window, not the stale layout slot.
@MainActor
final class BordersPanel: NSPanelHud {
    static let shared = BordersPanel()

    private let ringView = NSView()
    private var lastRingFrame: CGRect = .zero
    private var lastRingKey: String = ""
    private var dragMonitor: Any?
    private var isTrackingDrag = false

    override private init() {
        super.init()
        contentView = ringView
        ringView.wantsLayer = true
        hasShadow = false
        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.trackDrag()
            }
        }
    }

    func refresh() {
        guard let window = focus.windowOrNil, bordersShouldShow(config: config, window: window),
            let rect = window.lastAppliedLayoutPhysicalRect
        else {
            lastRingFrame = .zero
            lastRingKey = ""
            orderOut(nil)
            return
        }
        applyRing(rect: rect.nsWindowFrame)
    }

    /// Live-follow during mouse drags: read the focused window's actual AX frame.
    private func trackDrag() {
        guard !isTrackingDrag, config.borders.enabled,
            let window = focus.windowOrNil, window.isBound, !window.isFullscreen
        else { return }
        isTrackingDrag = true
        Task.startUnstructured {
            if let liveRect = try? await window.getAxRect(.nonCancellable) {
                await MainActor.run {
                    self.applyRing(rect: liveRect.nsWindowFrame)
                }
            }
            self.isTrackingDrag = false
        }
    }

    private func applyRing(rect windowFrame: CGRect) {
        let width = config.borders.width
        let color = bordersRingColor(config.borders.color, paletteName: config.palette.name)
        let key = "\(windowFrame)|\(width)|\(color)"
        let frame = bordersRingFrame(windowRect: windowFrame, width: width)
        let frameChanged = frame != lastRingFrame || key != lastRingKey
        if frameChanged {
            ringView.layer?.borderColor = color.cgColor
            ringView.layer?.borderWidth = CGFloat(width)
            ringView.layer?.cornerRadius = 6
            setFrame(frame, display: true)
            orderFrontRegardless()
            lastRingFrame = frame
            lastRingKey = key
        }
    }
}

extension Rect {
    /// AeroSpace Rect (y-down from the main display's top) → AppKit bottom-left frame.
    var nsWindowFrame: CGRect {
        CGRect(x: topLeftX, y: mainMonitorInfo.height - topLeftY - height, width: width, height: height)
    }
}

