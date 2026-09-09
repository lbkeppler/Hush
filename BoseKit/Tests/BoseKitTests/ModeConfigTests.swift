import Testing
@testable import BoseKit

@Test func parses48ByteModeConfig() {
    var p = [UInt8](repeating: 0, count: 48)
    p[0] = 5                 // index
    p[3] = 1                 // editable
    p[4] = 1                 // configured
    for (i, b) in Array("Focus".utf8).enumerated() { p[6 + i] = b }
    p[42] = 3; p[44] = 1; p[45] = 0; p[47] = 1 // cnc=3 spatial=room anc=on
    let c = BMAPParse.modeConfig48(p)
    #expect(c.index == 5 && c.name == "Focus" && c.editable && c.configured)
    #expect(c.cnc == 3 && c.spatial == 1 && c.anc == 1)
}

@Test func builds40ByteModeConfigWithPaddedName() {
    let c = ModeConfig(index: 5, name: "Focus", editable: true, configured: true,
                       cnc: 3, autoCNC: 0, spatial: 1, wind: 0, anc: 1)
    let f = BMAPBuild.modeConfig40(c)
    let p = f.payload
    #expect(f.fblock == 0x1f && f.function == 0x06 && f.op == .setGet)
    #expect(p.count == 40)
    #expect(p[0] == 5)
    #expect(Array(p[3..<8]) == Array("Focus".utf8))
    #expect(p[8] == 0)          // null padding begins
    #expect(p[35] == 3 && p[37] == 1 && p[39] == 1) // cnc, spatial, anc
}

@Test func handlesEmptyPayloadWithoutCrashing() {
    let c = BMAPParse.modeConfig48([])
    #expect(c.index == 0 && c.name == "" && !c.editable && !c.configured)
    #expect(c.cnc == 0 && c.anc == 0)
}

@Test func handlesShortPayloadWithoutCrashing() {
    let c = BMAPParse.modeConfig48([5, 0, 0, 1, 1])  // 5 bytes: index=5, editable=1 @ [3], configured=1 @ [4]
    #expect(c.index == 5 && c.name == "" && c.editable && c.configured)
    #expect(c.cnc == 0 && c.anc == 0)  // beyond payload, should be 0
}
