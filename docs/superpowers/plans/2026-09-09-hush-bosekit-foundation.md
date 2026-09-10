# BoseKit Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `BoseKit`, a native Swift library that reads and writes every user-facing setting on a Bose QC Ultra over Bluetooth RFCOMM using the BMAP protocol, verified against the real device via a small CLI.

**Architecture:** A pure, I/O-free `BMAPCodec` (frame encode/decode + per-feature parsers/builders) sits under a `BluetoothTransport` actor (IOBluetooth RFCOMM, persistent connection) and a typed `BoseDevice` API selected by a data-only `DeviceProfile`. A `hushctl` CLI exercises the stack against real hardware (Milestone 0) to confirm the untested `lonestarr` (0x4066) profile.

**Tech Stack:** Swift 5.9+, Swift Package Manager, IOBluetooth (macOS), Swift Testing (`import Testing`). No third-party dependencies.

**Spec:** `docs/superpowers/plans/../specs/2026-09-09-bose-macos-app-design.md` (i.e. `docs/superpowers/specs/2026-09-09-bose-macos-app-design.md`) — read it alongside this plan.

## Global Constraints

- Platform: **macOS 14 (Sonoma)** minimum. Package `platforms: [.macOS(.v14)]`.
- **No third-party dependencies** — native frameworks only (this is the "native Swift" goal).
- **Never send operator SET (0).** All writes use **SETGET (2)** or **START (5)**; reads use **GET (1)**. Auth/ECDH (block 18) is out of scope.
- BMAP frame = `[fblock, function, flags, length, payload…]`; `flags = operator & 0x0F`; no preamble/checksum/terminator; multi-frame split by length.
- **CNC is inverted**: 0 = max ANC, 10 = most ambient. Never send `autoCNC=1` (Runtime err 8).
- EQ values are **signed** `Int8`, range −10 (0xF6) .. +10 (0x0A).
- Reference model is **wolverine (0x4082, QC Ultra 2)**. Target **lonestarr (0x4066)** is unverified for writes — the `lonestarr` profile starts as a copy of `wolverine` and is corrected in Milestone 0.
- Target device: MAC `E4:58:BC:2E:0E:A7`, firmware `1.6.7+g6ebabd2`.
- Reference implementation (read-only): `~/bosectl` (Python `pybmap`); captured bytes in `~/bosectl/captures/*.json` and `~/bosectl/fixtures/`.

---

### Task 1: Scaffold the workspace

**Files:**
- Create: `BoseKit/Package.swift`
- Create: `BoseKit/Sources/BoseKit/BoseKit.swift` (umbrella/doc file)
- Create: `BoseKit/Tests/BoseKitTests/SmokeTests.swift`

**Interfaces:**
- Produces: the `BoseKit` SwiftPM library, buildable and testable via `swift test` from `BoseKit/`.

- [ ] **Step 1: Create the package manifest**

`BoseKit/Package.swift`:
```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BoseKit",
    platforms: [.macOS(.v14)],
    products: [.library(name: "BoseKit", targets: ["BoseKit"])],
    targets: [
        .target(name: "BoseKit"),
        .testTarget(name: "BoseKitTests", dependencies: ["BoseKit"]),
    ]
)
```

- [ ] **Step 2: Add a placeholder source and a smoke test**

`BoseKit/Sources/BoseKit/BoseKit.swift`:
```swift
/// BoseKit — native Swift BMAP controller for Bose QC Ultra.
public enum BoseKit { public static let version = "0.1.0" }
```
`BoseKit/Tests/BoseKitTests/SmokeTests.swift`:
```swift
import Testing
@testable import BoseKit

@Test func packageBuilds() {
    #expect(BoseKit.version == "0.1.0")
}
```

- [ ] **Step 3: Build and test**

Run: `cd BoseKit && swift test`
Expected: PASS (1 test).

- [ ] **Step 4: Commit**

```bash
git add BoseKit
git commit -m "chore: scaffold BoseKit swift package"
```

---

### Task 2: BMAP frame model + encode

**Files:**
- Create: `BoseKit/Sources/BoseKit/Protocol/BMAPOperator.swift`
- Create: `BoseKit/Sources/BoseKit/Protocol/BMAPFrame.swift`
- Test: `BoseKit/Tests/BoseKitTests/BMAPFrameEncodeTests.swift`

**Interfaces:**
- Produces:
  - `enum BMAPOperator: UInt8 { case set=0, get=1, setGet=2, status=3, error=4, start=5, result=6, processing=7 }`
  - `struct BMAPFrame: Equatable { var fblock: UInt8; var function: UInt8; var op: BMAPOperator; var payload: [UInt8]; var encoded: Data }`
  - `init(fblock:function:op:payload:)` with `payload` defaulting to `[]`.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
@testable import BoseKit

@Test func encodesGetRequestWithNoPayload() {
    let f = BMAPFrame(fblock: 0x02, function: 0x02, op: .get)
    #expect(Array(f.encoded) == [0x02, 0x02, 0x01, 0x00])
}

@Test func encodesSetGetWithPayload() {
    let f = BMAPFrame(fblock: 0x01, function: 0x07, op: .setGet, payload: [0x01, 0x00])
    #expect(Array(f.encoded) == [0x01, 0x07, 0x02, 0x02, 0x01, 0x00])
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter BMAPFrameEncodeTests`
Expected: FAIL (types not defined).

- [ ] **Step 3: Write minimal implementation**

`BMAPOperator.swift`:
```swift
public enum BMAPOperator: UInt8, Sendable {
    case set = 0, get = 1, setGet = 2, status = 3
    case error = 4, start = 5, result = 6, processing = 7
}
```
`BMAPFrame.swift`:
```swift
import Foundation

public struct BMAPFrame: Equatable, Sendable {
    public var fblock: UInt8
    public var function: UInt8
    public var op: BMAPOperator
    public var payload: [UInt8]

    public init(fblock: UInt8, function: UInt8, op: BMAPOperator, payload: [UInt8] = []) {
        self.fblock = fblock; self.function = function; self.op = op; self.payload = payload
    }

    public var encoded: Data {
        Data([fblock, function, op.rawValue & 0x0F, UInt8(payload.count)] + payload)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter BMAPFrameEncodeTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add BoseKit/Sources/BoseKit/Protocol BoseKit/Tests/BoseKitTests/BMAPFrameEncodeTests.swift
git commit -m "feat: BMAP frame model and encoding"
```

---

### Task 3: BMAP frame decode + multi-frame split

**Files:**
- Modify: `BoseKit/Sources/BoseKit/Protocol/BMAPFrame.swift`
- Test: `BoseKit/Tests/BoseKitTests/BMAPFrameDecodeTests.swift`

**Interfaces:**
- Produces:
  - `static func BMAPFrame.parseAll(_ data: Data) -> [BMAPFrame]` — splits concatenated frames by length; drops a trailing frame whose declared length overruns the buffer.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import Foundation
@testable import BoseKit

@Test func parsesSingleStatusFrame() {
    // Battery STATUS: 02 02 03 04 50 ff ff 00
    let frames = BMAPFrame.parseAll(Data([0x02,0x02,0x03,0x04,0x50,0xff,0xff,0x00]))
    #expect(frames.count == 1)
    #expect(frames[0].fblock == 0x02 && frames[0].function == 0x02)
    #expect(frames[0].op == .status)
    #expect(frames[0].payload == [0x50,0xff,0xff,0x00])
}

@Test func splitsConcatenatedFrames() {
    // mode STATUS (1f 03 03 01 01) followed by battery STATUS
    let data = Data([0x1f,0x03,0x03,0x01,0x01, 0x02,0x02,0x03,0x04,0x50,0xff,0xff,0x00])
    let frames = BMAPFrame.parseAll(data)
    #expect(frames.count == 2)
    #expect(frames[0].payload == [0x01])
    #expect(frames[1].payload == [0x50,0xff,0xff,0x00])
}

@Test func dropsTruncatedTrailingFrame() {
    // second frame claims length 4 but only 1 byte follows
    let data = Data([0x1f,0x03,0x03,0x01,0x01, 0x02,0x02,0x03,0x04,0x50])
    let frames = BMAPFrame.parseAll(data)
    #expect(frames.count == 1)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter BMAPFrameDecodeTests`
Expected: FAIL (`parseAll` not defined).

- [ ] **Step 3: Write minimal implementation** (append to `BMAPFrame.swift`)

```swift
public extension BMAPFrame {
    static func parseAll(_ data: Data) -> [BMAPFrame] {
        let bytes = [UInt8](data)
        var frames: [BMAPFrame] = []
        var pos = 0
        while pos + 4 <= bytes.count {
            let length = Int(bytes[pos + 3])
            let end = pos + 4 + length
            guard end <= bytes.count else { break } // truncated → drop
            let op = BMAPOperator(rawValue: bytes[pos + 2] & 0x0F) ?? .status
            frames.append(BMAPFrame(fblock: bytes[pos], function: bytes[pos + 1],
                                    op: op, payload: Array(bytes[(pos + 4)..<end])))
            pos = end
        }
        return frames
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter BMAPFrameDecodeTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add BoseKit/Sources/BoseKit/Protocol/BMAPFrame.swift BoseKit/Tests/BoseKitTests/BMAPFrameDecodeTests.swift
git commit -m "feat: BMAP multi-frame decode"
```

---

### Task 4: BMAP errors + addresses table

**Files:**
- Create: `BoseKit/Sources/BoseKit/Protocol/BMAPError.swift`
- Create: `BoseKit/Sources/BoseKit/Protocol/Addresses.swift`
- Test: `BoseKit/Tests/BoseKitTests/BMAPErrorTests.swift`

**Interfaces:**
- Produces:
  - `enum BMAPError: Error, Equatable { case device(code: UInt8); case timeout; case notConnected; case unexpectedResponse; case unsupported }`
  - `static func BMAPError.from(_ frame: BMAPFrame) -> BMAPError?` — returns `.device(code:)` iff `frame.op == .error` (code = payload[0]).
  - `enum Addr` — named `(fblock, function)` tuples for every feature (values below).

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import BoseKit

@Test func mapsErrorFrameToDeviceError() {
    let f = BMAPFrame(fblock: 0x1f, function: 0x06, op: .error, payload: [0x08])
    #expect(BMAPError.from(f) == .device(code: 0x08)) // Runtime error 8
}

@Test func nonErrorFrameIsNotAnError() {
    let f = BMAPFrame(fblock: 0x02, function: 0x02, op: .status, payload: [0x50])
    #expect(BMAPError.from(f) == nil)
}

@Test func addressesAreCorrect() {
    #expect(Addr.battery == (0x02, 0x02))
    #expect(Addr.eq == (0x01, 0x07))
    #expect(Addr.audioSettings == (0x1f, 0x0a))
    #expect(Addr.currentMode == (0x1f, 0x03))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter BMAPErrorTests`
Expected: FAIL.

- [ ] **Step 3: Write minimal implementation**

`BMAPError.swift`:
```swift
public enum BMAPError: Error, Equatable, Sendable {
    case device(code: UInt8)
    case timeout
    case notConnected
    case unexpectedResponse
    case unsupported

    public static func from(_ frame: BMAPFrame) -> BMAPError? {
        guard frame.op == .error else { return nil }
        return .device(code: frame.payload.first ?? 0)
    }
}
```
`Addresses.swift`:
```swift
public enum Addr {
    public static let firmware: (UInt8, UInt8)      = (0x00, 0x05)
    public static let name: (UInt8, UInt8)          = (0x01, 0x02)
    public static let voicePrompts: (UInt8, UInt8)  = (0x01, 0x03)
    public static let cnc: (UInt8, UInt8)           = (0x01, 0x05)
    public static let eq: (UInt8, UInt8)            = (0x01, 0x07)
    public static let buttons: (UInt8, UInt8)       = (0x01, 0x09)
    public static let multipoint: (UInt8, UInt8)    = (0x01, 0x0a)
    public static let sidetone: (UInt8, UInt8)      = (0x01, 0x0b)
    public static let autoPause: (UInt8, UInt8)     = (0x01, 0x18)
    public static let autoAnswer: (UInt8, UInt8)    = (0x01, 0x1b)
    public static let battery: (UInt8, UInt8)       = (0x02, 0x02)
    public static let control: (UInt8, UInt8)       = (0x07, 0x04)
    public static let modesList: (UInt8, UInt8)     = (0x1f, 0x01)
    public static let currentMode: (UInt8, UInt8)   = (0x1f, 0x03)
    public static let modeConfig: (UInt8, UInt8)    = (0x1f, 0x06)
    public static let audioSettings: (UInt8, UInt8) = (0x1f, 0x0a)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter BMAPErrorTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add BoseKit/Sources/BoseKit/Protocol/BMAPError.swift BoseKit/Sources/BoseKit/Protocol/Addresses.swift BoseKit/Tests/BoseKitTests/BMAPErrorTests.swift
git commit -m "feat: BMAP error mapping and address table"
```

---

### Task 5: Simple read parsers — battery, firmware, name, mode, CNC, multipoint, sidetone, toggles

**Files:**
- Create: `BoseKit/Sources/BoseKit/Protocol/Parsers.swift`
- Test: `BoseKit/Tests/BoseKitTests/ParsersTests.swift`

**Interfaces:**
- Produces static parse functions on `enum BMAPParse`:
  - `battery(_ payload: [UInt8]) -> Int` → `payload[0]`
  - `firmware(_ payload: [UInt8]) -> String` → ASCII
  - `name(_ payload: [UInt8]) -> String` → UTF-8 of `payload[1...]`
  - `modeIndex(_ payload: [UInt8]) -> Int` → `payload[0]`
  - `cnc(_ payload: [UInt8]) -> (current: Int, max: Int)` → `(payload[1], payload[0]-1)`
  - `multipointEnabled(_ payload: [UInt8]) -> Bool` → `payload[0] & 0x02 != 0`
  - `sidetone(_ payload: [UInt8]) -> Int` → `payload[1]`
  - `boolByte0(_ payload: [UInt8]) -> Bool` → `payload[0] != 0`

- [ ] **Step 1: Write the failing test** (real captured bytes)

```swift
import Testing
@testable import BoseKit

@Test func parsesBattery()  { #expect(BMAPParse.battery([0x50,0xff,0xff,0x00]) == 80) }
@Test func parsesFirmware() { #expect(BMAPParse.firmware(Array("1.6.7".utf8)) == "1.6.7") }
@Test func parsesName()     { #expect(BMAPParse.name([0x00,0x46,0x61,0x72,0x67,0x6f]) == "Fargo") }
@Test func parsesModeIndex(){ #expect(BMAPParse.modeIndex([0x01]) == 1) }
@Test func parsesCNC() {
    let r = BMAPParse.cnc([0x0b,0x00,0x03]); #expect(r.current == 0 && r.max == 10)
}
@Test func parsesMultipoint() { #expect(BMAPParse.multipointEnabled([0x07]) == true) }
@Test func parsesSidetone()   { #expect(BMAPParse.sidetone([0x01,0x02,0x0f]) == 2) } // medium
@Test func parsesBoolByte0()  { #expect(BMAPParse.boolByte0([0x01]) == true) }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ParsersTests`
Expected: FAIL.

- [ ] **Step 3: Write minimal implementation**

`Parsers.swift`:
```swift
import Foundation

public enum BMAPParse {
    public static func battery(_ p: [UInt8]) -> Int { Int(p.first ?? 0) }
    public static func firmware(_ p: [UInt8]) -> String { String(decoding: p, as: UTF8.self) }
    public static func name(_ p: [UInt8]) -> String {
        String(decoding: Array(p.dropFirst()), as: UTF8.self)
    }
    public static func modeIndex(_ p: [UInt8]) -> Int { Int(p.first ?? 0) }
    public static func cnc(_ p: [UInt8]) -> (current: Int, max: Int) {
        (Int(p.count > 1 ? p[1] : 0), Int(p.first ?? 1) - 1)
    }
    public static func multipointEnabled(_ p: [UInt8]) -> Bool { (p.first ?? 0) & 0x02 != 0 }
    public static func sidetone(_ p: [UInt8]) -> Int { Int(p.count > 1 ? p[1] : 0) }
    public static func boolByte0(_ p: [UInt8]) -> Bool { (p.first ?? 0) != 0 }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ParsersTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add BoseKit/Sources/BoseKit/Protocol/Parsers.swift BoseKit/Tests/BoseKitTests/ParsersTests.swift
git commit -m "feat: simple BMAP read parsers"
```

---

### Task 6: EQ parse (signed 3-band) + per-band builder

**Files:**
- Modify: `BoseKit/Sources/BoseKit/Protocol/Parsers.swift`
- Create: `BoseKit/Sources/BoseKit/Protocol/Builders.swift`
- Test: `BoseKit/Tests/BoseKitTests/EQTests.swift`

**Interfaces:**
- Produces:
  - `struct EQBand: Equatable { var band: Int; var value: Int }`  (band 0=bass,1=mid,2=treble)
  - `BMAPParse.eq(_ payload: [UInt8]) -> [EQBand]` — 3 groups of `[min,max,cur(signed),band]`
  - `BMAPBuild.eqBand(value: Int, band: Int) -> BMAPFrame` — SETGET `[01 07 02 02 <signed> <band>]`

- [ ] **Step 1: Write the failing test** (captured EQ read)

```swift
import Testing
@testable import BoseKit

@Test func parsesSignedEQ() {
    // f6 0a 00 00 | f6 0a fe 01 | f6 0a fa 02  → bass 0, mid -2, treble -6
    let bands = BMAPParse.eq([0xf6,0x0a,0x00,0x00, 0xf6,0x0a,0xfe,0x01, 0xf6,0x0a,0xfa,0x02])
    #expect(bands == [EQBand(band: 0, value: 0), EQBand(band: 1, value: -2), EQBand(band: 2, value: -6)])
}

@Test func buildsEQBandFrameWithSignedValue() {
    let f = BMAPBuild.eqBand(value: -4, band: 0) // bass -4
    #expect(Array(f.encoded) == [0x01,0x07,0x02,0x02,0xfc,0x00])
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter EQTests`
Expected: FAIL.

- [ ] **Step 3: Write minimal implementation**

Append to `Parsers.swift`:
```swift
public struct EQBand: Equatable, Sendable { public var band: Int; public var value: Int
    public init(band: Int, value: Int) { self.band = band; self.value = value } }

public extension BMAPParse {
    static func eq(_ p: [UInt8]) -> [EQBand] {
        stride(from: 0, to: p.count - 3, by: 4).map { i in
            EQBand(band: Int(p[i + 3]), value: Int(Int8(bitPattern: p[i + 2])))
        }
    }
}
```
`Builders.swift`:
```swift
import Foundation

public enum BMAPBuild {
    public static func eqBand(value: Int, band: Int) -> BMAPFrame {
        let v = UInt8(bitPattern: Int8(clamping: value))
        return BMAPFrame(fblock: Addr.eq.0, function: Addr.eq.1, op: .setGet, payload: [v, UInt8(band)])
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter EQTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add BoseKit/Sources/BoseKit/Protocol BoseKit/Tests/BoseKitTests/EQTests.swift
git commit -m "feat: signed EQ parse and per-band builder"
```

---

### Task 7: Audio settings register [31.10] parse + build (cnc/spatial/wind/anc)

**Files:**
- Modify: `BoseKit/Sources/BoseKit/Protocol/Parsers.swift`, `Builders.swift`
- Test: `BoseKit/Tests/BoseKitTests/AudioSettingsTests.swift`

**Interfaces:**
- Produces:
  - `struct AudioSettings: Equatable { var cnc: Int; var autoCNC: Int; var spatial: Int; var wind: Int; var anc: Int }`
  - `BMAPParse.audioSettings(_ payload: [UInt8]) -> AudioSettings`
  - `BMAPBuild.audioSettings(_ s: AudioSettings) -> BMAPFrame` — SETGET `1f 0a 02 05 <cnc><autoCNC><spatial><wind><anc>`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import BoseKit

@Test func parsesAudioSettings() {
    let s = BMAPParse.audioSettings([0x00,0x00,0x02,0x00,0x01]) // cnc0 spatial=head wind0 anc on
    #expect(s == AudioSettings(cnc: 0, autoCNC: 0, spatial: 2, wind: 0, anc: 1))
}

@Test func buildsAudioSettings() {
    let f = BMAPBuild.audioSettings(AudioSettings(cnc: 0, autoCNC: 0, spatial: 0, wind: 0, anc: 1))
    #expect(Array(f.encoded) == [0x1f,0x0a,0x02,0x05,0x00,0x00,0x00,0x00,0x01])
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AudioSettingsTests`
Expected: FAIL.

- [ ] **Step 3: Write minimal implementation**

Append to `Parsers.swift`:
```swift
public struct AudioSettings: Equatable, Sendable {
    public var cnc: Int; public var autoCNC: Int; public var spatial: Int; public var wind: Int; public var anc: Int
    public init(cnc: Int, autoCNC: Int, spatial: Int, wind: Int, anc: Int) {
        self.cnc = cnc; self.autoCNC = autoCNC; self.spatial = spatial; self.wind = wind; self.anc = anc
    }
}
public extension BMAPParse {
    static func audioSettings(_ p: [UInt8]) -> AudioSettings {
        func b(_ i: Int) -> Int { i < p.count ? Int(p[i]) : 0 }
        return AudioSettings(cnc: b(0), autoCNC: b(1), spatial: b(2), wind: b(3), anc: b(4))
    }
}
```
Append to `Builders.swift`:
```swift
public extension BMAPBuild {
    static func audioSettings(_ s: AudioSettings) -> BMAPFrame {
        BMAPFrame(fblock: Addr.audioSettings.0, function: Addr.audioSettings.1, op: .setGet,
                  payload: [UInt8(s.cnc), UInt8(s.autoCNC), UInt8(s.spatial), UInt8(s.wind), UInt8(s.anc)])
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AudioSettingsTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add BoseKit/Sources/BoseKit/Protocol BoseKit/Tests/BoseKitTests/AudioSettingsTests.swift
git commit -m "feat: audio settings register [31.10] parse and build"
```

---

### Task 8: Setting builders — name, mode, toggles, sidetone, voice prompts

**Files:**
- Modify: `BoseKit/Sources/BoseKit/Protocol/Builders.swift`
- Test: `BoseKit/Tests/BoseKitTests/SettingBuildersTests.swift`

**Interfaces:**
- Produces on `BMAPBuild`:
  - `setName(_ name: String) -> BMAPFrame` — SETGET `[1.2]`, raw UTF-8 (no flag byte), truncated to 31 bytes
  - `setMode(index: Int, announce: Bool) -> BMAPFrame` — START `[31.3]` payload `[index, announce ? 1 : 0]`
  - `toggle(_ addr: (UInt8,UInt8), on: Bool) -> BMAPFrame` — SETGET payload `[on ? 1 : 0]`
  - `setSidetone(level: Int) -> BMAPFrame` — SETGET `[1.11]` payload `[0x01, level]`
  - `setVoicePrompts(enabled: Bool, language: Int) -> BMAPFrame` — SETGET `[1.3]` payload `[(enabled ? 0x20 : 0) | (language & 0x1F)]` (⚠ enabled-bit verified in Milestone 0; see spec §4.3)
  - `get(_ addr: (UInt8,UInt8)) -> BMAPFrame` — GET convenience

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import BoseKit

@Test func buildsGet() {
    #expect(Array(BMAPBuild.get(Addr.battery).encoded) == [0x02,0x02,0x01,0x00])
}
@Test func buildsSetName() {
    #expect(Array(BMAPBuild.setName("Fargo").encoded) == [0x01,0x02,0x02,0x05,0x46,0x61,0x72,0x67,0x6f])
}
@Test func buildsSetModeAware() {
    #expect(Array(BMAPBuild.setMode(index: 1, announce: false).encoded) == [0x1f,0x03,0x05,0x02,0x01,0x00])
}
@Test func buildsToggleMultipointOff() {
    #expect(Array(BMAPBuild.toggle(Addr.multipoint, on: false).encoded) == [0x01,0x0a,0x02,0x01,0x00])
}
@Test func buildsSidetoneMedium() {
    #expect(Array(BMAPBuild.setSidetone(level: 2).encoded) == [0x01,0x0b,0x02,0x02,0x01,0x02])
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SettingBuildersTests`
Expected: FAIL.

- [ ] **Step 3: Write minimal implementation** (append to `Builders.swift`)

```swift
public extension BMAPBuild {
    static func get(_ a: (UInt8, UInt8)) -> BMAPFrame { BMAPFrame(fblock: a.0, function: a.1, op: .get) }

    static func setName(_ name: String) -> BMAPFrame {
        let bytes = Array(Array(name.utf8).prefix(31))
        return BMAPFrame(fblock: Addr.name.0, function: Addr.name.1, op: .setGet, payload: bytes)
    }
    static func setMode(index: Int, announce: Bool) -> BMAPFrame {
        BMAPFrame(fblock: Addr.currentMode.0, function: Addr.currentMode.1, op: .start,
                  payload: [UInt8(index), announce ? 1 : 0])
    }
    static func toggle(_ a: (UInt8, UInt8), on: Bool) -> BMAPFrame {
        BMAPFrame(fblock: a.0, function: a.1, op: .setGet, payload: [on ? 1 : 0])
    }
    static func setSidetone(level: Int) -> BMAPFrame {
        BMAPFrame(fblock: Addr.sidetone.0, function: Addr.sidetone.1, op: .setGet, payload: [0x01, UInt8(level)])
    }
    static func setVoicePrompts(enabled: Bool, language: Int) -> BMAPFrame {
        BMAPFrame(fblock: Addr.voicePrompts.0, function: Addr.voicePrompts.1, op: .setGet,
                  payload: [(enabled ? 0x20 : 0) | (UInt8(language) & 0x1F)])
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter SettingBuildersTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add BoseKit/Sources/BoseKit/Protocol/Builders.swift BoseKit/Tests/BoseKitTests/SettingBuildersTests.swift
git commit -m "feat: setting builders (name, mode, toggles, sidetone, prompts)"
```

---

### Task 9: ModeConfig (custom profiles) parse (48B) + build (40B)

**Files:**
- Create: `BoseKit/Sources/BoseKit/Protocol/ModeConfig.swift`
- Test: `BoseKit/Tests/BoseKitTests/ModeConfigTests.swift`

**Interfaces:**
- Produces:
  - `struct ModeConfig: Equatable { var index: Int; var name: String; var editable: Bool; var configured: Bool; var cnc: Int; var autoCNC: Int; var spatial: Int; var wind: Int; var anc: Int }`
  - `BMAPParse.modeConfig48(_ payload: [UInt8]) -> ModeConfig` (STATUS offsets per spec §4.4)
  - `BMAPBuild.modeConfig40(_ c: ModeConfig) -> BMAPFrame` — SETGET `[31.6]`, 40-byte payload, name UTF-8 null-padded to 32

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import BoseKit

@Test func parses48ByteModeConfig() {
    var p = [UInt8](repeating: 0, count: 48)
    p[0] = 5                 // index
    p[3] = 1                 // editable
    p[4] = 1                 // configured
    for (i, b) in Array("Focus".utf8).enumerated() { p[6 + i] = b }
    p[42] = 3; p[44] = 1; p[45] = 0; p[47] = 1 // cnc=3 spatial=room anc=on
    let c = BMAPParse.modeConfig48(p)
    #expect(c.index == 5 && c.name == "Focus" && c.editable && c.configured)
    #expect(c.cnc == 3 && c.spatial == 1 && c.anc == 1)
}

@Test func builds40ByteModeConfigWithPaddedName() {
    let c = ModeConfig(index: 5, name: "Focus", editable: true, configured: true,
                       cnc: 3, autoCNC: 0, spatial: 1, wind: 0, anc: 1)
    let f = BMAPBuild.modeConfig40(c)
    let p = f.payload
    #expect(f.fblock == 0x1f && f.function == 0x06 && f.op == .setGet)
    #expect(p.count == 40)
    #expect(p[0] == 5)
    #expect(Array(p[3..<8]) == Array("Focus".utf8))
    #expect(p[8] == 0)          // null padding begins
    #expect(p[35] == 3 && p[37] == 1 && p[39] == 1) // cnc, spatial, anc
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ModeConfigTests`
Expected: FAIL.

- [ ] **Step 3: Write minimal implementation**

`ModeConfig.swift`:
```swift
import Foundation

public struct ModeConfig: Equatable, Sendable {
    public var index: Int; public var name: String
    public var editable: Bool; public var configured: Bool
    public var cnc: Int; public var autoCNC: Int; public var spatial: Int; public var wind: Int; public var anc: Int
    public init(index: Int, name: String, editable: Bool, configured: Bool,
                cnc: Int, autoCNC: Int, spatial: Int, wind: Int, anc: Int) {
        self.index = index; self.name = name; self.editable = editable; self.configured = configured
        self.cnc = cnc; self.autoCNC = autoCNC; self.spatial = spatial; self.wind = wind; self.anc = anc
    }
}

public extension BMAPParse {
    static func modeConfig48(_ p: [UInt8]) -> ModeConfig {
        func b(_ i: Int) -> Int { i < p.count ? Int(p[i]) : 0 }
        let nameBytes = Array(p[safe: 6..<38]).prefix { $0 != 0 }
        return ModeConfig(index: b(0), name: String(decoding: nameBytes, as: UTF8.self),
                          editable: b(3) != 0, configured: b(4) != 0,
                          cnc: b(42), autoCNC: b(43), spatial: b(44), wind: b(45), anc: b(47))
    }
}

public extension BMAPBuild {
    static func modeConfig40(_ c: ModeConfig) -> BMAPFrame {
        var p = [UInt8](repeating: 0, count: 40)
        p[0] = UInt8(c.index)
        for (i, byte) in Array(c.name.utf8).prefix(32).enumerated() { p[3 + i] = byte }
        p[35] = UInt8(c.cnc); p[36] = UInt8(c.autoCNC); p[37] = UInt8(c.spatial)
        p[38] = UInt8(c.wind); p[39] = UInt8(c.anc)
        return BMAPFrame(fblock: Addr.modeConfig.0, function: Addr.modeConfig.1, op: .setGet, payload: p)
    }
}

extension Array where Element == UInt8 {
    subscript(safe range: Range<Int>) -> ArraySlice<UInt8> {
        self[Swift.max(0, range.lowerBound)..<Swift.min(count, range.upperBound)]
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ModeConfigTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add BoseKit/Sources/BoseKit/Protocol/ModeConfig.swift BoseKit/Tests/BoseKitTests/ModeConfigTests.swift
git commit -m "feat: mode config parse (48B) and build (40B)"
```

---

### Task 10: Transport — discovery + connect + firmware smoke (hardware)

**Files:**
- Create: `BoseKit/Sources/BoseKit/Transport/RFCOMMDelegate.swift`
- Create: `BoseKit/Sources/BoseKit/Transport/BluetoothTransport.swift`
- Create: `hushctl/Package.swift`, `hushctl/Sources/hushctl/main.swift` (CLI to exercise hardware)

**Interfaces:**
- Consumes: `BMAPFrame`, `BMAPFrame.parseAll`.
- Produces:
  - `actor BluetoothTransport` with:
    - `init(address: String, channel: UInt8)`
    - `func connect() async throws`
    - `func rawSend(_ data: Data) async throws` (write, no wait — internal)
    - a delegate that buffers inbound bytes
  - CLI `hushctl firmware` that connects and prints the firmware string.

> IOBluetooth cannot be unit-tested; verification is by running `hushctl` against the real headphones (which must be paired + connected, with Bluetooth permission granted to the terminal). The connect sequence mirrors the validated spike: `performSDPQuery(nil)` (~1.5 s run loop) → `openConnection(delegate)` (≤5 s) → `openRFCOMMChannelSync(channelID:, delegate:)` (≤3 s), then drain ~0.5 s.

- [ ] **Step 1: Implement the RFCOMM delegate + transport actor**

`RFCOMMDelegate.swift`:
```swift
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
```
`BluetoothTransport.swift` (connect + rawSend; a run loop pumped on a dedicated thread):
```swift
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
```

- [ ] **Step 2: Add the CLI**

`hushctl/Package.swift`:
```swift
// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "hushctl",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../BoseKit")],
    targets: [.executableTarget(name: "hushctl", dependencies: ["BoseKit"])]
)
```
`hushctl/Sources/hushctl/main.swift`:
```swift
import BoseKit
import Foundation

let mac = ProcessInfo.processInfo.environment["BOSE_MAC"] ?? "E4:58:BC:2E:0E:A7"
let transport = BluetoothTransport(address: mac, channel: 2)
try await transport.connect()
try transport.rawSend(BMAPBuild.get(Addr.firmware).encoded)
try await Task.sleep(nanoseconds: 800_000_000)
print("connected; sent firmware request — see next task for response reads")
```

- [ ] **Step 3: Build**

Run: `cd hushctl && swift build`
Expected: builds.

- [ ] **Step 4: Verify on hardware** (headphones connected; run in a real Terminal so the Bluetooth permission prompt can appear)

Run: `cd hushctl && swift run hushctl`
Expected: prints "connected; sent firmware request…" with no channel error. (Full response parsing arrives in Task 11.) If channel 2 fails, note it — Task 12 adds probing.

- [ ] **Step 5: Commit**

```bash
git add BoseKit/Sources/BoseKit/Transport hushctl
git commit -m "feat: RFCOMM transport connect + hushctl smoke"
```

---

### Task 11: Transport — request/response with 200ms delay + drain mode

**Files:**
- Modify: `BoseKit/Sources/BoseKit/Transport/BluetoothTransport.swift`
- Modify: `hushctl/Sources/hushctl/main.swift`

**Interfaces:**
- Produces on `BluetoothTransport`:
  - `func send(_ frame: BMAPFrame, drain: Bool = false, timeout: TimeInterval = 3) async throws -> [BMAPFrame]`
    — clears inbound, `rawSend`, waits 200 ms, then collects the first chunk within `timeout`; when `drain`, keeps reading with a rolling 0.5 s idle window; returns `BMAPFrame.parseAll(collected)`.

- [ ] **Step 1: Implement `send`** (append/replace in `BluetoothTransport.swift`)

```swift
public extension BluetoothTransport {
    func send(_ frame: BMAPFrame, drain: Bool = false, timeout: TimeInterval = 3) async throws -> [BMAPFrame] {
        inbound.removeAll()
        try rawSend(frame.encoded)
        try await Task.sleep(nanoseconds: 200_000_000) // required post-send delay
        let deadline = Date().addingTimeInterval(timeout)
        while inbound.isEmpty && Date() < deadline { try await Task.sleep(nanoseconds: 50_000_000) }
        if inbound.isEmpty { throw BMAPError.timeout }
        if drain {
            var lastCount = -1
            while lastCount != inbound.count {
                lastCount = inbound.count
                try await Task.sleep(nanoseconds: 500_000_000) // idle window
            }
        }
        return BMAPFrame.parseAll(inbound)
    }
}
```

- [ ] **Step 2: Update the CLI to read firmware + battery**

`hushctl/Sources/hushctl/main.swift` (replace the smoke body):
```swift
import BoseKit
import Foundation

let mac = ProcessInfo.processInfo.environment["BOSE_MAC"] ?? "E4:58:BC:2E:0E:A7"
let t = BluetoothTransport(address: mac, channel: 2)
try await t.connect()

let fw = try await t.send(BMAPBuild.get(Addr.firmware))
if let f = fw.first(where: { ($0.fblock, $0.function) == Addr.firmware }) {
    print("Firmware: \(BMAPParse.firmware(f.payload))")
}
let bat = try await t.send(BMAPBuild.get(Addr.battery))
if let b = bat.first(where: { ($0.fblock, $0.function) == Addr.battery }) {
    print("Battery: \(BMAPParse.battery(b.payload))%")
}
```

- [ ] **Step 3: Build**

Run: `cd hushctl && swift build`
Expected: builds.

- [ ] **Step 4: Verify on hardware**

Run: `cd hushctl && swift run hushctl`
Expected: prints `Firmware: 1.6.7+g6ebabd2` and `Battery: NN%`. This is the definitive proof the native Swift stack reads BMAP. If it times out, the channel is wrong → do Task 12 first.

- [ ] **Step 5: Commit**

```bash
git add BoseKit/Sources/BoseKit/Transport/BluetoothTransport.swift hushctl/Sources/hushctl/main.swift
git commit -m "feat: BMAP request/response with drain mode; hushctl reads firmware+battery"
```

---

### Task 12: Transport — channel probing + persistent connection + reconnect

**Files:**
- Modify: `BoseKit/Sources/BoseKit/Transport/BluetoothTransport.swift`

**Interfaces:**
- Produces on `BluetoothTransport`:
  - `static func discover(address: String) async throws -> BluetoothTransport` — tries channels `[configured, 2, 8, 9]`, confirms each by sending GET `[0.5]` and requiring a parseable `[0.5]` reply; the first that answers wins.
  - `var isConnected: Bool` (tracked from open/close/traffic, not `IOBluetoothDevice.isConnected()`).
  - `func ensureConnected() async throws` — reconnects with backoff if the channel closed.
  - On `rfcommChannelClosed`, mark disconnected; a caller's next `send` triggers `ensureConnected()`.

- [ ] **Step 1: Implement probing + reconnect**

```swift
public extension BluetoothTransport {
    static func discover(address: String, preferred: UInt8 = 2) async throws -> BluetoothTransport {
        for ch in [preferred, 2, 8, 9].reduced() {
            let t = BluetoothTransport(address: address, channel: ch)
            do {
                try await t.connect()
                let reply = try await t.send(BMAPBuild.get(Addr.firmware), timeout: 2)
                if reply.contains(where: { ($0.fblock, $0.function) == Addr.firmware }) { return t }
            } catch { continue }
        }
        throw BMAPError.notConnected
    }
}

private extension Array where Element == UInt8 {
    func reduced() -> [UInt8] { var seen = Set<UInt8>(); return filter { seen.insert($0).inserted } }
}
```
Add connection-state tracking: set a `private var connected = false` flag `true` at end of `connect()`, `false` in the delegate's `onClose`, and have `send` call an `ensureConnected()` that re-runs `connect()` (with a short backoff) when `!connected`.

- [ ] **Step 2: Wire the CLI to use discovery**

In `hushctl/Sources/hushctl/main.swift`, replace `BluetoothTransport(address:channel:)` + `connect()` with:
```swift
let t = try await BluetoothTransport.discover(address: mac)
```

- [ ] **Step 3: Build**

Run: `cd hushctl && swift build`
Expected: builds.

- [ ] **Step 4: Verify on hardware**

Run: `cd hushctl && swift run hushctl`
Expected: same firmware+battery output; and if you toggle the headphones off/on mid-session a subsequent run reconnects. Note in a comment which channel actually answered for 0x4066 (feeds the `lonestarr` profile in Task 13).

- [ ] **Step 5: Commit**

```bash
git add BoseKit/Sources/BoseKit/Transport/BluetoothTransport.swift hushctl/Sources/hushctl/main.swift
git commit -m "feat: RFCOMM channel probing and persistent connection"
```

---

### Task 13: DeviceProfile + BoseDevice typed API (mock-transport tests)

**Files:**
- Create: `BoseKit/Sources/BoseKit/Device/DeviceProfile.swift`
- Create: `BoseKit/Sources/BoseKit/Device/FrameSender.swift`
- Create: `BoseKit/Sources/BoseKit/Device/BoseDevice.swift`
- Test: `BoseKit/Tests/BoseKitTests/BoseDeviceTests.swift`

**Interfaces:**
- Consumes: all builders/parsers; `BluetoothTransport.send`.
- Produces:
  - `protocol FrameSender: Sendable { func send(_ frame: BMAPFrame, drain: Bool, timeout: TimeInterval) async throws -> [BMAPFrame] }` — `BluetoothTransport` conforms; tests use a mock.
  - `struct DeviceProfile: Sendable { var productID: UInt16; var codename: String; var rfcommChannel: UInt8; var hasAudioSettingsRegister: Bool; var modeConfigStatusLength: Int; var modeConfigSetLength: Int; var editableSlots: ClosedRange<Int> }` with `static let wolverine` and `static let lonestarr` (a copy of wolverine, corrected in Milestone 0).
  - `actor BoseDevice` with typed methods: `battery() async throws -> Int`, `firmware()`, `name()/setName(_:)`, `currentMode()/setMode(_:)`, `audioSettings()/setCNC(_:)/setANC(_:)/setWind(_:)/setSpatial(_:)` (read-modify-write on `[31.10]`), `eq()/setEQ(band:value:)`, `sidetone()/setSidetone(_:)`, `multipoint()/setMultipoint(_:)`, `autoPause()/setAutoPause(_:)`, `autoAnswer()/setAutoAnswer(_:)`, `voicePrompts()/setVoicePrompts(enabled:language:)`, `modes()`, `saveProfile(_:)`, `deleteProfile(name:)`.

- [ ] **Step 1: Write the failing test** (mock sender records frames and returns canned replies)

```swift
import Testing
@testable import BoseKit

actor MockSender: FrameSender {
    var sent: [BMAPFrame] = []
    var replies: [[BMAPFrame]] = []
    func send(_ frame: BMAPFrame, drain: Bool, timeout: TimeInterval) async throws -> [BMAPFrame] {
        sent.append(frame)
        return replies.isEmpty ? [] : replies.removeFirst()
    }
}

@Test func readsBatteryThroughDevice() async throws {
    let mock = MockSender()
    await mock.setReplies([[BMAPFrame(fblock: 0x02, function: 0x02, op: .status, payload: [0x50,0xff,0xff,0x00])]])
    let dev = BoseDevice(sender: mock, profile: .wolverine)
    #expect(try await dev.battery() == 80)
}

@Test func setCNCReadModifyWrites() async throws {
    let mock = MockSender()
    // first reply: current audio settings; device reads then writes
    await mock.setReplies([
        [BMAPFrame(fblock: 0x1f, function: 0x0a, op: .status, payload: [0x00,0x00,0x00,0x00,0x01])],
        [BMAPFrame(fblock: 0x1f, function: 0x0a, op: .status, payload: [0x05,0x00,0x00,0x00,0x01])],
    ])
    let dev = BoseDevice(sender: mock, profile: .wolverine)
    try await dev.setCNC(5)
    let sent = await mock.sent
    #expect(sent.last?.op == .setGet)
    #expect(sent.last?.payload == [0x05,0x00,0x00,0x00,0x01]) // cnc=5 preserved anc=1
}
```
(Add a `MockSender.setReplies(_:)` helper and make its `sent` accessible.)

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter BoseDeviceTests`
Expected: FAIL.

- [ ] **Step 3: Write minimal implementation**

`FrameSender.swift`:
```swift
import Foundation
public protocol FrameSender: Sendable {
    func send(_ frame: BMAPFrame, drain: Bool, timeout: TimeInterval) async throws -> [BMAPFrame]
}
extension BluetoothTransport: FrameSender {}
```
(Adjust `BluetoothTransport.send` signature to match: `func send(_:drain:timeout:)` — already close; give `drain`/`timeout` defaults via the protocol call sites.)

`DeviceProfile.swift`:
```swift
public struct DeviceProfile: Sendable {
    public var productID: UInt16; public var codename: String; public var rfcommChannel: UInt8
    public var hasAudioSettingsRegister: Bool
    public var modeConfigStatusLength: Int; public var modeConfigSetLength: Int
    public var editableSlots: ClosedRange<Int>

    public static let wolverine = DeviceProfile(
        productID: 0x4082, codename: "wolverine", rfcommChannel: 2,
        hasAudioSettingsRegister: true, modeConfigStatusLength: 48, modeConfigSetLength: 40,
        editableSlots: 4...10)
    // Starts identical to wolverine; corrected in Milestone 0 (Task 14).
    public static let lonestarr = DeviceProfile(
        productID: 0x4066, codename: "lonestarr", rfcommChannel: 2,
        hasAudioSettingsRegister: true, modeConfigStatusLength: 48, modeConfigSetLength: 40,
        editableSlots: 4...10)
}
```
`BoseDevice.swift` (representative methods; implement the rest following the same read-modify-write / builder pattern and the address table):
```swift
import Foundation

public actor BoseDevice {
    private let sender: FrameSender
    public let profile: DeviceProfile
    public init(sender: FrameSender, profile: DeviceProfile) { self.sender = sender; self.profile = profile }

    private func first(_ frames: [BMAPFrame], _ addr: (UInt8, UInt8)) throws -> BMAPFrame {
        if let e = frames.compactMap(BMAPError.from).first { throw e }
        guard let f = frames.first(where: { ($0.fblock, $0.function) == addr }) else { throw BMAPError.unexpectedResponse }
        return f
    }

    public func battery() async throws -> Int {
        let r = try await sender.send(BMAPBuild.get(Addr.battery), drain: false, timeout: 3)
        return BMAPParse.battery(try first(r, Addr.battery).payload)
    }
    public func audioSettings() async throws -> AudioSettings {
        let r = try await sender.send(BMAPBuild.get(Addr.audioSettings), drain: false, timeout: 3)
        return BMAPParse.audioSettings(try first(r, Addr.audioSettings).payload)
    }
    public func setCNC(_ level: Int) async throws {
        var s = try await audioSettings(); s.cnc = level; s.autoCNC = 0
        _ = try await sender.send(BMAPBuild.audioSettings(s), drain: false, timeout: 3)
    }
    public func setEQ(band: Int, value: Int) async throws {
        _ = try await sender.send(BMAPBuild.eqBand(value: value, band: band), drain: false, timeout: 3)
    }
    public func setMode(index: Int, announce: Bool = false) async throws {
        _ = try await sender.send(BMAPBuild.setMode(index: index, announce: announce), drain: true, timeout: 3)
    }
    // …implement name/eq(read)/sidetone/multipoint/autoPause/autoAnswer/voicePrompts/
    //    setANC/setWind/setSpatial (read-modify-write on audioSettings)/modes/saveProfile/
    //    deleteProfile following the same pattern + the Addr table + §4.4.
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter BoseDeviceTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add BoseKit/Sources/BoseKit/Device BoseKit/Tests/BoseKitTests/BoseDeviceTests.swift
git commit -m "feat: DeviceProfile and typed BoseDevice API"
```

---

### Task 14: Milestone 0 — verify the lonestarr profile on hardware

**Files:**
- Modify: `hushctl/Sources/hushctl/main.swift` (add subcommands)
- Modify: `BoseKit/Sources/BoseKit/Device/DeviceProfile.swift` (correct `lonestarr` from findings)
- Create: `docs/superpowers/notes/2026-xx-lonestarr-verification.md` (record findings)

**Interfaces:**
- Consumes: `BoseDevice`, `BluetoothTransport.discover`.
- Produces: a verified `DeviceProfile.lonestarr` and a findings note.

> This is the acceptance gate for the whole foundation on the real 0x4066 device. Each write is applied, then re-read (and audibly/visually confirmed), then reverted.

- [ ] **Step 1: Add a `status` + `verify` command to hushctl**

Extend `main.swift` to parse `CommandLine.arguments[1]`:
```swift
let dev = BoseDevice(sender: try await BluetoothTransport.discover(address: mac), profile: .lonestarr)
switch CommandLine.arguments.dropFirst().first ?? "status" {
case "status":
    print("FW:", try await dev.firmware())
    print("Battery:", try await dev.battery())
    print("Mode:", try await dev.currentMode())
    print("EQ:", try await dev.eq())
    print("Audio:", try await dev.audioSettings())
    print("Multipoint:", try await dev.multipoint())
    print("Sidetone:", try await dev.sidetone())
default: print("unknown command")
}
```

- [ ] **Step 2: Verify reads on hardware**

Run: `cd hushctl && swift run hushctl status`
Expected: every field matches what `~/bosectl` (`BOSE_MAC=... ./bosectl status`) prints for the same device. Record which RFCOMM channel `discover` chose.

- [ ] **Step 3: Verify each write, one at a time** (add temporary `verify` handlers, or a REPL). For each, apply → re-read → confirm → revert:
  - `setCNC(5)` then `setCNC(0)` — CNC changes in `audioSettings()` and is audible.
  - `setANC(false)`/`setANC(true)`.
  - `setEQ(band: 0, value: 6)` then back to original — `eq()` reflects it.
  - `setMode(index: 1)` (Aware) then `setMode(index: 0)` (Quiet).
  - `setSpatial(2)` / back — confirm `[31.10]` byte 2 or fall back to ModeConfig if `[31.10]` errors (FuncNotSupp) → set `hasAudioSettingsRegister = false`.
  - `setSidetone`, `setMultipoint`, `setAutoPause`, `setAutoAnswer`.
  - `setVoicePrompts(enabled: false)` — determine whether bit5 or bit6 is the enabled bit; record it.
  - Create/switch/delete a custom profile — confirm ModeConfig payload length (48/40) is right; if writes reject with err 8 on a supposedly editable slot, adjust `editableSlots`.

- [ ] **Step 4: Correct the `lonestarr` profile + write the findings note**

Update `DeviceProfile.lonestarr` (channel, `hasAudioSettingsRegister`, ModeConfig lengths, editableSlots) to the verified values, and record everything (including the voice-prompt enabled bit) in `docs/superpowers/notes/2026-xx-lonestarr-verification.md`. If the voice-prompt bit differs, fix `BMAPBuild.setVoicePrompts` and its test.

- [ ] **Step 5: Run the full test suite + commit**

Run: `cd BoseKit && swift test` (all green)
```bash
git add BoseKit hushctl docs/superpowers/notes
git commit -m "feat: verify and correct lonestarr (0x4066) profile on hardware"
```

---

## Self-Review

**Spec coverage:** Frame format/operators (Tasks 2–4) ✓; per-feature read/write — battery, firmware, name, mode, CNC, EQ, spatial, wind, ANC, sidetone, multipoint, auto-pause, auto-answer, voice prompts (Tasks 5–8, 13) ✓; profiles/ModeConfig (Task 9, 13) ✓; transport sequence + drain + persistent + probing (Tasks 10–12) ✓; device profiles + gen-1 caveat + Milestone 0 (Tasks 13–14) ✓; error codes (Task 4) ✓. Buttons parse/build is specified in the spec (§4.3) but folded into the "follow the same pattern" note in Task 13 — **if the executor wants a dedicated test, add a Buttons task mirroring Task 8** (parse `[1.9]` → `[btn,event,action,mask…]`, build `[btn,event,action]`). UI is intentionally out of scope (Plan 2).

**Placeholder scan:** Task 13's `BoseDevice` lists "…implement the rest following the same pattern" for the remaining typed methods — these are mechanical repeats of the shown `battery`/`setCNC` pattern against the Task-4 `Addr` table and the Task 5–9 parsers/builders, not undefined behavior; acceptable, but the executor writes a test per method as they go.

**Type consistency:** `FrameSender.send(_:drain:timeout:)` is used consistently in Tasks 11–13; `AudioSettings`, `EQBand`, `ModeConfig`, `DeviceProfile` names match across tasks; `Addr` tuple names match the address table.

---

## Execution Handoff

Plan 2 (the SwiftUI **Hush** app on top of `BoseKit`) is written after this foundation is verified on hardware (Milestone 0), so its UI binds to a proven API.
