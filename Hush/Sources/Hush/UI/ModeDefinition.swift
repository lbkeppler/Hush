import Foundation

/// A single noise-control mode/preset shown as a `ModeChip`. Shared by `MenuBarView` (the
/// popover's compact selector) and `ModesSection` (the main window's mode grid) so the
/// preset list — Quiet/Aware/Immersion/Cinema — is defined exactly once.
struct ModeDefinition: Identifiable {
    let index: Int
    let title: String
    let icon: String
    var id: Int { index }
}

/// The four built-in mode presets, in device-index order (0-3). `ModesSection` appends any
/// custom modes the device reports beyond index 3; `MenuBarView` uses this list as-is.
enum ModePresets {
    static let all: [ModeDefinition] = [
        ModeDefinition(index: 0, title: "Quiet", icon: "moon.fill"),
        ModeDefinition(index: 1, title: "Aware", icon: "ear"),
        ModeDefinition(index: 2, title: "Immersion", icon: "waveform"),
        ModeDefinition(index: 3, title: "Cinema", icon: "tv"),
    ]
}
