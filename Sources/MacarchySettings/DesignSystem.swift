import MacarchySettingsCore
import SwiftUI

// MARK: - Design system

/// Premium surface built on the contrast-tested Core theme tokens.
struct AppTheme {
    let palette: ThemePalette

    static func current(_ scheme: ColorScheme) -> AppTheme {
        AppTheme(palette: Theme.current(isDark: scheme == .dark))
    }

    var background: Color { palette.background }
    var sidebar: Color { palette.name == "light" ? Color(nsColor: .controlBackgroundColor) : palette.background }
    var card: Color { palette.cardBackground }
    var cardBorder: Color { palette.separator.opacity(0.5) }
    var separator: Color { palette.separator }
    var primaryText: Color { palette.primaryText }
    var secondaryText: Color { palette.secondaryText }
    var accent: Color { palette.accent }
    var accentText: Color { palette.background }
}

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue = AppTheme.current(.light)
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}

/// Content card: rounded 12, hairline border, generous padding.
struct PremiumCard<Content: View>: View {
    @Environment(\.appTheme) private var theme
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(theme.cardBorder, lineWidth: 1)
            )
    }
}

/// Panel header: tinted icon tile, title, subtitle.
struct PanelHeader: View {
    @Environment(\.appTheme) private var theme
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(tint.opacity(0.16))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(theme.primaryText)
                Text(subtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.secondaryText)
            }
            Spacer()
        }
        .padding(.bottom, 6)
    }
}

/// Small labeled value pill for stats (About panel, permissions).
struct StatPill: View {
    @Environment(\.appTheme) private var theme
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(theme.secondaryText.opacity(0.08))
        )
    }
}

/// Sidebar row with icon tile and selection pill (System Settings style).
struct SidebarRow: View {
    @Environment(\.appTheme) private var theme
    let section: SettingsSection
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.9) : section.tint.opacity(0.16))
                    .frame(width: 26, height: 26)
                Image(systemName: section.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isSelected ? section.tint : section.tint)
            }
            Text(section.rawValue)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? theme.primaryText : theme.secondaryText)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? theme.accent.opacity(0.16) : Color.clear)
        )
        .contentShape(Rectangle())
    }
}

extension SettingsSection {
    var tint: Color {
        switch self {
            case .appearance: .blue
            case .gapsAndLayout: .indigo
            case .keybindings: .orange
            case .overlays: .purple
            case .permissions: .green
            case .about: .gray
        }
    }
}

/// Section label inside panels.
struct CardLabel: View {
    @Environment(\.appTheme) private var theme
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .bold))
            .foregroundStyle(theme.secondaryText.opacity(0.8))
            .kerning(0.8)
            .padding(.bottom, 7)
    }
}
