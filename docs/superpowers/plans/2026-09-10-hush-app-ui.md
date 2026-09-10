# Hush App (SwiftUI UI) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Build "Hush", a native macOS SwiftUI app over `BoseKit` — a menu-bar popover + a main window — to control the user's Bose QC Ultra (gen-1) with the settings that are verified to work.

**Architecture:** A `Hush` SwiftPM executable target (SwiftUI `App` with `MenuBarExtra` + `WindowGroup`) depends on the local `BoseKit` package. A single `@MainActor @Observable BoseController` owns the persistent `BluetoothTransport` + `BoseDevice`, exposes live state and debounced intents, and both surfaces bind to it. Views are feature-gated by `DeviceProfile` flags so unsupported controls (live ANC/CNC on gen-1) are hidden, not broken.

**Tech Stack:** Swift 6.3 / SwiftPM, SwiftUI (macOS 14+), Swift Testing, `BoseKit` (local). No third-party deps. Space Grotesk bundled (OFL) with SF fallback.

**Spec:** `docs/superpowers/specs/2026-09-09-bose-macos-app-design.md`. Foundation plan: `docs/superpowers/plans/2026-09-09-hush-bosekit-foundation.md`. Approved design canvas: https://claude.ai/code/artifact/83e0050e-9df4-4385-ace9-7ce217b62775

## Global Constraints
- macOS 14+ (`platforms: [.macOS(.v14)]`); NO third-party deps.
- Design tokens: ink `#12151A`, surface `#191D24`, hairline `#232A34`, text `#E8ECF1`, muted `#8B95A1`, champagne accent `#E4C39A` (dark) / `#B8895A` (light) — accent for active/live only. Light: base `#ECEFF3`, surface `#FFFFFF`, text `#1B2027`. Space Grotesk for numerals/headings; SF/system for body.
- **Feature-gate every noise/profile control by `device.profile` flags** (`hasAudioSettingsRegister`, `supportsCustomProfiles`). On gen-1 both are false → the app shows mode selection + EQ + settings, NOT a live CNC dial or profile editor.
- All device writes go through `BoseController` and are **debounced** (120–200 ms) and serialized.
- Never call `BoseDevice` write methods that throw `.unsupported` from the UI — gate them out.

---

### Task 1: Scaffold the Hush app target + design tokens

**Files:**
- Modify: `Package.swift` (add `Hush` executable target depending on `BoseKit`) — OR create `Hush/Package.swift` if kept separate; prefer one workspace `Package.swift` at repo root that includes BoseKit + Hush.
- Create: `Sources/Hush/HushApp.swift`, `Sources/Hush/UI/DesignTokens.swift`
- Test: `Tests/HushTests/DesignTokensTests.swift`

**Interfaces:**
- Produces: a runnable `Hush` executable (`swift run Hush`) showing an empty menu-bar item + window; `enum Theme` / `DesignTokens` with the color + font tokens as `Color`/`Font` (theme-aware via `@Environment(\.colorScheme)`).

- [ ] **Step 1: Add the Hush executable target** (root `Package.swift`): products `.executable(name: "Hush", targets: ["Hush"])`, target `.executableTarget(name: "Hush", dependencies: ["BoseKit"], resources: [.process("Resources")])`, test target `HushTests`. Keep BoseKit targets.
- [ ] **Step 2: DesignTokens.swift** — `enum DT` with `static func ink(_ scheme: ColorScheme) -> Color` etc. from the hex tokens above (both palettes), plus `Font` helpers (`DT.display(_ size:)` → Space Grotesk, `DT.body(_ size:)` → system). Add a Color(hex:) init.
- [ ] **Step 3: Write a token test** asserting a couple of hex → Color conversions are correct (e.g. accent dark = #E4C39A components), and that the palette functions return distinct values per scheme.
- [ ] **Step 4: HushApp.swift** — `@main struct HushApp: App` with `MenuBarExtra("Hush", systemImage: "headphones") { Text("Hush") }` and a `WindowGroup { Text("Hush") }`. Set activation so the menu-bar item shows.
- [ ] **Step 5: Run `swift build` and `swift test`** — build clean, token test passes.
- [ ] **Step 6: Commit** `chore: scaffold Hush app target + design tokens`.

---

### Task 2: BoseController — state, lifecycle, feature flags (mock-tested)

**Files:**
- Create: `Sources/Hush/BoseController.swift`, `Sources/Hush/DeviceState.swift`
- Test: `Tests/HushTests/BoseControllerTests.swift`

**Interfaces:**
- Produces:
  - `struct DeviceState: Equatable` — connection status (`.disconnected/.connecting/.connected/.error(String)`), plus the readable values: `battery: Int?`, `firmware: String?`, `name: String?`, `currentModeIndex: Int?`, `modeNames: [Int:String]?` (from `modes()` when supported), `eq: [EQBand]?`, `sidetone: Int?`, `multipoint: Bool?`, `autoPause: Bool?`, `autoAnswer: Bool?`, and capability flags `supportsLiveNoise: Bool`, `supportsProfiles: Bool` (from the profile).
  - `@MainActor @Observable final class BoseController` with `private(set) var state: DeviceState`; `func start()` (discover + connect + initial read + begin battery polling); `func setEQ(band:value:)`, `func switchMode(index:)`, `func setSidetone(_:)`, `func setAutoPause(_:)`, `func setAutoAnswer(_:)`, `func setName(_:)` — each debounced + reflected optimistically then reconciled from device; `func refresh()`.
  - Dependency-injected `DeviceProviding` protocol (a thin async wrapper over `BoseDevice`) so tests use a mock; production impl wraps the real `BoseDevice` obtained from `BluetoothTransport.discover`.

- [ ] **Step 1: Write failing tests** (mock `DeviceProviding`): after `start()`, `state.connected == true` and `state.battery`/`eq`/`currentModeIndex` are populated from the mock; `switchMode(1)` calls the provider's `setMode(1)` and updates `state.currentModeIndex`; a provider error moves state to `.error`; capability flags mirror the injected profile (gen-1 → `supportsLiveNoise=false`).
- [ ] **Step 2: Run — fails.**
- [ ] **Step 3: Implement** `DeviceState`, `DeviceProviding`, and `BoseController` (debounce with a small `Task` + `Task.sleep`; serialize writes on the main actor; catch `BMAPError.unsupported` and simply never call those from the UI). Battery polling: a `Task` loop every ~60 s calling `battery()`.
- [ ] **Step 4: Run — passes.**
- [ ] **Step 5: Commit** `feat: BoseController app state + lifecycle (mock-tested)`.

---

### Task 3: Reusable UI components

**Files:**
- Create: `Sources/Hush/UI/Components/{Toggle,Chip,BatteryArc,EQCurveView,SectionCard}.swift`
- Test: none (visual) — build only.

**Interfaces:**
- Produces SwiftUI views matching the design: `HushToggle(isOn:)` (champagne pill), `ModeChip(title:icon:active:action:)`, `BatteryArc(percent:)`, `EQCurveView(bands: Binding<[EQBand]>, onEdit:)` (3 draggable points on a smooth curve, −10…+10), `SectionCard { content }` (surface + hairline + radius 16). All theme-aware via tokens.

- [ ] **Step 1: Implement the components** to the approved design (champagne accent for active/live only; Space Grotesk numerals). `EQCurveView` maps drag Y → value and calls `onEdit(band, value)`.
- [ ] **Step 2: `swift build`** clean.
- [ ] **Step 3: Commit** `feat: reusable Hush UI components`.

---

### Task 4: Menu-bar popover

**Files:**
- Create: `Sources/Hush/UI/MenuBarView.swift`; Modify: `HushApp.swift` (use it in `MenuBarExtra`, `.menuBarExtraStyle(.window)`).
- Build only.

**Interfaces:**
- Consumes `BoseController`. Produces `MenuBarView` (~340pt): header (name + `BatteryArc`), the **primary control = mode selector** (Quiet/Aware/Immersion/Cinema chips wired to `switchMode`; the design's CNC dial is shown ONLY if `state.supportsLiveNoise`), EQ preset chips, and an "Open Hush" button opening the main window. Connection/empty states per the design ("Headphones not connected — connect in System Settings").

- [ ] **Step 1: Implement** `MenuBarView` bound to `controller.state`; gate the CNC dial behind `supportsLiveNoise`. Wire chips to `switchMode`.
- [ ] **Step 2: `swift build`** clean.
- [ ] **Step 3: Commit** `feat: menu-bar popover`.

---

### Task 5: Main window shell + sidebar + Now/Modes section

**Files:**
- Create: `Sources/Hush/UI/MainWindow.swift`, `Sources/Hush/UI/Sections/ModesSection.swift`; Modify `HushApp.swift` `WindowGroup`.
- Build only.

**Interfaces:**
- Produces the 980×760-ish window: sidebar (device summary — name, `BatteryArc`, firmware; nav: Now/Modes, Sound, Settings; connection dot) + a detail area. **Now/Modes** is the hero: current mode large, the four preset modes + any custom `modeNames` as selectable cards (wired to `switchMode`); when `supportsLiveNoise` the CNC dial appears here, else a short "Noise settings live inside each mode on this model" note. Sidebar selection drives which section shows.

- [ ] **Step 1: Implement** the window scaffold, sidebar, and Modes section bound to the controller.
- [ ] **Step 2: `swift build`** clean.
- [ ] **Step 3: Commit** `feat: main window shell + modes section`.

---

### Task 6: Sound (EQ) section

**Files:** Create `Sources/Hush/UI/Sections/SoundSection.swift`. Build only.

**Interfaces:** Consumes controller; produces `SoundSection` with the interactive `EQCurveView` bound to `state.eq`, per-band value labels (+8/+4/+5 style), and preset chips (Flat / Bass boost / Podcast / Custom) that call `setEQ` per band. Edits are debounced via the controller.

- [ ] **Step 1: Implement** the EQ section; dragging a point calls `controller.setEQ(band:value:)`.
- [ ] **Step 2: `swift build`** clean.
- [ ] **Step 3: Commit** `feat: sound/EQ section`.

---

### Task 7: Settings section

**Files:** Create `Sources/Hush/UI/Sections/SettingsSection.swift`. Build only.

**Interfaces:** Produces `SettingsSection` with the settings that work: sidetone (off/low/med/high segmented), auto-pause (toggle), auto-answer (toggle), device name (editable text with Save), and a read-only Multipoint row (with a small "applies on device" note, since the write is flaky). Multipoint/profile controls gated by capability. Each wired to the controller's debounced setters.

- [ ] **Step 1: Implement** the settings section.
- [ ] **Step 2: `swift build`** clean.
- [ ] **Step 3: Commit** `feat: settings section`.

---

### Task 8: Light mode, focus/empty/error states, motion polish

**Files:** Modify the views + `DesignTokens`. Build only.

**Interfaces:** Ensure every view reads tokens per `colorScheme` (dark + light both correct per the design's two palettes); keyboard focus visible; calm motion (only confirm-a-change animations — dial/EQ respond to input; no decorative section entrances). Empty/error/connecting states give direction, not mood, matching the design copy.

- [ ] **Step 1: Audit + fix** each view for light-mode tokens, focus rings, and the state copy.
- [ ] **Step 2: `swift build`** clean.
- [ ] **Step 3: Commit** `feat: light mode + state polish`.

---

### Task 9: Run + visual verification (HARDWARE/GUI checkpoint — controller-run)

**Files:** possibly a `Sources/Hush/Resources/` for the bundled font; a short `docs/superpowers/notes/hush-app-run.md`.

> This task is run by the controller (me), not an autonomous agent: `swift run Hush` with the headphones connected, drive each control, confirm it changes the device (and the UI reflects device state), take screenshots, and fix any bundling/entitlement/activation issues discovered (menu-bar activation policy, Bluetooth access from the app process, Space Grotesk bundling). Revert any device changes made while testing.

- [ ] **Step 1:** `swift build` the whole workspace clean; `swift run Hush` launches the menu-bar app + window.
- [ ] **Step 2:** With headphones connected, verify: status populates; switching mode changes the device; EQ drag changes the device EQ; sidetone/auto-pause/auto-answer round-trip; unsupported controls are hidden. Screenshot dark + light.
- [ ] **Step 3:** Fix any launch/bundle/entitlement issues; note them in `hush-app-run.md`.
- [ ] **Step 4: Commit** `feat: Hush app runs and controls the device (verified)`.

---

## Self-Review
- Spec coverage: menu-bar + window (Tasks 4–5) ✓; EQ (6) ✓; settings (7) ✓; modes as the noise control on gen-1 (4,5) ✓ per the v1 decision; tokens/light/dark (1,8) ✓; controller lifecycle + debounce (2) ✓; run/verify (9) ✓. Live CNC dial + profile editor are feature-gated (present for wolverine, hidden for gen-1) — matches the settled scope.
- The only unit-tested layer is `BoseController` (Task 2) + tokens (Task 1); views are verified visually at Task 9 — appropriate for SwiftUI. Flagged so the reviewer doesn't demand view unit tests.
- Placeholder scan: view Tasks (3–8) give component contracts + design references rather than full line-by-line SwiftUI; implementers build to the approved design artifact + the tokens. This is intentional for design-driven UI; each task is still an independently buildable, committable unit.

## Execution Handoff
Subagent-driven-development, same as Plan 1. Task 9 is a controller/hardware checkpoint. After Task 9, run `superpowers:finishing-a-development-branch` for the whole `bose-quietcomfort-macos-app` branch (Plan 1 + Plan 2).
