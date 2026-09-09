/// Per-model differences (addresses stay shared via `Addr`).
///
/// Only `hasAudioSettingsRegister`, `editableSlots`, and `supportsCustomProfiles` are
/// load-bearing today. A per-model ModeConfig-length abstraction (distinct
/// status/set payload sizes per device) is post-v1: `BluetoothTransport.discover`
/// hardcodes the RFCOMM channels it probes, and `BMAPParse`/`BMAPBuild` hardcode the
/// 48-byte STATUS / 40-byte SET ModeConfig layout used by `wolverine`-family devices.
public struct DeviceProfile: Sendable {
    public var productID: UInt16
    public var codename: String
    public var hasAudioSettingsRegister: Bool
    public var editableSlots: ClosedRange<Int>
    /// Whether this device's ModeConfig (`[31.6]`) matches the 48B STATUS / 40B SET
    /// layout `BMAPParse`/`BMAPBuild` assume. Gen-1 hardware (`lonestarr`) has a real
    /// ModeConfig that is 47 bytes with no ANC byte, so parsing it with the
    /// gen-2 layout would silently return garbage and writing would corrupt the
    /// device's profile — `modes()`/`saveProfile()`/`deleteProfile()` must refuse
    /// locally rather than round-trip when this is `false`.
    public var supportsCustomProfiles: Bool

    public init(productID: UInt16, codename: String,
                hasAudioSettingsRegister: Bool, editableSlots: ClosedRange<Int>,
                supportsCustomProfiles: Bool) {
        self.productID = productID
        self.codename = codename
        self.hasAudioSettingsRegister = hasAudioSettingsRegister
        self.editableSlots = editableSlots
        self.supportsCustomProfiles = supportsCustomProfiles
    }

    /// QC Ultra 2 (gen 2) — reference device for the reverse-engineered protocol.
    public static let wolverine = DeviceProfile(
        productID: 0x4082, codename: "wolverine",
        hasAudioSettingsRegister: true, editableSlots: 4...10,
        supportsCustomProfiles: true)

    /// QC Ultra (gen 1) — our target hardware. RFCOMM channel and editable slots
    /// matched `wolverine` on hardware verification (Milestone 0 / Task 14).
    /// `hasAudioSettingsRegister` is `false` (Task 15 / 2026-09-09 verification): gen-1
    /// returns FuncNotSupp for `[31.10]` AudioSettingsConfig, same as bosectl's
    /// prince/qc45 devices. Task 16 (2026-09-09, v1 scope decision): there is no verified
    /// live-write path for noise control on this device family (the `[31.6]` ModeConfig
    /// fallback hit firmware-locked presets and a mismatched payload layout), so
    /// `BoseDevice` throws `.unsupported` for CNC/ANC/Wind/Spatial/audioSettings here
    /// instead — see `docs/superpowers/notes/2026-09-09-lonestarr-verification.md`.
    /// `supportsCustomProfiles` is `false`: gen-1's real ModeConfig is 47B with no ANC
    /// byte, so the 48/40-byte parse/build this kit uses would return garbage on read
    /// and write the wrong bytes — custom profiles are gated off entirely for this
    /// device until a gen-1-specific ModeConfig layout exists.
    public static let lonestarr = DeviceProfile(
        productID: 0x4066, codename: "lonestarr",
        hasAudioSettingsRegister: false, editableSlots: 4...10,
        supportsCustomProfiles: false)
}
