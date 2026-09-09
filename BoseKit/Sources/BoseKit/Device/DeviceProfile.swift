/// Per-model differences (addresses stay shared via `Addr`; this captures the rest:
/// RFCOMM channel, ModeConfig payload lengths, and which slots are user-editable).
public struct DeviceProfile: Sendable {
    public var productID: UInt16
    public var codename: String
    public var rfcommChannel: UInt8
    public var hasAudioSettingsRegister: Bool
    public var modeConfigStatusLength: Int
    public var modeConfigSetLength: Int
    public var editableSlots: ClosedRange<Int>

    public init(productID: UInt16, codename: String, rfcommChannel: UInt8,
                hasAudioSettingsRegister: Bool, modeConfigStatusLength: Int, modeConfigSetLength: Int,
                editableSlots: ClosedRange<Int>) {
        self.productID = productID
        self.codename = codename
        self.rfcommChannel = rfcommChannel
        self.hasAudioSettingsRegister = hasAudioSettingsRegister
        self.modeConfigStatusLength = modeConfigStatusLength
        self.modeConfigSetLength = modeConfigSetLength
        self.editableSlots = editableSlots
    }

    /// QC Ultra 2 (gen 2) — reference device for the reverse-engineered protocol.
    public static let wolverine = DeviceProfile(
        productID: 0x4082, codename: "wolverine", rfcommChannel: 2,
        hasAudioSettingsRegister: true, modeConfigStatusLength: 48, modeConfigSetLength: 40,
        editableSlots: 4...10)

    /// QC Ultra (gen 1) — our target hardware. Starts identical to `wolverine`;
    /// corrected during hardware verification (Milestone 0 / Task 14) once the real
    /// RFCOMM channel, `[31.10]` register presence, ModeConfig lengths, and
    /// voice-prompts bit are confirmed on the device (spec §5).
    public static let lonestarr = DeviceProfile(
        productID: 0x4066, codename: "lonestarr", rfcommChannel: 2,
        hasAudioSettingsRegister: true, modeConfigStatusLength: 48, modeConfigSetLength: 40,
        editableSlots: 4...10)
}
