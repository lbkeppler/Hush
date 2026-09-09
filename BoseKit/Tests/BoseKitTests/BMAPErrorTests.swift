import Testing
@testable import BoseKit

@Test func mapsErrorFrameToDeviceError() {
    let f = BMAPFrame(fblock: 0x1f, function: 0x06, op: .error, payload: [0x08])
    #expect(BMAPError.from(f) == .device(code: 0x08)) // Runtime error 8
}

@Test func nonErrorFrameIsNotAnError() {
    let f = BMAPFrame(fblock: 0x02, function: 0x02, op: .status, payload: [0x50])
    #expect(BMAPError.from(f) == nil)
}

@Test func addressesAreCorrect() {
    #expect(Addr.battery == (0x02, 0x02))
    #expect(Addr.eq == (0x01, 0x07))
    #expect(Addr.audioSettings == (0x1f, 0x0a))
    #expect(Addr.currentMode == (0x1f, 0x03))
}
