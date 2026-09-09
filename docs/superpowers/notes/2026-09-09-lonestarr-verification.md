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
