import Foundation
import IOBluetooth

public actor BluetoothTransport {
    private let address: String
    private let channelID: BluetoothRFCOMMChannelID
    private var core: TransportCore?

    public init(address: String, channel: UInt8) { self.address = address; self.channelID = channel }

    public var isConnected: Bool { core?.isOpen ?? false }

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

    public func disconnect() {
        core?.stop()
        core = nil
    }

    /// Re-establishes the RFCOMM channel if it isn't currently open.
    public func ensureConnected() async throws {
        guard !isConnected else { return }
        disconnect()
        try await Task.sleep(nanoseconds: 300_000_000) // short backoff before reconnect
        try await connect()
    }

    public func rawSend(_ data: Data) throws {
        guard let core else { throw BMAPError.notConnected }
        guard core.write(data) == kIOReturnSuccess else { throw BMAPError.notConnected }
    }

    public func send(_ frame: BMAPFrame, drain: Bool = false, timeout: TimeInterval = 3) async throws -> [BMAPFrame] {
        try await ensureConnected()
        guard let core else { throw BMAPError.notConnected }
        core.clearInbound()
        try rawSend(frame.encoded)
        try await Task.sleep(nanoseconds: 200_000_000) // required post-send delay
        let deadline = Date().addingTimeInterval(timeout)
        while core.snapshotInbound().isEmpty && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        if core.snapshotInbound().isEmpty { throw BMAPError.timeout }
        if drain {
            var last = -1
            while last != core.snapshotInbound().count {
                last = core.snapshotInbound().count
                try await Task.sleep(nanoseconds: 500_000_000) // idle window
            }
        }
        return BMAPFrame.parseAll(core.snapshotInbound())
    }
}

public extension BluetoothTransport {
    /// Probes RFCOMM channels in order (deduped, `preferred` first) and returns the first transport
    /// that answers a firmware GET, leaving that transport connected.
    static func discover(address: String, preferred: UInt8 = 2) async throws -> BluetoothTransport {
        var seen = Set<UInt8>()
        let channels = [preferred, 2, 8, 9].filter { seen.insert($0).inserted }
        for ch in channels {
            let transport = BluetoothTransport(address: address, channel: ch)
            do {
                try await transport.connect()
                let reply = try await transport.send(BMAPBuild.get(Addr.firmware), timeout: 2)
                if reply.contains(where: { ($0.fblock, $0.function) == Addr.firmware }) {
                    return transport
                }
            } catch {
                // try the next candidate channel
            }
            await transport.disconnect()
        }
        throw BMAPError.notConnected
    }
}
