import AppKit
import SwiftUI

/// Shared visual language for macarchy overlay surfaces, modeled on Omarchy's
/// Quickshell theme: soft translucent panels, a teal accent, hairline borders.
/// Every color, radius, and font size used by overlays lives here.
enum Theme {
    /// Omarchy accent teal (#33CCFF), also the active-border gradient start.
    static let accent = Color(red: 0.20, green: 0.80, blue: 1.00)
    /// Omarchy accent green (#00FF99), the active-border gradient end.
    static let accentEnd = Color(red: 0.00, green: 1.00, blue: 0.60)
    static let selectionTintOpacity = 0.16

    static let cornerRadius: CGFloat = 12
    static let rowCornerRadius: CGFloat = 8
    static let hairlineWidth: CGFloat = 1

    /// Standard panel background: translucent material, rounded corners, and a
    /// hairline border that stays legible in both light and dark appearances.
    static func panelBackground(material: NSVisualEffectView.Material) -> NSVisualEffectView {
        let background = NSVisualEffectView()
        background.material = material
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = cornerRadius
        background.layer?.masksToBounds = true
        background.layer?.borderWidth = hairlineWidth
        background.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.4).cgColor
        return background
    }

    /// Linear accent brush used for highlights, matching the active window border.
    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accent, accentEnd], startPoint: .top, endPoint: .bottom)
    }
}

/// Keycap chip used by HUD-style surfaces (system mode, cheat sheets).
struct KeyCap: View {
    let key: String
    var prominent = false

    var body: some View {
        Text(key)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .frame(minWidth: 34, alignment: .center)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(prominent ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color.primary.opacity(0.09))),
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: Theme.hairlineWidth),
            )
    }
}
