import SwiftUI
import MaskCore

struct VoiceRow: View {
    let voice: Voice
    let isSelected: Bool
    let isFocused: Bool
    let isAlt: Bool
    let isModified: Bool
    let showModifiedColumn: Bool
    let tagBackground: Color

    var body: some View {
        HStack(spacing: 0) {
            Text(String(format: "%03d", voice.index + 1))
                .font(Theme.smallMono)
                .frame(width: 36, alignment: .leading)
                .foregroundStyle(isSelected && isFocused ? Color.white.opacity(0.85) : .secondary)
            Text(voice.displayName)
                .font(Theme.monoFont)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .foregroundStyle(isSelected && isFocused ? .white : .primary)
            // Tag column reserved for a future category field; for now empty.
            Spacer().frame(width: 36)
            if showModifiedColumn {
                Circle()
                    .fill(isModified ? (isSelected && isFocused ? .white : Theme.modifiedDot) : .clear)
                    .frame(width: 6, height: 6)
                    .frame(width: 14)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: Theme.rowHeight)
        .background(rowBackground)
    }

    private var rowBackground: Color {
        if isSelected && isFocused { return .accentColor }
        if isSelected               { return Color.accentColor.opacity(0.18) }
        if isAlt                    { return Color(white: 0.98) }
        return .clear
    }
}
