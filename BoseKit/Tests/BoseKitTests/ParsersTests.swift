import Testing
@testable import BoseKit

@Test func parsesBattery()  { #expect(BMAPParse.battery([0x50,0xff,0xff,0x00]) == 80) }
@Test func parsesFirmware() { #expect(BMAPParse.firmware(Array("1.6.7".utf8)) == "1.6.7") }
@Test func parsesName()     { #expect(BMAPParse.name([0x00,0x46,0x61,0x72,0x67,0x6f]) == "Fargo") }
@Test func parsesModeIndex(){ #expect(BMAPParse.modeIndex([0x01]) == 1) }
@Test func parsesCNC() {
    let r = BMAPParse.cnc([0x0b,0x00,0x03]); #expect(r.current == 0 && r.max == 10)
}
@Test func parsesMultipoint() { #expect(BMAPParse.multipointEnabled([0x07]) == true) }
@Test func parsesSidetone()   { #expect(BMAPParse.sidetone([0x01,0x02,0x0f]) == 2) } // medium
@Test func parsesBoolByte0()  { #expect(BMAPParse.boolByte0([0x01]) == true) }
@Test func parsesVoicePromptsEnabledBit5AndLanguage() {
    let r = BMAPParse.voicePrompts([0x23]) // bit5 set + language 3
    #expect(r.enabled == true && r.language == 3)
}
@Test func parsesVoicePromptsDisabled() {
    let r = BMAPParse.voicePrompts([0x03]) // language 3, bit5 clear
    #expect(r.enabled == false && r.language == 3)
}
@Test func parsesButtonMapping() {
    #expect(BMAPParse.buttonMapping([1,2,3]) == ButtonMapping(button: 1, event: 2, action: 3))
}
