import Foundation

/// Typed high-level API over a `FrameSender` (real transport or a test mock). Maps every
/// feature to its BMAP address/frame per spec §4.3/§4.4, doing read-modify-write where the
/// device only exposes a combined register (audio settings `[31.10]`, ModeConfig `[31.6]`).
public actor BoseDevice {
    private let sender: FrameSender
    public let profile: DeviceProfile

    public init(sender: FrameSender, profile: DeviceProfile) {
        self.sender = sender
        self.profile = profile
    }

    /// Returns the single frame addressed to `addr` from a reply batch, throwing the
    /// device's own error if it sent one, or `.unexpectedResponse` if nothing matches.
    private func first(_ frames: [BMAPFrame], _ addr: (UInt8, UInt8)) throws -> BMAPFrame {
        if let e = frames.compactMap(BMAPError.from).first { throw e }
        guard let f = frames.first(where: { ($0.fblock, $0.function) == addr }) else { throw BMAPError.unexpectedResponse }
        return f
    }

    private func checkForError(_ frames: [BMAPFrame]) throws {
        if let e = frames.compactMap(BMAPError.from).first { throw e }
    }

    // MARK: - Battery / Firmware / Name

    public func battery() async throws -> Int {
        let r = try await sender.send(BMAPBuild.get(Addr.battery), drain: false, timeout: 3)
        return BMAPParse.battery(try first(r, Addr.battery).payload)
    }

    public func firmware() async throws -> String {
        let r = try await sender.send(BMAPBuild.get(Addr.firmware), drain: false, timeout: 3)
        return BMAPParse.firmware(try first(r, Addr.firmware).payload)
    }

    public func name() async throws -> String {
        let r = try await sender.send(BMAPBuild.get(Addr.name), drain: false, timeout: 3)
        return BMAPParse.name(try first(r, Addr.name).payload)
    }

    public func setName(_ name: String) async throws {
        let r = try await sender.send(BMAPBuild.setName(name), drain: false, timeout: 3)
        try checkForError(r)
    }

    // MARK: - Mode

    public func currentMode() async throws -> Int {
        let r = try await sender.send(BMAPBuild.get(Addr.currentMode), drain: false, timeout: 3)
        return BMAPParse.modeIndex(try first(r, Addr.currentMode).payload)
    }

    public func setMode(_ index: Int, announce: Bool = false) async throws {
        let r = try await sender.send(BMAPBuild.setMode(index: index, announce: announce), drain: true, timeout: 3)
        try checkForError(r)
    }

    // MARK: - Audio settings register `[31.10]` (cnc/autoCNC/spatial/wind/anc), with a
    // `[31.6]` ModeConfig fallback for devices (e.g. lonestarr / QC Ultra gen-1) that
    // return FuncNotSupp for `[31.10]` — same situation as bosectl's prince/qc45 devices
    // (`~/bosectl/python/pybmap/connection.py` `_update_current_mode_config`).

    public func audioSettings() async throws -> AudioSettings {
        guard profile.hasAudioSettingsRegister else {
            let config = try await currentModeConfig()
            return AudioSettings(cnc: config.cnc, autoCNC: config.autoCNC, spatial: config.spatial,
                                  wind: config.wind, anc: config.anc)
        }
        let r = try await sender.send(BMAPBuild.get(Addr.audioSettings), drain: false, timeout: 3)
        return BMAPParse.audioSettings(try first(r, Addr.audioSettings).payload)
    }

    private func writeAudioSettings(_ s: AudioSettings) async throws {
        let r = try await sender.send(BMAPBuild.audioSettings(s), drain: false, timeout: 3)
        try checkForError(r)
    }

    /// Fetches the `ModeConfig` for the currently active mode: `[31.3]` for the index,
    /// then `[31.1]` GetAll (via `modes()`) to find that index's config — mirrors
    /// bosectl's `_current_mode_config` (`mode_idx()` + a lookup in `modes()`), since
    /// there is no targeted single-mode `[31.6]` GET.
    private func currentModeConfig() async throws -> ModeConfig {
        let idx = try await currentMode()
        let all = try await modes()
        guard let config = all.first(where: { $0.index == idx }) else { throw BMAPError.unexpectedResponse }
        return config
    }

    /// Writes back a `ModeConfig` via `[31.6]` SETGET — the fallback write path used by
    /// setCNC/setANC/setWind/setSpatial on devices without `[31.10]`. Unlike
    /// `saveProfile`, this does not gate on `editableSlots`: CNC/ANC/Wind/Spatial are
    /// live settings that apply to whichever mode is currently active (including
    /// firmware presets), exactly as `[31.10]` does on devices that have it.
    private func writeModeConfigFallback(_ config: ModeConfig) async throws {
        let r = try await sender.send(BMAPBuild.modeConfig40(config), drain: false, timeout: 3)
        try checkForError(r)
    }

    /// CNC is inverted (0 = max ANC, 10 = ambient); writing it must clear `autoCNC`
    /// (leaving `autoCNC=1` set alongside an explicit level triggers Runtime err 8 — spec §8).
    public func setCNC(_ level: Int) async throws {
        guard profile.hasAudioSettingsRegister else {
            var config = try await currentModeConfig()
            config.cnc = level
            config.autoCNC = 0
            try await writeModeConfigFallback(config)
            return
        }
        var s = try await audioSettings()
        s.cnc = level
        s.autoCNC = 0
        try await writeAudioSettings(s)
    }

    public func setANC(_ on: Bool) async throws {
        guard profile.hasAudioSettingsRegister else {
            var config = try await currentModeConfig()
            config.anc = on ? 1 : 0
            try await writeModeConfigFallback(config)
            return
        }
        var s = try await audioSettings()
        s.anc = on ? 1 : 0
        try await writeAudioSettings(s)
    }

    public func setWind(_ on: Bool) async throws {
        guard profile.hasAudioSettingsRegister else {
            var config = try await currentModeConfig()
            config.wind = on ? 1 : 0
            try await writeModeConfigFallback(config)
            return
        }
        var s = try await audioSettings()
        s.wind = on ? 1 : 0
        try await writeAudioSettings(s)
    }

    /// `mode`: 0 off / 1 room / 2 head (spec §4.3).
    public func setSpatial(_ mode: Int) async throws {
        guard profile.hasAudioSettingsRegister else {
            var config = try await currentModeConfig()
            config.spatial = mode
            try await writeModeConfigFallback(config)
            return
        }
        var s = try await audioSettings()
        s.spatial = mode
        try await writeAudioSettings(s)
    }

    // MARK: - EQ

    /// `[1.7]` GET can come back as one frame with the full 12-byte payload or as three
    /// 4-byte STATUS frames (one per band) depending on the device — concatenate whichever
    /// arrives at `Addr.eq` before parsing.
    public func eq() async throws -> [EQBand] {
        let r = try await sender.send(BMAPBuild.get(Addr.eq), drain: true, timeout: 3)
        try checkForError(r)
        let payload = r.filter { ($0.fblock, $0.function) == Addr.eq }.flatMap(\.payload)
        guard !payload.isEmpty else { throw BMAPError.unexpectedResponse }
        return BMAPParse.eq(payload)
    }

    public func setEQ(band: Int, value: Int) async throws {
        let r = try await sender.send(BMAPBuild.eqBand(value: value, band: band), drain: false, timeout: 3)
        try checkForError(r)
    }

    // MARK: - Sidetone

    public func sidetone() async throws -> Int {
        let r = try await sender.send(BMAPBuild.get(Addr.sidetone), drain: false, timeout: 3)
        return BMAPParse.sidetone(try first(r, Addr.sidetone).payload)
    }

    public func setSidetone(_ level: Int) async throws {
        let r = try await sender.send(BMAPBuild.setSidetone(level: level), drain: false, timeout: 3)
        try checkForError(r)
    }

    // MARK: - Multipoint

    public func multipoint() async throws -> Bool {
        let r = try await sender.send(BMAPBuild.get(Addr.multipoint), drain: false, timeout: 3)
        return BMAPParse.multipointEnabled(try first(r, Addr.multipoint).payload)
    }

    /// On lonestarr hardware (2026-09-09 verification), `setMultipoint(false)` ack'd
    /// successfully but an immediate read-back still showed `true`. `BMAPBuild.toggle`
    /// (plain `[on ? 1 : 0]`) and `BMAPParse.multipointEnabled` (bit `0x02` of byte 0)
    /// match bosectl's `build_toggle`/`parse_multipoint` for `[1.10]` exactly — bosectl
    /// does no extra delay or different payload either — so this isn't a payload bug.
    /// Most likely the device applies multipoint asynchronously and a re-read shortly
    /// after would show the new value. Not blocking; revisit if it recurs.
    public func setMultipoint(_ on: Bool) async throws {
        let r = try await sender.send(BMAPBuild.toggle(Addr.multipoint, on: on), drain: false, timeout: 3)
        try checkForError(r)
    }

    // MARK: - Auto-pause / Auto-answer

    public func autoPause() async throws -> Bool {
        let r = try await sender.send(BMAPBuild.get(Addr.autoPause), drain: false, timeout: 3)
        return BMAPParse.boolByte0(try first(r, Addr.autoPause).payload)
    }

    public func setAutoPause(_ on: Bool) async throws {
        let r = try await sender.send(BMAPBuild.toggle(Addr.autoPause, on: on), drain: false, timeout: 3)
        try checkForError(r)
    }

    public func autoAnswer() async throws -> Bool {
        let r = try await sender.send(BMAPBuild.get(Addr.autoAnswer), drain: false, timeout: 3)
        return BMAPParse.boolByte0(try first(r, Addr.autoAnswer).payload)
    }

    public func setAutoAnswer(_ on: Bool) async throws {
        let r = try await sender.send(BMAPBuild.toggle(Addr.autoAnswer, on: on), drain: false, timeout: 3)
        try checkForError(r)
    }

    // MARK: - Voice prompts

    public func voicePrompts() async throws -> (enabled: Bool, language: Int) {
        let r = try await sender.send(BMAPBuild.get(Addr.voicePrompts), drain: false, timeout: 3)
        return BMAPParse.voicePrompts(try first(r, Addr.voicePrompts).payload)
    }

    public func setVoicePrompts(enabled: Bool, language: Int) async throws {
        let r = try await sender.send(BMAPBuild.setVoicePrompts(enabled: enabled, language: language), drain: false, timeout: 3)
        try checkForError(r)
    }

    // MARK: - Buttons

    public func buttons() async throws -> ButtonMapping {
        let r = try await sender.send(BMAPBuild.get(Addr.buttons), drain: false, timeout: 3)
        return BMAPParse.buttonMapping(try first(r, Addr.buttons).payload)
    }

    public func setButton(_ mapping: ButtonMapping) async throws {
        let r = try await sender.send(BMAPBuild.setButton(mapping), drain: false, timeout: 3)
        try checkForError(r)
    }

    // MARK: - Profiles / ModeConfig

    /// `START [31.1]`, drained — the device streams a `[31.6]` STATUS frame (48B) per
    /// mode (locked presets 0–3 plus whatever custom slots exist).
    public func modes() async throws -> [ModeConfig] {
        let r = try await sender.send(BMAPBuild.listProfiles(), drain: true, timeout: 3)
        try checkForError(r)
        return r.filter { ($0.fblock, $0.function) == Addr.modeConfig }
            .map { BMAPParse.modeConfig48($0.payload) }
    }

    /// Writes a custom profile slot. Presets 0–3 are firmware-locked (spec §4.4/§8) —
    /// reject locally rather than round-tripping to get a Runtime err 8 back.
    public func saveProfile(_ config: ModeConfig) async throws {
        guard profile.editableSlots.contains(config.index) else { throw BMAPError.unsupported }
        let r = try await sender.send(BMAPBuild.modeConfig40(config), drain: false, timeout: 3)
        try checkForError(r)
    }

    /// Delete = overwrite the named editable slot with name "None" and zeroed settings
    /// (spec §4.4 — there is no dedicated delete opcode).
    public func deleteProfile(name: String) async throws {
        let all = try await modes()
        guard let match = all.first(where: { $0.name == name && $0.editable }) else {
            throw BMAPError.unexpectedResponse
        }
        var cleared = match
        cleared.name = "None"
        cleared.configured = false
        cleared.cnc = 0
        cleared.autoCNC = 0
        cleared.spatial = 0
        cleared.wind = 0
        cleared.anc = 0
        let r = try await sender.send(BMAPBuild.modeConfig40(cleared), drain: false, timeout: 3)
        try checkForError(r)
    }
}
