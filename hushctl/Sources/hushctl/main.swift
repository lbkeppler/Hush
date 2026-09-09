import BoseKit
import Foundation

let mac = ProcessInfo.processInfo.environment["BOSE_MAC"] ?? "E4:58:BC:2E:0E:A7"
let transport = BluetoothTransport(address: mac, channel: 2)
try await transport.connect()
try transport.rawSend(BMAPBuild.get(Addr.firmware).encoded)
try await Task.sleep(nanoseconds: 800_000_000)
print("connected; sent firmware request — see next task for response reads")
