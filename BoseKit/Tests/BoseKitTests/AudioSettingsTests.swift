import Testing
@testable import BoseKit

@Test func parsesAudioSettings() {
    let s = BMAPParse.audioSettings([0x00,0x00,0x02,0x00,0x01]) // cnc0 spatial=head wind0 anc on
    #expect(s == AudioSettings(cnc: 0, autoCNC: 0, spatial: 2, wind: 0, anc: 1))
}

@Test func buildsAudioSettings() {
    let f = BMAPBuild.audioSettings(AudioSettings(cnc: 0, autoCNC: 0, spatial: 0, wind: 0, anc: 1))
    #expect(Array(f.encoded) == [0x1f,0x0a,0x02,0x05,0x00,0x00,0x00,0x00,0x01])
}
