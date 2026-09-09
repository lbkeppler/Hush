import Testing
@testable import BoseKit

@Test func parsesSignedEQ() {
    // f6 0a 00 00 | f6 0a fe 01 | f6 0a fa 02  → bass 0, mid -2, treble -6
    let bands = BMAPParse.eq([0xf6,0x0a,0x00,0x00, 0xf6,0x0a,0xfe,0x01, 0xf6,0x0a,0xfa,0x02])
    #expect(bands == [EQBand(band: 0, value: 0), EQBand(band: 1, value: -2), EQBand(band: 2, value: -6)])
}

@Test func buildsEQBandFrameWithSignedValue() {
    let f = BMAPBuild.eqBand(value: -4, band: 0) // bass -4
    #expect(Array(f.encoded) == [0x01,0x07,0x02,0x02,0xfc,0x00])
}
