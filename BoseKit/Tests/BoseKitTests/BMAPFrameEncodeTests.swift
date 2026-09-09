import Testing
import Foundation
@testable import BoseKit

@Test func encodesGetRequestWithNoPayload() {
    let f = BMAPFrame(fblock: 0x02, function: 0x02, op: .get)
    #expect(Array(f.encoded) == [0x02, 0x02, 0x01, 0x00])
}

@Test func encodesSetGetWithPayload() {
    let f = BMAPFrame(fblock: 0x01, function: 0x07, op: .setGet, payload: [0x01, 0x00])
    #expect(Array(f.encoded) == [0x01, 0x07, 0x02, 0x02, 0x01, 0x00])
}
