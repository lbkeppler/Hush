import SwiftUI

/// A champagne pill toggle. On = accent-filled track with the knob at the trailing edge;
/// off = muted track with the knob at the leading edge. Tapping anywhere on the pill toggles it.
public struct HushToggle: View {
    @Binding var isOn: Bool
    @Environment(\.colorScheme) private var scheme

    private let width: CGFloat = 42
    private let height: CGFloat = 24
    private let inset: CGFloat = 3

    public init(isOn: Binding<Bool>) {
        self._isOn = isOn
    }

    public var body: some View {
        let knobDiameter = height - inset * 2
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(isOn ? DT.accent(scheme) : DT.muted(scheme).opacity(0.35))
            .overlay(
                RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                    .strokeBorder(DT.hairline(scheme), lineWidth: isOn ? 0 : 1)
            )
            .frame(width: width, height: height)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(DT.surface(scheme))
                    .frame(width: knobDiameter, height: knobDiameter)
                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
                    .padding(.horizontal, inset)
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.8), value: isOn)
            .contentShape(Rectangle())
            .onTapGesture {
                isOn.toggle()
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(isOn ? "On" : "Off")
    }
}

#Preview {
    VStack(spacing: 16) {
        HushToggle(isOn: .constant(true))
        HushToggle(isOn: .constant(false))
    }
    .padding()
}
