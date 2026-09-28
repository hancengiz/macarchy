import Foundation
import SwiftUI
public struct ThemePalette: Sendable {
    public let name: String
    public let backgroundRgb: (Double, Double, Double)
    public let cardBackgroundRgb: (Double, Double, Double)
    public let separatorRgb: (Double, Double, Double)
    public let primaryTextRgb: (Double, Double, Double)
    public let secondaryTextRgb: (Double, Double, Double)
    public let accentRgb: (Double, Double, Double)

    public var background: Color { Color(rgb: backgroundRgb) }
    public var cardBackground: Color { Color(rgb: cardBackgroundRgb) }
    public var separator: Color { Color(rgb: separatorRgb) }
    public var primaryText: Color { Color(rgb: primaryTextRgb) }
    public var secondaryText: Color { Color(rgb: secondaryTextRgb) }
    public var accent: Color { Color(rgb: accentRgb) }
}

extension Color {
    init(rgb: (Double, Double, Double)) {
        self.init(.sRGB, red: rgb.0, green: rgb.1, blue: rgb.2, opacity: 1)
    }
}

public enum Theme {
    public static let light = ThemePalette(
        name: "light",
        backgroundRgb: (0.96, 0.96, 0.97),
        cardBackgroundRgb: (1.0, 1.0, 1.0),
        separatorRgb: (0.82, 0.82, 0.84),
        primaryTextRgb: (0.07, 0.07, 0.08),
        secondaryTextRgb: (0.40, 0.40, 0.43),
        accentRgb: (0.36, 0.33, 0.78)
    )
    public static let dark = ThemePalette(
        name: "dark",
        backgroundRgb: (0.11, 0.11, 0.13),
        cardBackgroundRgb: (0.16, 0.16, 0.18),
        separatorRgb: (0.28, 0.28, 0.31),
        primaryTextRgb: (0.95, 0.95, 0.96),
        secondaryTextRgb: (0.66, 0.66, 0.69),
        accentRgb: (0.70, 0.68, 1.0)
    )

    public static func current(isDark: Bool) -> ThemePalette { isDark ? dark : light }

    /// WCAG 2.x relative-luminance contrast ratio, for tests and token discipline.
    public static func contrastRatio(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
        func luminance(_ c: (Double, Double, Double)) -> Double {
            func channel(_ x: Double) -> Double { x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
            return 0.2126 * channel(c.0) + 0.7152 * channel(c.1) + 0.0722 * channel(c.2)
        }
        let l1 = luminance(a), l2 = luminance(b)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }
}
