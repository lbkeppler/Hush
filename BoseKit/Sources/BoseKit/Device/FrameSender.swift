import Foundation

/// Abstraction over "send a BMAP frame, get frames back" — implemented by the real
/// `BluetoothTransport` and by a mock in tests, so `BoseDevice` never touches IOBluetooth.
public protocol FrameSender: Sendable {
    func send(_ frame: BMAPFrame, drain: Bool, timeout: TimeInterval) async throws -> [BMAPFrame]
}

extension BluetoothTransport: FrameSender {}
