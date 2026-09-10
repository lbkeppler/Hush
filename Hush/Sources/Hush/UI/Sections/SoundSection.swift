import SwiftUI
import BoseKit

/// The Sound/EQ section: an interactive three-band curve (bass/mid/treble) with live value
/// readouts, plus preset chips (Flat / Bass boost / Podcast / Custom). Dragging a point on
/// the curve calls `controller.setEQ(band:value:)`, which the controller debounces before
/// writing to the device. "Custom" lights up whenever the live bands don't match any of the
/// three named presets — it isn't itself tappable.
public struct SoundSection: View {
    public var controller: BoseController

    @Environment(\.colorScheme) private var scheme

    /// Shared with `MenuBarView` — see `EQPresetDefinition.swift`.
    private let presets: [EQPreset] = EQPresets.all

    public init(controller: BoseController) {
        self.controller = controller
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                SectionCard {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Equalizer")
                            .font(DT.body(12))
                            .foregroundStyle(DT.muted(scheme))

                        EQCurveView(bands: bands, onEdit: { band, value in
                            controller.setEQ(band: band, value: value)
                        })
                        .frame(height: 160)

                        valueLabels
                    }
                }

                presetRow
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Bands

    /// Bass/mid/treble values (band 0/1/2), defaulting any band the device hasn't reported
    /// yet to 0 and always in a fixed 0-1-2 order regardless of `state.eq`'s order.
    private var bandValues: [Int] {
        (0...2).map { band in
            controller.state.eq?.first(where: { $0.band == band })?.value ?? 0
        }
    }

    private var bands: [EQBand] {
        bandValues.enumerated().map { EQBand(band: $0.offset, value: $0.element) }
    }

    // MARK: - Value labels

    private var valueLabels: some View {
        HStack(spacing: 0) {
            valueLabel(title: "Bass", value: bandValues[0])
            Spacer()
            valueLabel(title: "Mid", value: bandValues[1])
            Spacer()
            valueLabel(title: "Treble", value: bandValues[2])
        }
    }

    private func valueLabel(title: String, value: Int) -> some View {
        VStack(spacing: 4) {
            Text(formatted(value))
                .font(DT.display(20))
                .foregroundStyle(DT.text(scheme))
            Text(title)
                .font(DT.body(11))
                .foregroundStyle(DT.muted(scheme))
        }
        .frame(maxWidth: .infinity)
    }

    private func formatted(_ value: Int) -> String {
        value > 0 ? "+\(value)" : "\(value)"
    }

    // MARK: - Presets

    private var presetRow: some View {
        HStack(spacing: 12) {
            ForEach(presets) { preset in
                ModeChip(title: preset.name, active: bandValues == preset.values) {
                    apply(preset)
                }
            }

            ModeChip(title: "Custom", active: isCustom) {}
                .allowsHitTesting(false)
        }
    }

    private var isCustom: Bool {
        !presets.contains { $0.values == bandValues }
    }

    private func apply(_ preset: EQPreset) {
        for (band, value) in preset.values.enumerated() {
            controller.setEQ(band: band, value: value)
        }
    }
}

#Preview {
    SoundSection(controller: BoseController(makeProvider: {
        struct Unavailable: Error {}
        throw Unavailable()
    }))
}
