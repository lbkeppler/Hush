import Testing
import Foundation
@testable import BoseKit

@Test func parsesSingleStatusFrame() {
    // Battery STATUS: 02 02 03 04 50 ff ff 00
    let frames = BMAPFrame.parseAll(Data([0x02,0x02,0x03,0x04,0x50,0xff,0xff,0x00]))
    #expect(frames.count == 1)
    #expect(frames[0].fblock == 0x02 && frames[0].function == 0x02)
    #expect(frames[0].op == .status)
    #expect(frames[0].payload == [0x50,0xff,0xff,0x00])
}

@Test func splitsConcatenatedFrames() {
    // mode STATUS (1f 03 03 01 01) followed by battery STATUS
    let data = Data([0x1f,0x03,0x03,0x01,0x01, 0x02,0x02,0x03,0x04,0x50,0xff,0xff,0x00])
    let frames = BMAPFrame.parseAll(data)
    #expect(frames.count == 2)
    #expect(frames[0].payload == [0x01])
    #expect(frames[1].payload == [0x50,0xff,0xff,0x00])
}

@Test func dropsTruncatedTrailingFrame() {
    // second frame claims length 4 but only 1 byte follows
    let data = Data([0x1f,0x03,0x03,0x01,0x01, 0x02,0x02,0x03,0x04,0x50])
    let frames = BMAPFrame.parseAll(data)
    #expect(frames.count == 1)
}
