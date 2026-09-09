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
                  payload: [UInt8(s.cnc), UInt8(s.autoCNC), UInt8(s.spatial), UInt8(s.wind), UInt8(s.anc)])
    }
}
