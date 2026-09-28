import AppKit
import Common

/// Config-level palette selection.
struct PaletteConfig: ConvenienceMutable, Equatable, Sendable {
    var name: String = "default"
}

/// Shared color roles for WM overlays (borders today, the bar next).
/// `default` follows the system accent; the rest are fixed sets.
struct Palette {
    let name: String

    static let allNames = ["default", "nord", "dracula", "solarized-dark", "gruvbox-dark"]

    init(name: String) {
        self.name = Self.allNames.contains(name) ? name : "default"
    }

    var focus: NSColor? { Self.table[name]?.focus }
    var inactive: NSColor? { Self.table[name]?.inactive }
    var background: NSColor? { Self.table[name]?.background }
    var text: NSColor? { Self.table[name]?.text }

    struct Roles {
        let focus: NSColor
        let inactive: NSColor
        let background: NSColor
        let text: NSColor
    }

    static let table: [String: Roles] = [
        "default": .init(focus: .controlAccentColor, inactive: .quaternaryLabelColor, background: .windowBackgroundColor, text: .labelColor),
        "nord": .init(
            focus: NSColor(red: 0.48, green: 0.63, blue: 0.78, alpha: 1), // nord11-ish steel blue
            inactive: NSColor(red: 0.29, green: 0.34, blue: 0.42, alpha: 1),
            background: NSColor(red: 0.13, green: 0.16, blue: 0.21, alpha: 1),
            text: NSColor(red: 0.87, green: 0.90, blue: 0.92, alpha: 1)
        ),
        "dracula": .init(
            focus: NSColor(red: 0.62, green: 0.53, blue: 0.94, alpha: 1),
            inactive: NSColor(red: 0.31, green: 0.30, blue: 0.40, alpha: 1),
            background: NSColor(red: 0.16, green: 0.16, blue: 0.21, alpha: 1),
            text: NSColor(red: 0.93, green: 0.93, blue: 0.91, alpha: 1)
        ),
        "solarized-dark": .init(
            focus: NSColor(red: 0.15, green: 0.55, blue: 0.55, alpha: 1), // cyan
            inactive: NSColor(red: 0.20, green: 0.23, blue: 0.23, alpha: 1),
            background: NSColor(red: 0.00, green: 0.17, blue: 0.21, alpha: 1),
            text: NSColor(red: 0.93, green: 0.91, blue: 0.84, alpha: 1)
        ),
        "gruvbox-dark": .init(
            focus: NSColor(red: 0.70, green: 0.53, blue: 0.24, alpha: 1), // yellow
            inactive: NSColor(red: 0.27, green: 0.25, blue: 0.23, alpha: 1),
            background: NSColor(red: 0.16, green: 0.16, blue: 0.15, alpha: 1),
            text: NSColor(red: 0.85, green: 0.80, blue: 0.69, alpha: 1)
        ),
    ]

    /// WCAG relative-luminance contrast ratio (overlay visibility discipline).
    static func contrastRatio(_ a: NSColor, _ b: NSColor) -> Double {
        func luminance(_ c: NSColor) -> Double {
            let rgb = c.usingColorSpace(.sRGB)!
            func channel(_ x: CGFloat) -> Double {
                let v = Double(x)
                return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(rgb.redComponent) + 0.7152 * channel(rgb.greenComponent) + 0.0722 * channel(rgb.blueComponent)
        }
        let l1 = luminance(a), l2 = luminance(b)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }
}

private let paletteParser: [String: any ParserProtocol<PaletteConfig>] = [
    "name": Parser(\.name, parseString),
]

func parsePalette(_ raw: OrderedJson, _ backtrace: ConfigBacktrace, _ c: inout ConfigParserContext) -> PaletteConfig {
    parseTable(raw, PaletteConfig(), paletteParser, backtrace, &c)
}
