import Foundation
import IOBluetooth

public actor BluetoothTransport {
    private let address: String
    private let channelID: BluetoothRFCOMMChannelID
    private var core: TransportCore?

    public init(address: String, channel: UInt8) { self.address = address; self.channelID = channel }

    public func connect() async throws {
        let core = TransportCore(address: address, channelID: channelID)
        self.core = core
        let rc: IOReturn = await withCheckedContinuation { cont in
            core.start { cont.resume(returning: $0) }
        }
        guard rc == kIOReturnSuccess else { throw BMAPError.notConnected }
        try await Task.sleep(nanoseconds: 500_000_000) // drain window
        core.clearInbound()
    }

    public func rawSend(_ data: Data) throws {
        guard let core else { throw BMAPError.notConnected }
        guard core.write(data) == kIOReturnSuccess else { throw BMAPError.notConnected }
    }
}
