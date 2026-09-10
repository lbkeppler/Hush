# Hush — Native macOS Bose QC Ultra Controller · Design Spec

Date: 2026-09-09
Status: Draft for review
Author: Lucas Keppler (with Claude)

## 1. Overview

A native macOS app (SwiftUI) to manage **Bose QuietComfort Ultra** headphones
without the official mobile-only Bose app. It talks to the headphones over
Bluetooth Classic **RFCOMM** using the reverse-engineered **BMAP** protocol,
ported to native Swift.

Validated feasibility (spike, 2026-09-09): RFCOMM + BMAP works on the target Mac
and headphones; `bosectl` read full live state (battery, EQ, mode, firmware) from
the actual device. See `bose-macos-app-project` / `bosectl-reference` memories.

Target device: **Bose QC Ultra Headphones**, MAC `E4:58:BC:2E:0E:A7`, product
`0x4066` (gen 1, codename `lonestarr`), firmware `1.6.7+g6ebabd2`.

## 2. Scope

**v1 = full feature set** (user decision). Read and write:

- Noise: ANC on/off, CNC level 0–10, Wind Block
- Modes: Quiet / Aware / Immersion / Cinema
- Spatial audio: off / room / head
- Equalizer: 3-band bass/mid/treble (−10..+10)
- Custom profiles: list / create / update / delete / switch
- Settings: sidetone, multipoint, auto-pause on remove, auto-answer, voice
  prompts (+language), device name, button remap
- Status: battery %, current mode, firmware, connection state

**UI:** two surfaces from the approved design — a menu-bar popover and a full
window (dark + light).

**Non-goals (v1):** cloud/account features, ECDH-gated SET operations, firmware
update, multi-device management beyond the one paired headset, iOS/iPadOS,
App Store distribution/notarization (personal developer build first).

## 3. Architecture

Layers, bottom-up. Everything below the UI ships as a Swift package `BoseKit`
so the protocol/transport can be unit-tested and reused headless.

```
UI (SwiftUI)            MenuBar popover · Window (Noise/Sound/Modes/Spatial/
                        Profiles/Settings) · design tokens · dark+light
BoseController          @Observable app state; live device state; debounced
  (app state)           writes; connection lifecycle; error/empty/reconnect
BoseDevice              typed high-level API (battery, setCNC, setEQ, setMode,
  + DeviceProfile       profiles…); maps features → BMAP; per-model config
BMAPCodec               pure Swift, no I/O; encode/decode frames; split
                        multi-frame; parsers/builders per feature
BluetoothTransport      IOBluetooth RFCOMM; discovery; connect sequence;
                        async send/recv; drain; reconnection
```

**Design principles**
- The **codec is pure and I/O-free** — the only place with tricky byte logic,
  so it is fully unit-tested against captured fixtures. No Bluetooth in it.
- **Transport** hides all IOBluetooth delegate/run-loop mess behind
  `func send(_ frame: Data, drain: Bool) async throws -> [BMAPFrame]`.
- **DeviceProfile** captures per-model differences as data (addresses, payload
  lengths, channel, feature availability), so supporting another Bose later is a
  new profile, not new logic.
- Writes are **debounced/coalesced** in `BoseController` (dragging the EQ or CNC
  must not flood RFCOMM).

## 4. BMAP protocol (port target)

Source of truth: `~/bosectl` (Python `pybmap`). This section captures what the
Swift port implements; verify against `python/pybmap/{protocol,constants,
connection}.py` and `devices/{parsers,qc_ultra2}.py`.

### 4.1 Frame format

```
Byte 0  fblock   function block id
Byte 1  func     function id within block
Byte 2  flags    operator in low nibble (device_id/port_num = 0)
Byte 3  length   payload length (0–255)
Byte 4+ payload  length bytes
```
No preamble, no checksum, no terminator. Multi-frame responses are concatenated
and split by walking each packet's length (`pos += 4 + length`); a packet whose
length overruns the buffer is truncated → drop.

### 4.2 Operators

| Code | Name | Use |
|---|---|---|
| 1 | GET | read (unauthenticated everywhere) |
| 2 | SETGET | write+readback — **unauthenticated** on Settings `[1.x]` & AudioModes `[31.x]` |
| 5 | START | trigger action — **unauthenticated** on AudioModes `[31.x]`, Control `[7.x]` |
| 3 | STATUS | response / unsolicited |
| 4 | ERROR | response, code in payload[0] |
| 6 | RESULT | action ok |
| 7 | PROCESSING | async in progress (treat as success) |
| 0 | SET | **cloud/ECDH gated — never used** |

All writes route through SETGET or START to avoid the auth gate. `SET` and the
Authentication block `[18.x]` are out of scope.

### 4.3 Per-feature command map (QC Ultra 2 reference — verify on 0x4066)

Notation `[fblock.func]`; request bytes `fblock func flags len payload`.

| Feature | Read | Write | Payload / parse |
|---|---|---|---|
| Battery | `02 02 01 00` | — | `%` = payload[0] |
| Firmware | `00 05 01 00` | — | ASCII string |
| Device name | `01 02 01 00` | SETGET `01 02 02 <len> <utf8>` | read = [flag, utf8…] (name = [1:]); write = raw utf8 ≤31 |
| Current mode | `1f 03 01 00` | START `1f 03 05 02 <idx> <announce>` | idx: quiet0 aware1 immersion2 cinema3 |
| Live audio register `[31.10]` | `1f 0a 01 00` | SETGET `1f 0a 02 05 <cnc> <autoCNC> <spatial> <wind> <anc>` | 5 bytes `[cnc,autoCNC,spatial,wind,anc]`; **read-modify-write** for cnc/wind/spatial/anc |
| CNC (read) | `01 05 01 00` | via `[31.10]` | payload `[steps, current, flags]`; current=payload[1], max=payload[0]−1; **0 = max ANC, 10 = ambient** |
| EQ | `01 07 01 00` | SETGET per band `01 07 02 02 <val> <band>` | 3×`[min,max,cur,band]` signed; band 0/1/2 = bass/mid/treble; val −10(0xf6)..+10(0x0a) |
| Spatial | via `[31.10]` byte2 | via `[31.10]` | 0 off / 1 room / 2 head |
| Sidetone | `01 0b 01 00` | SETGET `01 0b 02 02 01 <lvl>` | lvl 0 off /1 high /2 medium /3 low (read = payload[1]) |
| Multipoint | `01 0a 01 00` | SETGET `[0/1]` | read enabled = `payload[0] & 0x02`; write plain 0/1 (asymmetric) |
| Auto-pause | `01 18 01 00` | SETGET `[0/1]` | bool(payload[0]) |
| Auto-answer | `01 1b 01 00` | SETGET `[0/1]` | bool(payload[0]) |
| Voice prompts | `01 03 01 00` | SETGET byte0 | enabled bit5 **or bit6 — verify**; lang = byte0 & 0x1F |
| Buttons | `01 09 01 00` | SETGET `[btn, event, action]` | enums in constants |
| Profiles list | START `1f 01 05 00`, drain | — | collect all `[31.6]` STATUS frames |
| Profile config | `[31.6]` STATUS 48B | SETGET `[31.6]` 40B | see §4.4 |
| Switch profile | — | START `[31.3]` by index | preset name→index, else search custom |
| Power off | — | START `07 04 05 01 00` | — |
| Pairing mode | — | START `04 08 05 01 01` | — |

### 4.4 ModeConfig (custom profiles, QC Ultra 2 layout)

- **SETGET write, 40 bytes:** `[0]=idx (5–10 custom, 4=Home; 0–3 presets reject
  with Runtime err 8), [1:3]=voicePrompt, [3:35]=name utf8 null-padded to 32,
  [35]=cnc, [36]=autoCNC, [37]=spatial, [38]=wind, [39]=ancToggle`.
- **STATUS read, 48 bytes:** offsets differ — `[0]=idx, [1:3]=prompt, [3]=editable,
  [4]=configured, [6:38]=name(32), [42]=cnc, [43]=autoCNC, [44]=spatial,
  [45]=wind, [47]=ancToggle`.
- Create = first free editable+unconfigured slot; Update = match by name, require
  editable, read-modify-write; Delete = overwrite slot with name "None", zeros.

### 4.5 Error codes (ERROR op 4, payload[0])

1 Length · 2 Chksum · 3 FblockNotSupp · 4 FuncNotSupp · **5 OpNotSupp/auth
(→ wrong operator, use SETGET/START)** · 6 InvalidData · 7 DataUnavail ·
8 Runtime · 9 Timeout · 10 InvalidState · 15 InvalidTransition · 20 InsecureTransport.

## 5. Device support & the 0x4066 caveat

**0x4066 (our gen-1 Ultra) is not implemented or verified anywhere in bosectl.**
The reference is **0x4082 (QC Ultra 2 / wolverine)**. Our own `bosectl status`
run used the Ultra-2 config and read every field correctly, so reads are
empirically compatible; writes are inference until proven on hardware.

Model differences are expressed as a `DeviceProfile` value (addresses, ModeConfig
lengths 48/40 vs 47/39, RFCOMM channel, `ancToggle` presence, feature set). v1
ships a `lonestarr` profile that **starts as a copy of `wolverine`** and is
corrected during the verification milestone.

Must verify on the real device (Milestone 0):
1. RFCOMM channel (probe order 2 → 8 → 9, confirm via GET `[0.5]`).
2. Whether `[31.10]` live register exists (else fall back to editing ModeConfig `[31.6]`).
3. ModeConfig payload lengths (48/40 vs 47/39) and `ancToggle` byte.
4. Voice-prompts enabled bit (bit5 vs bit6).
5. Each write actually takes effect (read-back + audible check).

## 6. Transport & sequencing

macOS connect sequence (matches the validated spike):
1. `IOBluetoothDevice(addressString:)`.
2. `performSDPQuery(nil)`; pump run loop ~1.5 s.
3. `openConnection(delegate)`; wait ≤5 s for `connectionComplete`.
4. `openRFCOMMChannelSync(_, withChannelID: <channel>, delegate:)`; wait ≤3 s.
5. **Drain** ~0.5 s and flush startup/beacon frames (`FF 55 02 …`).

Request/response: **no transaction id** — synchronous positional correlation.
Before each send clear the RX queue, `writeSync`, **wait ~200 ms (required)**,
then read up to 3 s for the first chunk; verify identity by matching
`fblock`/`func`. **Drain mode** for multi-STATUS commands: keep reading with a
rolling 0.5 s idle timeout, then split by length.

The Swift port wraps the delegate callbacks with continuations to expose
`async` calls, and runs the IOBluetooth run loop on a dedicated thread/queue.

Unsolicited frames (STATUS notifications, `FF 55` beacon, PROCESSING acks) can
arrive any time — ignore anything that isn't a valid BMAP frame addressed to the
outstanding request; surface STATUS notifications as live state updates.

## 7. UI

Implements the approved "Quiet instrument" design (artifact
`83e0050e-9df4-4385-ace9-7ce217b62775`). Tokens: ink `#12151A`, surface
`#191D24`, champagne accent `#E4C39A` (dark) / `#B8895A` (light) for active/live
only; Space Grotesk for numerals/headings (bundled) with SF Pro fallback; aurora
gradient reserved for the spatial visualization.

- **MenuBarExtra popover** (~340 pt): battery, CNC control, ANC/Wind, mode chips,
  EQ presets, "Open Hush".
- **Main window** (~980×800): sidebar (device summary + sections Noise, Sound,
  Modes, Spatial, Profiles, Settings) and a section detail area. Noise = CNC dial
  hero + ANC/Wind + modes; Sound = interactive 3-band EQ; Modes/Profiles = presets
  + editable custom profile cards; Spatial = off/room/head + visualization;
  Settings = sidetone, multipoint, auto-pause, auto-answer, voice prompts, name,
  buttons.
- Both bind one `BoseController`. Present CNC as an intuitive "strength" =
  `10 − rawCnc` (0 raw = max ANC = full). Disable/annotate CNC when ANC off or
  Wind on (audibility coupling). Empty/error states give direction, not mood
  (e.g. "Headphones not connected — turn them on and connect in System Settings").

## 8. Edge cases & rules

- CNC inverted (0 = max ANC); audible only with ANC on and Wind off; `autoCNC=1`
  → Runtime err 8 (never send).
- EQ values signed `Int8`. One SETGET per band.
- Presets 0–3 are firmware-locked (Runtime err 8) — only slots 4–10 editable.
- Multipoint read masks bit1; write sends plain 0/1.
- Name: GET has a leading flag byte, SETGET writes raw UTF-8 (no flag).
- Multi-frame: never assume one packet per read; accumulate and re-split.
- **Persistent connection** (decided): hold one long-lived RFCOMM connection for
  the app's lifetime, tolerate unsolicited pushes, and auto-reconnect on drop with
  backoff. `isConnected()` is unreliable — track state from the channel
  delegate/traffic, don't gate on it. No keepalive is defined by the protocol; add
  a lightweight periodic GET (e.g. battery) as a liveness probe if idle drops occur.
- Debounce EQ/CNC drags (e.g. 120–200 ms) into a single SETGET.

## 9. Testing

- **BMAPCodec:** unit tests (TDD) against real byte fixtures copied from
  `~/bosectl/captures/` and `fixtures/` — encode produces exact bytes, decode
  parses known frames, multi-frame split, signed EQ, error frames.
- **DeviceProfile/BoseDevice:** table-driven tests mapping feature calls to
  expected frames.
- **Transport:** integration-tested against the real headphones (manual, like the
  spike probe) — cannot unit-test IOBluetooth.
- **Milestone 0 hardware verification** doubles as the acceptance test for the
  `lonestarr` profile.

## 10. Packaging & permissions

- SwiftUI app, macOS 14+ (Sonoma). Xcode project; `BoseKit` as a local Swift
  package.
- Entitlement `com.apple.security.device.bluetooth`. Likely non-sandboxed
  developer build first; if sandboxed, add the Bluetooth entitlement and verify
  RFCOMM still opens.
- Bundle Space Grotesk (OFL) or fall back to SF Pro.
- Personal developer build (run locally); signing/notarization deferred.

## 11. Proposed module layout

```
BoseKit/ (Swift package)
  Sources/BoseKit/
    Transport/   BluetoothTransport.swift, RFCOMMChannel+async.swift, Discovery.swift
    Protocol/    BMAPFrame.swift, BMAPCodec.swift, Operators.swift, Errors.swift
    Device/      BoseDevice.swift, DeviceProfile.swift, Profiles/lonestarr.swift, wolverine.swift
    Features/    Battery, Noise, EQ, Modes, Spatial, Settings, ProfilesConfig
  Tests/BoseKitTests/  (fixtures/, codec + device tests)
Hush/ (app target)
  App.swift (MenuBarExtra + WindowGroup), BoseController.swift
  UI/ Tokens.swift, MenuBarView.swift, MainWindow/*.swift (sections), Components/*
```

## 12. Risks & open questions

- **gen-1 (0x4066) unverified for writes** — mitigated by Milestone 0. Reads
  already proven.
- IOBluetooth async wrapping correctness (run loop on background queue) — proven
  reachable in the spike; needs careful lifecycle handling.
- Voice-prompts enabled bit ambiguity — verify.
- Persistent connection adds lifecycle/reconnection complexity vs per-command
  sessions; mitigated by a dedicated transport actor owning the connection.
- Button remap behavioral effect not fully confirmed even on Ultra 2.

## Decisions (settled 2026-09-09)

1. App name: **Hush**.
2. Connection model: **persistent** long-lived RFCOMM connection with
   auto-reconnect (see §6, §8).
3. Minimum OS: **macOS 14 (Sonoma)**.
