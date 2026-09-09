import Foundation
import IOBluetooth

final class RFCOMMDelegate: NSObject, IOBluetoothRFCOMMChannelDelegate, @unchecked Sendable {
    let onData: (Data) -> Void
    let onOpen: (IOReturn) -> Void
    let onClose: () -> Void
    init(onData: @escaping (Data) -> Void, onOpen: @escaping (IOReturn) -> Void, onClose: @escaping () -> Void) {
        self.onData = onData; self.onOpen = onOpen; self.onClose = onClose
    }
    func rfcommChannelOpenComplete(_ ch: IOBluetoothRFCOMMChannel!, status error: IOReturn) { onOpen(error) }
    func rfcommChannelData(_ ch: IOBluetoothRFCOMMChannel!, data ptr: UnsafeMutableRawPointer!, length len: Int) {
        onData(Data(bytes: ptr, count: len))
    }
    func rfcommChannelClosed(_ ch: IOBluetoothRFCOMMChannel!) { onClose() }
}
