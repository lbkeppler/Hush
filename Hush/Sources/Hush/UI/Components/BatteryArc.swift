import SwiftUI

/// A slim ring gauge showing battery percent, with the number set in `DT.display`.
/// Champagne (`DT.accent`) fill — battery level reads as a live/active state.
public struct BatteryArc: View {
    let percent: Int

    @Environment(\.colorScheme) private var scheme

    public init(percent: Int) {
        self.percent = percent
    }

    private var clamped: Double {
        Double(min(max(percent, 0), 100)) / 100
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(DT.hairline(scheme), lineWidth: 3)
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(
                    DT.accent(scheme),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: clamped)

            Text("\(min(max(percent, 0), 100))")
                .font(DT.display(13))
                .foregroundStyle(DT.text(scheme))
        }
        .frame(width: 34, height: 34)
        .accessibilityLabel("Battery")
        .accessibilityValue("\(percent) percent")
    }
}

#Preview {
    HStack(spacing: 16) {
        BatteryArc(percent: 82)
        BatteryArc(percent: 34)
        BatteryArc(percent: 5)
    }
    .padding()
}
