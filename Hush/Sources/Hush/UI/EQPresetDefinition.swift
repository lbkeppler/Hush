import Foundation

/// A single EQ preset shown as a `ModeChip`. Shared by `MenuBarView` (the popover's compact
/// preset row) and `SoundSection` (the main window's EQ preset chips) so the preset list —
/// Flat/Bass boost/Podcast — and their band values are defined exactly once. Without this,
/// the two surfaces could drift (and previously did): applying a preset in one would leave
/// the other reading "Custom" for the same device state.
struct EQPreset: Identifiable {
    let name: String
    /// Bass, mid, treble — matches `EQBand.band` 0/1/2.
    let values: [Int]
    var id: String { name }
}

/// The three built-in EQ presets, canonical values in `[bass, mid, treble]` order.
enum EQPresets {
    static let all: [EQPreset] = [
        EQPreset(name: "Flat", values: [0, 0, 0]),
        EQPreset(name: "Bass boost", values: [6, 0, 2]),
        EQPreset(name: "Podcast", values: [-2, 3, 1]),
    ]
}
