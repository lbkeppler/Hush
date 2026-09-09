import Foundation

public enum BMAPBuild {
    public static func eqBand(value: Int, band: Int) -> BMAPFrame {
        let v = UInt8(bitPattern: Int8(clamping: value))
        return BMAPFrame(fblock: Addr.eq.0, function: Addr.eq.1, op: .setGet, payload: [v, UInt8(band)])
    }
}

public extension BMAPBuild {
    static func audioSettings(_ s: AudioSettings) -> BMAPFrame {
        BMAPFrame(fblock: Addr.audioSettings.0, function: Addr.audioSettings.1, op: .setGet,
                  payload: [UInt8(clamping: s.cnc), UInt8(clamping: s.autoCNC), UInt8(clamping: s.spatial),
                            UInt8(clamping: s.wind), UInt8(clamping: s.anc)])
    }
}

public extension BMAPBuild {
    static func get(_ a: (UInt8, UInt8)) -> BMAPFrame { BMAPFrame(fblock: a.0, function: a.1, op: .get) }

    static func setName(_ name: String) -> BMAPFrame {
        let bytes = Array(Array(name.utf8).prefix(31))
        return BMAPFrame(fblock: Addr.name.0, function: Addr.name.1, op: .setGet, payload: bytes)
    }
    static func setMode(index: Int, announce: Bool) -> BMAPFrame {
        BMAPFrame(fblock: Addr.currentMode.0, function: Addr.currentMode.1, op: .start,
                  payload: [UInt8(clamping: index), announce ? 1 : 0])
    }
    static func toggle(_ a: (UInt8, UInt8), on: Bool) -> BMAPFrame {
        BMAPFrame(fblock: a.0, function: a.1, op: .setGet, payload: [on ? 1 : 0])
    }
    static func setSidetone(level: Int) -> BMAPFrame {
        BMAPFrame(fblock: Addr.sidetone.0, function: Addr.sidetone.1, op: .setGet, payload: [0x01, UInt8(clamping: level)])
    }
    static func setVoicePrompts(enabled: Bool, language: Int) -> BMAPFrame {
        BMAPFrame(fblock: Addr.voicePrompts.0, function: Addr.voicePrompts.1, op: .setGet,
                  payload: [(enabled ? 0x20 : 0) | (UInt8(language) & 0x1F)])
    }
    static func setButton(_ m: ButtonMapping) -> BMAPFrame {
        BMAPFrame(fblock: Addr.buttons.0, function: Addr.buttons.1, op: .setGet,
                  payload: [UInt8(clamping: m.button), UInt8(clamping: m.event), UInt8(clamping: m.action)])
    }
    /// `START [31.1]` — "list profiles"; the device streams `[31.6]` STATUS frames for
    /// every mode (presets + custom slots), collected by `send(..., drain: true)`.
    static func listProfiles() -> BMAPFrame {
        BMAPFrame(fblock: Addr.modesList.0, function: Addr.modesList.1, op: .start)
    }
}
