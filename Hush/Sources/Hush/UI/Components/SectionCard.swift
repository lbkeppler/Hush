import SwiftUI

/// A rounded surface card (radius 16) with a hairline border and internal padding,
/// used to group related content into a single "quiet instrument" panel.
public struct SectionCard<Content: View>: View {
    private let content: Content

    @Environment(\.colorScheme) private var scheme

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(DT.surface(scheme))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(DT.hairline(scheme), lineWidth: 1)
            )
    }
}

#Preview {
    SectionCard {
        VStack(alignment: .leading, spacing: 8) {
            Text("Noise Control")
            Text("Quiet, Aware, Immersion")
                .foregroundStyle(.secondary)
        }
    }
    .padding()
}
