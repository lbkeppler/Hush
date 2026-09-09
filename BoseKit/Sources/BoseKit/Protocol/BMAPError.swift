public enum BMAPError: Error, Equatable, Sendable {
    case device(code: UInt8)
    case timeout
    case notConnected
    case unexpectedResponse
    case unsupported

    public static func from(_ frame: BMAPFrame) -> BMAPError? {
        guard frame.op == .error else { return nil }
        return .device(code: frame.payload.first ?? 0)
    }
}
