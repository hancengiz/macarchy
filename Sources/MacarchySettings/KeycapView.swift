import MacarchySettingsCore
import SwiftUI

struct KeycapView: View {
    let chord: String
    var prominent = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(ChordGlyph.glyphs(chord: chord).enumerated()), id: \.offset) { _, glyph in
                Text(glyph)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(prominent ? Color.accentColor.opacity(0.18) : Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
            }
        }
    }
}
