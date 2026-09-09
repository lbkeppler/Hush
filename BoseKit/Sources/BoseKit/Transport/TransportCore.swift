import Foundation
import IOBluetooth

final class TransportCore: NSObject, IOBluetoothRFCOMMChannelDelegate, @unchecked Sendable {
    private let address: String
    private let channelID: BluetoothRFCOMMChannelID
    private var channel: IOBluetoothRFCOMMChannel?
    private var thread: Thread?
    private let lock = NSLock()
    private var inbound = Data()
    private(set) var openStatus: IOReturn = kIOReturnError
    private var opened = false

    init(address: String, channelID: BluetoothRFCOMMChannelID) {
        self.address = address; self.channelID = channelID
    }

    /// Starts the dedicated thread, connects, and calls `completion(IOReturn)` when the channel open resolves.
    func start(completion: @escaping (IOReturn) -> Void) {
        let t = Thread { [weak self] in
            guard let self else { return }
            let rl = RunLoop.current
            rl.add(NSMachPort(), forMode: .default) // keep the run loop alive with a source
            let device = IOBluetoothDevice(addressString: self.address)
            device?.performSDPQuery(nil)
            rl.run(until: Date().addingTimeInterval(1.5)) // let SDP register
            var ch: IOBluetoothRFCOMMChannel?
            let rc = device?.openRFCOMMChannelSync(&ch, withChannelID: self.channelID, delegate: self) ?? kIOReturnError
            self.lock.lock(); self.openStatus = rc; self.opened = (rc == kIOReturnSuccess); self.channel = ch; self.lock.unlock()
            completion(rc)
            // Keep pumping so delegate callbacks are delivered for the life of the connection.
            while let th = self.thread, !th.isCancelled {
                rl.run(mode: .default, before: Date().addingTimeInterval(0.2))
            }
        }
        t.name = "BoseKit.RFCOMM"; t.stackSize = 1 << 20
        self.thread = t; t.start()
    }

    // Delegate callbacks run on the dedicated thread, in order → append synchronously under the lock.
    func rfcommChannelData(_ ch: IOBluetoothRFCOMMChannel!, data ptr: UnsafeMutableRawPointer!, length len: Int) {
        lock.lock(); inbound.append(Data(bytes: ptr, count: len)); lock.unlock()
    }
    func rfcommChannelClosed(_ ch: IOBluetoothRFCOMMChannel!) {
        lock.lock(); opened = false; channel = nil; lock.unlock()
    }

    var isOpen: Bool { lock.lock(); defer { lock.unlock() }; return opened }
    func snapshotInbound() -> Data { lock.lock(); defer { lock.unlock() }; return inbound }
    func clearInbound() { lock.lock(); inbound.removeAll(); lock.unlock() }
    func write(_ data: Data) -> IOReturn {
        lock.lock(); let ch = channel; lock.unlock()
        guard let ch else { return kIOReturnNotOpen }
        var bytes = [UInt8](data)
        return ch.writeSync(&bytes, length: UInt16(bytes.count))
    }
    func stop() { thread?.cancel(); thread = nil }
}
