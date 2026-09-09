import BoseKit
import Foundation

// Milestone 0 diagnostic harness: `status` dumps every readable setting, `verify` runs
// an apply -> read-back -> revert check against each reversible setting. Hardware runs
// are the controller's job (see task-14 brief) — this file only needs to build cleanly.

let mac = ProcessInfo.processInfo.environment["BOSE_MAC"] ?? "E4:58:BC:2E:0E:A7"

let transport = try await BluetoothTransport.discover(address: mac)
let dev = BoseDevice(sender: transport, profile: .lonestarr)

// MARK: - status

/// Reads and prints one field in isolation: a `FuncNotSupp` device error (code 4) is
/// reported as UNSUPPORTED rather than aborting the whole `status` run — some fields
/// are simply absent on gen-1 hardware, and we want to see every other field regardless.
func printField<T>(_ name: String, _ read: () async throws -> T) async {
    do {
        let value = try await read()
        print("\(name):", value)
    } catch BMAPError.device(code: 4) {
        print("\(name): UNSUPPORTED (FuncNotSupp)")
    } catch {
        print("\(name): ERROR \(error)")
    }
}

func runStatus() async {
    await printField("Firmware") { try await dev.firmware() }
    await printField("Battery") { try await dev.battery() }
    await printField("Mode") { try await dev.currentMode() }
    await printField("EQ") { try await dev.eq() }
    await printField("Audio") { try await dev.audioSettings() }
    await printField("Sidetone") { try await dev.sidetone() }
    await printField("Multipoint") { try await dev.multipoint() }
    await printField("AutoPause") { try await dev.autoPause() }
    await printField("AutoAnswer") { try await dev.autoAnswer() }
    await printField("Name") { try await dev.name() }
}

// MARK: - verify

enum StepResult: Equatable {
    case pass, fail, unsupported, skipped
}

/// Applies `testValue(original)`, reads back, checks it matches, then restores `original`
/// (even if the apply/read-back step failed) — except when the step turned out to be
/// unsupported, in which case nothing was written so there is nothing to restore.
///
/// A `FuncNotSupp` (device error code 4) from either the read or the apply is reported as
/// UNSUPPORTED rather than FAIL, so the summary can distinguish "gen-1 doesn't have this"
/// from "this is actually broken". Any other error is reported as FAIL rather than
/// propagated, so one bad setting doesn't abort the run.
func verifyStep<T: Equatable>(
    _ name: String,
    read: () async throws -> T,
    apply: (T) async throws -> Void,
    testValue: (T) -> T
) async -> StepResult {
    var original: T?
    var result: StepResult = .fail

    do {
        let current = try await read()
        original = current
        let target = testValue(current)
        try await apply(target)
        let after = try await read()
        if after == target {
            print("PASS \(name)")
            result = .pass
        } else {
            print("FAIL \(name): wrote \(target), read back \(after)")
        }
    } catch BMAPError.device(code: 4) {
        print("UNSUPPORTED \(name) (FuncNotSupp)")
        result = .unsupported
    } catch {
        print("FAIL \(name): \(error)")
    }

    if result != .unsupported, let original {
        do {
            try await apply(original)
        } catch {
            print("FAIL \(name): could not restore original value (\(original)): \(error)")
            result = .fail
        }
    }

    return result
}

/// CNC needs a bespoke check rather than a plain `verifyStep`: `setCNC` always forces
/// `autoCNC = 0` and there is no API to set `autoCNC` back to 1. If the device currently
/// has adaptive/auto-CNC engaged, running the normal apply/revert check would silently
/// and permanently disable it while still printing PASS. So: read the full audio
/// settings first, and only run the mutating check when `autoCNC == 0`.
func verifyCNC() async -> StepResult {
    let current: AudioSettings
    do {
        current = try await dev.audioSettings()
    } catch BMAPError.device(code: 4) {
        print("UNSUPPORTED CNC (FuncNotSupp)")
        return .unsupported
    } catch {
        print("FAIL CNC: \(error)")
        return .fail
    }

    guard current.autoCNC == 0 else {
        print("SKIP CNC: adaptive/auto-CNC engaged (no safe restore path)")
        return .skipped
    }

    return await verifyStep(
        "CNC",
        read: { try await dev.audioSettings().cnc },
        apply: { try await dev.setCNC($0) },
        testValue: { $0 == 0 ? 5 : 0 }
    )
}

func runVerify() async {
    var results: [StepResult] = []

    results.append(await verifyCNC())

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

    let passCount = results.filter { $0 == .pass }.count
    let failCount = results.filter { $0 == .fail }.count
    let otherCount = results.filter { $0 == .unsupported || $0 == .skipped }.count
    print("---")
    print("\(passCount) passed, \(failCount) failed, \(otherCount) unsupported/skipped out of \(results.count)")
}

// MARK: - dispatch

switch CommandLine.arguments.dropFirst().first ?? "status" {
case "status":
    await runStatus()
case "verify":
    await runVerify()
default:
    print("unknown command; expected 'status' or 'verify'")
}
