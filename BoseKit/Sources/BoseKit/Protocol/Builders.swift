import Foundation

public enum BMAPBuild {
    public static func eqBand(value: Int, band: Int) -> BMAPFrame {
        let v = UInt8(bitPattern: Int8(clamping: value))
        return BMAPFrame(fblock: Addr.eq.0, function: Addr.eq.1, op: .setGet, payload: [v, UInt8(band)])
    }
}
