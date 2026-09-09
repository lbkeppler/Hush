import BoseKit
import Foundation

let mac = ProcessInfo.processInfo.environment["BOSE_MAC"] ?? "E4:58:BC:2E:0E:A7"
let transport = try await BluetoothTransport.discover(address: mac)

let fw = try await transport.send(BMAPBuild.get(Addr.firmware))
if let f = fw.first(where: { ($0.fblock, $0.function) == Addr.firmware }) {
    print("Firmware: \(BMAPParse.firmware(f.payload))")
}

let bat = try await transport.send(BMAPBuild.get(Addr.battery))
if let b = bat.first(where: { ($0.fblock, $0.function) == Addr.battery }) {
    print("Battery: \(BMAPParse.battery(b.payload))%")
}
