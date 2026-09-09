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
    private var basebandConnected = false

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

            // Explicitly bring up the baseband link and wait for it before opening RFCOMM.
            // Matches the reference tool's (bosectl) proven connect sequence — on this
            // device, skipping straight to openRFCOMMChannelSync without this step has
            // been observed to fail with kIOReturnError.
            _ = device?.openConnection(self) // async; delivers connectionComplete(_:status:) on this thread's run loop
            let bbDeadline = Date().addingTimeInterval(5)
            while Date() < bbDeadline {
                self.lock.lock(); let ok = self.basebandConnected; self.lock.unlock()
                if ok { break }
                rl.run(mode: .default, before: Date().addingTimeInterval(0.1))
            }
            // Don't fail hard on a baseband-wait timeout: some stacks bring up the
            // baseband link implicitly as part of the RFCOMM open. The RFCOMM open's
            // IOReturn below remains the actual source of truth for success.

            var ch: IOBluetoothRFCOMMChannel?
            let rc = device?.openRFCOMMChannelSync(&ch, withChannelID: self.channelID, delegate: self) ?? kIOReturnError
            self.lock.lock(); self.openStatus = rc; self.opened = (rc == kIOReturnSuccess); self.channel = ch; self.lock.unlock()
            completion(rc)
            // Keep pumping so delegate callbacks are delivered for the life of the connection.
            while true {
                self.lock.lock(); let th = self.thread; self.lock.unlock()
                guard let th, !th.isCancelled else { break }
                rl.run(mode: .default, before: Date().addingTimeInterval(0.2))
            }
        }
        t.name = "BoseKit.RFCOMM"; t.stackSize = 1 << 20
        lock.lock(); self.thread = t; lock.unlock()
        t.start()
    }

    // Delegate callbacks run on the dedicated thread, in order → append synchronously under the lock.
    func rfcommChannelData(_ ch: IOBluetoothRFCOMMChannel!, data ptr: UnsafeMutableRawPointer!, length len: Int) {
        lock.lock(); inbound.append(Data(bytes: ptr, count: len)); lock.unlock()
    }
    func rfcommChannelClosed(_ ch: IOBluetoothRFCOMMChannel!) {
        lock.lock(); opened = false; channel = nil; lock.unlock()
    }

    // Async callback target for `device?.openConnection(self)` (informal
    // IOBluetoothDeviceAsyncCallbacks selector, invoked via the ObjC runtime — not
    // formally adopted as a protocol since it also requires remoteNameRequestComplete
    // and sdpQueryComplete stubs we don't use). Delivered on this thread's run loop.
    @objc func connectionComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        lock.lock(); basebandConnected = (status == kIOReturnSuccess); lock.unlock()
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
    func stop() {
        lock.lock()
        thread?.cancel()
        thread = nil
        lock.unlock()
    }
}
