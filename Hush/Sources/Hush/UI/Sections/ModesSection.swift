import SwiftUI

/// The Now/Modes section — the hero of the main window. Shows the current mode large, then
/// every mode (the four presets plus any custom entries from `state.modeNames` beyond
/// index 3) as selectable cards wired to `controller.switchMode(index:)`. When the device
/// reports `supportsLiveNoise` a CNC dial appears here; otherwise a short note explains that
/// noise control lives inside each mode on this model. `lastError` is surfaced subtly below.
public struct ModesSection: View {
    public var controller: BoseController

    @Environment(\.colorScheme) private var scheme

    /// Local-only placeholder value for the CNC dial — mirrors `MenuBarView.cncLevel`.
    /// There is no `DeviceProviding` read/write path for live noise control yet; this row
    /// only renders when `state.supportsLiveNoise` is true, which no current device profile
    /// sets (gen-1 gates noise control to mode selection).
    @State private var cncLevel: Double = 5

    /// Shared with `MenuBarView` — see `ModeDefinition.swift`.
    private let presets: [ModeDefinition] = ModePresets.all

    public init(controller: BoseController) {
        self.controller = controller
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                hero
                modeGrid

                if controller.state.supportsLiveNoise {
                    cncDial
                } else {
                    liveNoiseNote
                }

                if let lastError = controller.state.lastError {
                    Text(lastError)
                        .font(DT.body(11))
                        .foregroundStyle(DT.muted(scheme))
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Now")
                .font(DT.body(12))
                .foregroundStyle(DT.muted(scheme))

            Text(currentModeName)
                .font(DT.display(40))
                .foregroundStyle(DT.text(scheme))
        }
    }

    private var currentModeName: String {
        guard let index = controller.state.currentModeIndex else { return "—" }
        if let named = controller.state.modeNames?[index] { return named }
        if let preset = presets.first(where: { $0.index == index }) { return preset.title }
        return "Mode \(index)"
    }

    // MARK: - Mode cards

    /// The four presets plus any custom modes the device reports beyond index 3.
    private var allModes: [ModeDefinition] {
        var modes = presets
        if let modeNames = controller.state.modeNames {
            let extraIndices = modeNames.keys.filter { $0 > 3 }.sorted()
            modes += extraIndices.map { index in
                ModeDefinition(
                    index: index,
                    title: modeNames[index] ?? "Mode \(index)",
                    icon: "slider.horizontal.below.rectangle"
                )
            }
        }
        return modes
    }

    private var modeGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 12)], spacing: 12) {
            ForEach(allModes) { mode in
                ModeChip(
                    title: displayName(for: mode),
                    systemIcon: mode.icon,
                    active: controller.state.currentModeIndex == mode.index
                ) {
                    Task { await controller.switchMode(index: mode.index) }
                }
            }
        }
    }

    private func displayName(for mode: ModeDefinition) -> String {
        controller.state.modeNames?[mode.index] ?? mode.title
    }

    // MARK: - CNC dial (feature-gated, `supportsLiveNoise` only)

    private var cncDial: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Noise Cancellation")
                    .font(DT.body(12))
                    .foregroundStyle(DT.muted(scheme))
                Slider(value: $cncLevel, in: 0...10, step: 1)
                    .tint(DT.accent(scheme))
            }
        }
        .frame(maxWidth: 360)
    }

    private var liveNoiseNote: some View {
        Text("Noise settings live inside each mode on this model.")
            .font(DT.body(12))
            .foregroundStyle(DT.muted(scheme))
    }
}

#Preview {
    ModesSection(controller: BoseController(makeProvider: {
        struct Unavailable: Error {}
        throw Unavailable()
    }))
}
