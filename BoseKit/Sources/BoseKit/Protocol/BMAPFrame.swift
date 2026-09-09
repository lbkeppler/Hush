import Foundation

public struct BMAPFrame: Equatable, Sendable {
    public var fblock: UInt8
    public var function: UInt8
    public var op: BMAPOperator
    public var payload: [UInt8]

    public init(fblock: UInt8, function: UInt8, op: BMAPOperator, payload: [UInt8] = []) {
        self.fblock = fblock; self.function = function; self.op = op; self.payload = payload
    }

    public var encoded: Data {
        Data([fblock, function, op.rawValue & 0x0F, UInt8(payload.count)] + payload)
    }
}

public extension BMAPFrame {
    static func parseAll(_ data: Data) -> [BMAPFrame] {
        let bytes = [UInt8](data)
        var frames: [BMAPFrame] = []
        var pos = 0
        while pos + 4 <= bytes.count {
            let length = Int(bytes[pos + 3])
            let end = pos + 4 + length
            guard end <= bytes.count else { break } // truncated → drop
            let op = BMAPOperator(rawValue: bytes[pos + 2] & 0x0F) ?? .status
            frames.append(BMAPFrame(fblock: bytes[pos], function: bytes[pos + 1],
                                    op: op, payload: Array(bytes[(pos + 4)..<end])))
            pos = end
        }
        return frames
    }
}
