import SwiftUI
import BoseKit
#if canImport(AppKit)
import AppKit
#endif

/// The menu-bar popover: a compact (~340pt) "quiet instrument" panel. The primary control
/// is the mode selector (Quiet/Aware/Immersion/Cinema); a live CNC dial is reserved for
/// devices that report `supportsLiveNoise` (none on `v1` — gen-1 gates noise control to
/// mode selection per `DeviceProfile.lonestarr`'s doc comment) and a compact EQ preset row
/// rounds out the quick controls. "Open Hush" opens the full window (Task 5).
public struct MenuBarView: View {
    public var controller: BoseController

    @Environment(\.colorScheme) private var scheme
    @Environment(\.openWindow) private var openWindow

    /// Local-only placeholder value for the CNC dial. There is no `DeviceProviding`
    /// read/write path for live noise control yet (see `BoseController.live()`'s
    /// doc comment and task-2's report) — the row only ever renders when
    /// `state.supportsLiveNoise` is true, which no current device profile sets.
    @State private var cncLevel: Double = 5

    private struct ModeDefinition: Identifiable {
        let index: Int
        let title: String
        let icon: String
        var id: Int { index }
    }

    private struct EQPreset: Identifiable {
        let name: String
        /// Bass, mid, treble — matches `EQBand.band` 0/1/2.
        let values: [Int]
        var id: String { name }
    }

    private let modes: [ModeDefinition] = [
        ModeDefinition(index: 0, title: "Quiet", icon: "moon.fill"),
        ModeDefinition(index: 1, title: "Aware", icon: "ear"),
        ModeDefinition(index: 2, title: "Immersion", icon: "waveform"),
        ModeDefinition(index: 3, title: "Cinema", icon: "tv"),
    ]

    private let eqPresets: [EQPreset] = [
        EQPreset(name: "Flat", values: [0, 0, 0]),
        EQPreset(name: "Bass boost", values: [6, 2, -2]),
        EQPreset(name: "Podcast", values: [-2, 4, 3]),
    ]

    public init(controller: BoseController) {
        self.controller = controller
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if controller.state.status == .connected {
                modeSelector

                if controller.state.supportsLiveNoise {
                    cncDial
                }

                eqPresetRow
            } else {
                connectionState
            }

            if let lastError = controller.state.lastError {
                Text(lastError)
                    .font(DT.body(11))
                    .foregroundStyle(DT.muted(scheme))
                    .lineLimit(2)
            }

            openHushButton
        }
        .padding(16)
        .frame(width: 340)
        .background(DT.ink(scheme))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(connectionColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(controller.state.name ?? "Hush")
                    .font(DT.display(15))
                    .foregroundStyle(DT.text(scheme))
                Text(statusText)
                    .font(DT.body(11))
                    .foregroundStyle(DT.muted(scheme))
            }

            Spacer()

            if let battery = controller.state.battery {
                BatteryArc(percent: battery)
            }
        }
    }

    private var connectionColor: Color {
        switch controller.state.status {
        case .connected: DT.accent(scheme)
        case .connecting: DT.muted(scheme)
        case .disconnected, .error: DT.muted(scheme).opacity(0.4)
        }
    }

    private var statusText: String {
        switch controller.state.status {
        case .connected: "Connected"
        case .connecting: "Connecting…"
        case .disconnected: "Disconnected"
        case .error(let message): message
        }
    }

    // MARK: - Mode selector (primary control)

    private var modeSelector: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Noise Control")
                    .font(DT.body(12))
                    .foregroundStyle(DT.muted(scheme))

                HStack(spacing: 8) {
                    ForEach(modes) { mode in
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
    }

    // MARK: - EQ presets

    private var eqPresetRow: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("EQ Preset")
                    .font(DT.body(12))
                    .foregroundStyle(DT.muted(scheme))

                HStack(spacing: 8) {
                    ForEach(eqPresets) { preset in
                        ModeChip(title: preset.name, active: isActive(preset)) {
                            apply(preset)
                        }
                    }
                }
            }
        }
    }

    private func isActive(_ preset: EQPreset) -> Bool {
        guard let eq = controller.state.eq, eq.count == preset.values.count else { return false }
        let sortedValues = eq.sorted { $0.band < $1.band }.map(\.value)
        return sortedValues == preset.values
    }

    private func apply(_ preset: EQPreset) {
        for (band, value) in preset.values.enumerated() {
            controller.setEQ(band: band, value: value)
        }
    }

    // MARK: - Connection / empty state

    private var connectionState: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 4) {
                switch controller.state.status {
                case .connecting:
                    Text("Connecting…")
                        .font(DT.body(13))
                        .foregroundStyle(DT.text(scheme))
                case .error(let message):
                    Text("Headphones not connected — connect in System Settings")
                        .font(DT.body(13))
                        .foregroundStyle(DT.text(scheme))
                    Text(message)
                        .font(DT.body(11))
                        .foregroundStyle(DT.muted(scheme))
                default:
                    Text("Headphones not connected — connect in System Settings")
                        .font(DT.body(13))
                        .foregroundStyle(DT.text(scheme))
                }
            }
        }
    }

    // MARK: - Open Hush

    private var openHushButton: some View {
        Button {
            openWindow(id: "main")
            #if canImport(AppKit)
            NSApp.activate(ignoringOtherApps: true)
            #endif
        } label: {
            Text("Open Hush")
                .font(DT.body(13))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .foregroundStyle(DT.text(scheme))
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(DT.surface(scheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(DT.hairline(scheme), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    MenuBarView(controller: BoseController(makeProvider: {
        struct Unavailable: Error {}
        throw Unavailable()
    }))
}
