import SwiftUI

/// A tappable card representing a single mode/preset choice.
///
/// Active = accent-tinted background + accent border + accent text/icon (the one place
/// champagne is used for a "live" state). Inactive = quiet surface + hairline + text.
public struct ModeChip: View {
    let title: String
    let systemIcon: String?
    let active: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var scheme

    public init(
        title: String,
        systemIcon: String? = nil,
        active: Bool,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemIcon = systemIcon
        self.active = active
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                if let systemIcon {
                    Image(systemName: systemIcon)
                        .font(.system(size: 16, weight: .medium))
                }
                Text(title)
                    .font(DT.body(12))
                    .lineLimit(1)
            }
            .foregroundStyle(active ? DT.accent(scheme) : DT.text(scheme))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(active ? DT.accent(scheme).opacity(0.14) : DT.surface(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(active ? DT.accent(scheme) : DT.hairline(scheme), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview {
    HStack(spacing: 12) {
        ModeChip(title: "Quiet", systemIcon: "moon.fill", active: true) {}
        ModeChip(title: "Aware", systemIcon: "ear", active: false) {}
        ModeChip(title: "Immersion", systemIcon: "waveform", active: false) {}
    }
    .padding()
}
