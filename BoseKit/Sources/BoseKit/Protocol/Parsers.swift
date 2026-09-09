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
    /// Voice prompts byte0: enabled = bit5 (spec §4.3 notes bit5 *or* bit6 — unverified on
    /// hardware; matches `BMAPBuild.setVoicePrompts`'s bit5 write), language = low 5 bits.
    public static func voicePrompts(_ p: [UInt8]) -> (enabled: Bool, language: Int) {
        let b = p.first ?? 0
        return (enabled: (b & 0x20) != 0, language: Int(b & 0x1F))
    }
    public static func eq(_ p: [UInt8]) -> [EQBand] {
        stride(from: 0, to: p.count - 3, by: 4).map { i in
            EQBand(band: Int(p[i + 3]), value: Int(Int8(bitPattern: p[i + 2])))
        }
    }
}

public struct EQBand: Equatable, Sendable {
    public var band: Int
    public var value: Int
    public init(band: Int, value: Int) { self.band = band; self.value = value }
}

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

/// `[1.9]` button remap: `[button, event, action]` (spec §4.3 — "enums in constants",
/// left as raw ints here since the concrete button/event/action enumerations are
/// unverified on hardware).
public struct ButtonMapping: Equatable, Sendable {
    public var button: Int
    public var event: Int
    public var action: Int
    public init(button: Int, event: Int, action: Int) {
        self.button = button; self.event = event; self.action = action
    }
}

public extension BMAPParse {
    static func buttonMapping(_ p: [UInt8]) -> ButtonMapping {
        func b(_ i: Int) -> Int { i < p.count ? Int(p[i]) : 0 }
        return ButtonMapping(button: b(0), event: b(1), action: b(2))
    }
}
