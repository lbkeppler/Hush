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
