import SwiftUI
import BoseKit

/// Draws a smooth curve through up to three EQ band points (bass/mid/treble), a dashed
/// 0 dB midline, and champagne draggable dots for each band. Dragging a dot maps its Y
/// position back to an `Int` in -10...10 and reports it via `onEdit(band, value)`.
public struct EQCurveView: View {
    let bands: [EQBand]
    let onEdit: (Int, Int) -> Void

    @Environment(\.colorScheme) private var scheme

    private let padding: CGFloat = 14
    private let dotDiameter: CGFloat = 14
    private let xFractions: [CGFloat] = [0.15, 0.5, 0.85]

    public init(bands: [EQBand], onEdit: @escaping (Int, Int) -> Void) {
        self.bands = bands
        self.onEdit = onEdit
    }

    public var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let points = pointPositions(in: size)

            ZStack {
                // 0 dB dashed midline
                Path { path in
                    let midY = self.midY(in: size)
                    path.move(to: CGPoint(x: 0, y: midY))
                    path.addLine(to: CGPoint(x: size.width, y: midY))
                }
                .stroke(DT.hairline(scheme), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                if points.count >= 2 {
                    smoothPath(through: points)
                        .stroke(DT.accent(scheme), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }

                ForEach(Array(bands.enumerated()), id: \.offset) { index, band in
                    let point = points[index]
                    Circle()
                        .fill(DT.accent(scheme))
                        .frame(width: dotDiameter, height: dotDiameter)
                        .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                        .position(point)
                        .focusable()
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named("eqCurve"))
                                .onChanged { drag in
                                    let value = valueFor(y: drag.location.y, in: size)
                                    onEdit(band.band, value)
                                }
                        )
                        .accessibilityLabel(bandLabel(index))
                        .accessibilityValue("\(band.value)")
                }
            }
            .coordinateSpace(name: "eqCurve")
        }
    }

    private func bandLabel(_ index: Int) -> String {
        ["Bass", "Mid", "Treble"][safe: index] ?? "Band \(index)"
    }

    // MARK: - Geometry

    private func midY(in size: CGSize) -> CGFloat {
        let usable = size.height - padding * 2
        return padding + usable / 2
    }

    private func yFor(_ value: Int, in size: CGSize) -> CGFloat {
        let usable = size.height - padding * 2
        let clampedValue = CGFloat(min(max(value, -10), 10))
        return midY(in: size) - (clampedValue / 10) * (usable / 2)
    }

    private func valueFor(y: CGFloat, in size: CGSize) -> Int {
        let usable = size.height - padding * 2
        guard usable > 0 else { return 0 }
        let raw = -(y - midY(in: size)) / (usable / 2) * 10
        return Int(raw.rounded()).clamped(to: -10...10)
    }

    private func xFor(_ index: Int, in size: CGSize) -> CGFloat {
        let fraction = xFractions[safe: index] ?? 0.5
        return size.width * fraction
    }

    private func pointPositions(in size: CGSize) -> [CGPoint] {
        bands.indices.map { i in
            CGPoint(x: xFor(i, in: size), y: yFor(bands[i].value, in: size))
        }
    }

    /// A Catmull-Rom spline through `points`, converted to cubic Bézier segments so the
    /// curve is smooth and passes through every point (rather than merely approximating them).
    private func smoothPath(through points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 1 else { return path }

        var extended = points
        extended.insert(points[0], at: 0)
        extended.append(points[points.count - 1])

        for i in 1..<(extended.count - 2) {
            let p0 = extended[i - 1]
            let p1 = extended[i]
            let p2 = extended[i + 1]
            let p3 = extended[i + 2]
            let control1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let control2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: control1, control2: control2)
        }
        return path
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview {
    EQCurveView(
        bands: [EQBand(band: 0, value: 4), EQBand(band: 1, value: -2), EQBand(band: 2, value: 6)],
        onEdit: { _, _ in }
    )
    .frame(height: 140)
    .padding()
}
