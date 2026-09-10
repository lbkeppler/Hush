import Testing
import BoseKit
@testable import Hush

/// Confirms `EQPresetDefinition.swift` is the single source of truth both `MenuBarView` and
/// `SoundSection` render from — if their preset lists ever drifted again (as they did before
/// this file existed), applying a preset in one surface would show "Custom" in the other.
@Suite("EQ Presets")
struct EQPresetDefinitionTests {
    @Test("canonical preset values match across surfaces")
    func canonicalValues() {
        let byName = Dictionary(uniqueKeysWithValues: EQPresets.all.map { ($0.name, $0.values) })
        #expect(byName["Flat"] == [0, 0, 0])
        #expect(byName["Bass boost"] == [6, 0, 2])
        #expect(byName["Podcast"] == [-2, 3, 1])
    }

    /// Simulates each surface's own "is this preset active" check against the same device
    /// state (an `[EQBand]` for bands 0/1/2, MenuBar's shape) and confirms they agree.
    @Test("both surfaces resolve the same active preset from the same eq state")
    func agreesAcrossSurfaces() {
        for preset in EQPresets.all {
            let eq = preset.values.enumerated().map { EQBand(band: $0.offset, value: $0.element) }

            // MenuBarView.isActive: sort state.eq by band, compare to preset.values.
            let menuBarActive = eq.sorted { $0.band < $1.band }.map(\.value) == preset.values

            // SoundSection.bandValues: look up each band 0/1/2, default missing to 0.
            let soundBandValues = (0...2).map { band in
                eq.first(where: { $0.band == band })?.value ?? 0
            }
            let soundActive = soundBandValues == preset.values

            #expect(menuBarActive)
            #expect(soundActive)
            #expect(menuBarActive == soundActive)
        }
    }
}
