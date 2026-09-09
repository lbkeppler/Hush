import Testing
@testable import BoseKit

@Test func buildsGet() {
    #expect(Array(BMAPBuild.get(Addr.battery).encoded) == [0x02,0x02,0x01,0x00])
}

@Test func buildsSetName() {
    #expect(Array(BMAPBuild.setName("Fargo").encoded) == [0x01,0x02,0x02,0x05,0x46,0x61,0x72,0x67,0x6f])
}

@Test func buildsSetModeAware() {
    #expect(Array(BMAPBuild.setMode(index: 1, announce: false).encoded) == [0x1f,0x03,0x05,0x02,0x01,0x00])
}

@Test func buildsToggleMultipointOff() {
    #expect(Array(BMAPBuild.toggle(Addr.multipoint, on: false).encoded) == [0x01,0x0a,0x02,0x01,0x00])
}

@Test func buildsSidetoneMedium() {
    #expect(Array(BMAPBuild.setSidetone(level: 2).encoded) == [0x01,0x0b,0x02,0x02,0x01,0x02])
}

@Test func buildsListProfilesStart() {
    #expect(Array(BMAPBuild.listProfiles().encoded) == [0x1f,0x01,0x05,0x00])
}

@Test func buildsSetButtonMapping() {
    let f = BMAPBuild.setButton(ButtonMapping(button: 1, event: 2, action: 3))
    #expect(Array(f.encoded) == [0x01,0x09,0x02,0x03,0x01,0x02,0x03])
}

// MARK: - Integer clamping (out-of-range inputs must clamp, not trap)
//
// These builders are driven by a UI slider that can hand them any Int; `UInt8(x)`
// traps on negative values or values > 255, which would crash the whole process.
// `UInt8(clamping:)` must be used instead everywhere below.

@Test func setSidetoneClampsOutOfRangeLevelInsteadOfTrapping() {
    let f = BMAPBuild.setSidetone(level: 999)
    #expect(f.payload.last == 0xff) // clamped to 255, not a trap
}

@Test func setSidetoneClampsNegativeLevelInsteadOfTrapping() {
    let f = BMAPBuild.setSidetone(level: -5)
    #expect(f.payload.last == 0x00) // clamped to 0, not a trap
}

@Test func setModeClampsOutOfRangeIndexInsteadOfTrapping() {
    let f = BMAPBuild.setMode(index: 999, announce: false)
    #expect(f.payload.first == 0xff)
}

@Test func audioSettingsClampsOutOfRangeFieldsInsteadOfTrapping() {
    let s = AudioSettings(cnc: 999, autoCNC: -1, spatial: 300, wind: -100, anc: 256)
    let f = BMAPBuild.audioSettings(s)
    #expect(f.payload == [0xff, 0x00, 0xff, 0x00, 0xff])
}

@Test func setButtonClampsOutOfRangeFieldsInsteadOfTrapping() {
    let f = BMAPBuild.setButton(ButtonMapping(button: -1, event: 999, action: 300))
    #expect(f.payload == [0x00, 0xff, 0xff])
}
