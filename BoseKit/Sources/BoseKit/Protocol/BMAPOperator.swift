public enum BMAPOperator: UInt8, Sendable {
    case set = 0, get = 1, setGet = 2, status = 3
    case error = 4, start = 5, result = 6, processing = 7
}
