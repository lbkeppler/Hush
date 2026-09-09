# Milestone 0 — lonestarr (Bose QC Ultra gen 1, 0x4066) hardware verification

Date: 2026-09-09. Device: Bose QC Ultra Headphones, MAC `E4:58:BC:2E:0E:A7`,
product `0x4066` (`lonestarr`), firmware `1.6.7+g6ebabd2`. Verified with the
native `hushctl status` / `verify` harness (BoseKit), state restored after.

## Transport
- RFCOMM connect works via `discover` (SDP query → `openConnection` baseband wait
  → `openRFCOMMChannelSync` on **channel 2** → drain). Channel 2 is the BMAP
  channel for this device (same as wolverine).

## Reads (GET) — what gen-1 supports
| Field | Address | Result |
|---|---|---|
| Firmware | `[0.5]` | ✅ `1.6.7+g6ebabd2` |
| Battery | `[2.2]` | ✅ 60% |
| Current mode | `[31.3]` | ✅ 0 (Quiet) |
| EQ (3-band) | `[1.7]` | ✅ +8 / +4 / +5 |
| **Audio settings `[31.10]`** | `[31.10]` | ❌ **FuncNotSupp (err 4)** |
| Sidetone | `[1.11]` | ✅ 2 (medium) |
| Multipoint | `[1.10]` | ✅ true |
| Auto-pause | `[1.18]` | ✅ true |
| Auto-answer | `[1.1b]` | ✅ true |
| Name | `[1.2]` | ✅ "Bose QC Ultra Headphones" |

## Writes (SETGET / START) — verified apply→read-back→revert
| Setting | Result |
|---|---|
| EQ band | ✅ PASS |
| Mode (Quiet↔Aware) | ✅ PASS |
| Sidetone | ✅ PASS |
| Auto-pause | ✅ PASS |
| Auto-answer | ✅ PASS |
| Multipoint | ⚠️ FAIL — wrote false, read back true (write had no immediate effect) |
| CNC / ANC / Wind / Spatial | ⛔ UNSUPPORTED — depend on `[31.10]` |

## Key finding: no `[31.10]` register on gen-1
Unlike the QC Ultra 2 (wolverine), the gen-1 (lonestarr) returns **FuncNotSupp**
for `[31.10]` AudioModesSettingsConfig. This is the same situation as prince/qc45
in bosectl. Consequences:
- Noise control (CNC), ANC on/off, Wind block, and Spatial audio **cannot** be
  set via `[31.10]`. They must be read/written through the **current mode's
  ModeConfig `[31.6]`** (read-modify-write), per bosectl's prince/qc45 path
  (`~/bosectl/python/pybmap/connection.py:383-397`).
- `DeviceProfile.lonestarr` must set `hasAudioSettingsRegister = false` and route
  CNC/ANC/Wind/Spatial through the `[31.6]` fallback.

## Multipoint write
The `[1.10]` SETGET of a plain `0` did not change the read-back (still true).
Likely async application or a value/format nuance. Low priority; investigate with
a post-write delay + re-read, or compare bosectl's `build_toggle` behavior.

## Actions
1. Set `DeviceProfile.lonestarr.hasAudioSettingsRegister = false`.
2. Implement the `[31.6]` ModeConfig read-modify-write fallback for CNC/ANC/Wind/
   Spatial in `BoseDevice` (Task 15).
3. Re-run `hushctl verify` on hardware to confirm CNC/ANC/Spatial then pass.
4. Investigate multipoint write timing.

## Task 15 fallback verified broken on hardware (2026-09-09)
Re-running `hushctl verify` against real lonestarr hardware after Task 15 showed
the `[31.6]` ModeConfig fallback does **not** work:
- The active mode (index 0, "Quiet") is a firmware-locked preset. Writing its
  `ModeConfig` back via `[31.6]` SETGET hits **Runtime err 8** — the same "can't
  modify a locked slot" error `saveProfile` already guards against for
  `editableSlots`, just reached via a different path (live noise settings apply
  to whichever mode is *currently active*, which for most users most of the time
  is a locked preset, not a custom slot).
- Independent of the lock issue, the 48-byte `ModeConfig` STATUS layout used by
  `BMAPParse.modeConfig48` does not match this device family: it's actually
  **47 bytes** here and has **no ANC byte** at all, so reads through that path
  returned meaningless values even before the write was attempted.

## v1 decision
Per product decision, **v1 ships without live ANC/CNC/Wind/Spatial control on
devices without `[31.10]`** (gen-1 / lonestarr). There is no verified live-write
path over firmware presets on this device family, and the ModeConfig layout
assumed by the Task 15 fallback is wrong for it besides. Rather than ship a
broken or misleading control, `BoseDevice.audioSettings()`/`setCNC`/`setANC`/
`setWind`/`setSpatial` now throw `BMAPError.unsupported` immediately when
`profile.hasAudioSettingsRegister == false` (Task 16) — surfaced by `hushctl` as
a clean `UNSUPPORTED`, same as a device-reported `FuncNotSupp`.

Live noise control on gen-1 is **post-v1**: it needs a custom-mode model (write
to one of the user's own editable slots — `[31.6]` `editableSlots` 4...10, which
*is* writable per `saveProfile` — rather than the currently-active locked
preset), plus the correct 47-byte/no-ANC-byte payload layout for this device
family. That is out of scope here and tracked separately.
