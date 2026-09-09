import Foundation
import IOBluetooth

public actor BluetoothTransport {
    private let address: String
    private let channelID: UInt8
    private var channel: IOBluetoothRFCOMMChannel?
    private var delegate: RFCOMMDelegate?
    private var inbound = Data()
    private var waiters: [(Data) -> Bool] = []   // drained in Task 11

    public init(address: String, channel: UInt8) { self.address = address; self.channelID = channel }

    public func connect() async throws {
        guard let device = IOBluetoothDevice(addressString: address) else { throw BMAPError.notConnected }
        device.performSDPQuery(nil)
        try await Task.sleep(nanoseconds: 1_500_000_000)
        let delegate = RFCOMMDelegate(
            onData: { [weak self] d in Task { await self?.appendInbound(d) } },
            onOpen: { _ in }, onClose: { })
        self.delegate = delegate
        var ch: IOBluetoothRFCOMMChannel?
        let rc = device.openRFCOMMChannelSync(&ch, withChannelID: channelID, delegate: delegate)
        guard rc == kIOReturnSuccess, let ch else { throw BMAPError.notConnected }
        self.channel = ch
        try await Task.sleep(nanoseconds: 500_000_000) // drain window
        inbound.removeAll()
    }

    private func appendInbound(_ d: Data) { inbound.append(d) }

    public func rawSend(_ data: Data) throws {
        guard let ch = channel else { throw BMAPError.notConnected }
        var bytes = [UInt8](data)
        let rc = ch.writeSync(&bytes, length: UInt16(bytes.count))
        guard rc == kIOReturnSuccess else { throw BMAPError.notConnected }
    }
}
