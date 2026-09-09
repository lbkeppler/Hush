import Foundation

public struct ModeConfig: Equatable, Sendable {
    public var index: Int
    public var name: String
    public var editable: Bool
    public var configured: Bool
    public var cnc: Int
    public var autoCNC: Int
    public var spatial: Int
    public var wind: Int
    public var anc: Int

    public init(index: Int, name: String, editable: Bool, configured: Bool,
                cnc: Int, autoCNC: Int, spatial: Int, wind: Int, anc: Int) {
        self.index = index
        self.name = name
        self.editable = editable
        self.configured = configured
        self.cnc = cnc
        self.autoCNC = autoCNC
        self.spatial = spatial
        self.wind = wind
        self.anc = anc
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
        p[35] = UInt8(c.cnc)
        p[36] = UInt8(c.autoCNC)
        p[37] = UInt8(c.spatial)
        p[38] = UInt8(c.wind)
        p[39] = UInt8(c.anc)
        return BMAPFrame(fblock: Addr.modeConfig.0, function: Addr.modeConfig.1, op: .setGet, payload: p)
    }
}

extension Array where Element == UInt8 {
    subscript(safe range: Range<Int>) -> ArraySlice<UInt8> {
        let lo = Swift.min(count, Swift.max(0, range.lowerBound))
        let hi = Swift.min(count, Swift.max(0, range.upperBound))
        return self[lo..<Swift.max(lo, hi)]
    }
}
