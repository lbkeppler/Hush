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
