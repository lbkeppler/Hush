import BoseKit
import Foundation

// Milestone 0 diagnostic harness: `status` dumps every readable setting, `verify` runs
// an apply -> read-back -> revert check against each reversible setting. Hardware runs
// are the controller's job (see task-14 brief) — this file only needs to build cleanly.

let mac = ProcessInfo.processInfo.environment["BOSE_MAC"] ?? "E4:58:BC:2E:0E:A7"

let transport = try await BluetoothTransport.discover(address: mac)
let dev = BoseDevice(sender: transport, profile: .lonestarr)

// MARK: - status

func runStatus() async throws {
    print("Firmware:", try await dev.firmware())
    print("Battery:", try await dev.battery())
    print("Mode:", try await dev.currentMode())
    print("EQ:", try await dev.eq())
    print("Audio:", try await dev.audioSettings())
    print("Sidetone:", try await dev.sidetone())
    print("Multipoint:", try await dev.multipoint())
    print("AutoPause:", try await dev.autoPause())
    print("AutoAnswer:", try await dev.autoAnswer())
    print("Name:", try await dev.name())
}

// MARK: - verify

/// Applies `testValue(original)`, reads back, checks it matches, then always restores
/// `original` (even if the apply/read-back step failed). Any thrown error along the way
/// is reported as FAIL rather than propagated, so one bad setting doesn't abort the run.
func verifyStep<T: Equatable>(
    _ name: String,
    read: () async throws -> T,
    apply: (T) async throws -> Void,
    testValue: (T) -> T
) async -> Bool {
    var original: T?
    var passed = false

    do {
        let current = try await read()
        original = current
        let target = testValue(current)
        try await apply(target)
        let after = try await read()
        if after == target {
            print("PASS \(name)")
            passed = true
        } else {
            print("FAIL \(name): wrote \(target), read back \(after)")
        }
    } catch {
        print("FAIL \(name): \(error)")
    }

    if let original {
        do {
            try await apply(original)
        } catch {
            print("FAIL \(name): could not restore original value (\(original)): \(error)")
            passed = false
        }
    }

    return passed
}

func runVerify() async {
    var results: [Bool] = []

    results.append(await verifyStep(
        "CNC",
        read: { try await dev.audioSettings().cnc },
        apply: { try await dev.setCNC($0) },
        testValue: { $0 == 0 ? 5 : 0 }
    ))

    results.append(await verifyStep(
        "ANC",
        read: { try await dev.audioSettings().anc != 0 },
        apply: { try await dev.setANC($0) },
        testValue: { !$0 }
    ))

    results.append(await verifyStep(
        "Wind",
        read: { try await dev.audioSettings().wind != 0 },
        apply: { try await dev.setWind($0) },
        testValue: { !$0 }
    ))

    results.append(await verifyStep(
        "Spatial",
        read: { try await dev.audioSettings().spatial },
        apply: { try await dev.setSpatial($0) },
        testValue: { $0 == 0 ? 1 : 0 }
    ))

    results.append(await verifyStep(
        "EQ bass",
        read: { try await dev.eq().first(where: { $0.band == 0 })?.value ?? 0 },
        apply: { try await dev.setEQ(band: 0, value: $0) },
        testValue: { $0 + 2 <= 10 ? $0 + 2 : $0 - 2 }
    ))

    results.append(await verifyStep(
        "Mode",
        read: { try await dev.currentMode() },
        apply: { try await dev.setMode($0) },
        testValue: { $0 == 0 ? 1 : 0 }
    ))

    results.append(await verifyStep(
        "Sidetone",
        read: { try await dev.sidetone() },
        apply: { try await dev.setSidetone($0) },
        testValue: { $0 == 0 ? 1 : 0 }
    ))

    results.append(await verifyStep(
        "Multipoint",
        read: { try await dev.multipoint() },
        apply: { try await dev.setMultipoint($0) },
        testValue: { !$0 }
    ))

    results.append(await verifyStep(
        "AutoPause",
        read: { try await dev.autoPause() },
        apply: { try await dev.setAutoPause($0) },
        testValue: { !$0 }
    ))

    results.append(await verifyStep(
        "AutoAnswer",
        read: { try await dev.autoAnswer() },
        apply: { try await dev.setAutoAnswer($0) },
        testValue: { !$0 }
    ))

    let passCount = results.filter { $0 }.count
    print("---")
    print("\(passCount)/\(results.count) settings verified")
}

// MARK: - dispatch

switch CommandLine.arguments.dropFirst().first ?? "status" {
case "status":
    try await runStatus()
case "verify":
    await runVerify()
default:
    print("unknown command; expected 'status' or 'verify'")
}
