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

func bordersRingColor(_ name: String) -> NSColor {
    switch name {
        case "auto": .controlAccentColor
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
/// no ring on fullscreen windows; geometry is read-only from the engine's
/// `lastAppliedLayoutPhysicalRect` after every layout pass — the panel never
/// writes and never observes AX itself; plain (non-mouse-modifier) window drags
/// are not followed until the next engine pass.
@MainActor
final class BordersPanel: NSPanelHud {
    static let shared = BordersPanel()

    private let ringView = NSView()

    override private init() {
        super.init()
        contentView = ringView
        ringView.wantsLayer = true
        hasShadow = false
    }
    func refresh() {
        guard let window = focus.windowOrNil, bordersShouldShow(config: config, window: window),
            let rect = window.lastAppliedLayoutPhysicalRect
        else {
            orderOut(nil)
            return
        }
        let width = config.borders.width
        ringView.layer?.borderColor = bordersRingColor(config.borders.color).cgColor
        ringView.layer?.borderWidth = CGFloat(width)
        ringView.layer?.cornerRadius = 6
        setFrame(
            bordersRingFrame(windowRect: rect.nsWindowFrame, width: width),
            display: true,
        )
        orderFrontRegardless()
    }
}

extension Rect {
    /// AeroSpace Rect (y-down from the main display's top) → AppKit bottom-left frame.
    var nsWindowFrame: CGRect {
        CGRect(x: topLeftX, y: mainMonitorInfo.height - topLeftY - height, width: width, height: height)
    }
}

