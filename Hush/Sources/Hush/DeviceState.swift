import BoseKit

/// Observable snapshot of everything the UI needs to know about the connected device.
///
/// `BoseController` owns the single source of truth (`state: DeviceState`); views read it,
/// never `BoseDevice`/`DeviceProviding` directly.
public struct DeviceState: Equatable, Sendable {
    public enum ConnectionStatus: Equatable, Sendable {
        case disconnected
        case connecting
        case connected
        case error(String)
    }

    public var status: ConnectionStatus
    public var battery: Int?
    public var firmware: String?
    public var name: String?
    public var currentModeIndex: Int?
    public var modeNames: [Int: String]?
    public var eq: [EQBand]?
    public var sidetone: Int?
    public var multipoint: Bool?
    public var autoPause: Bool?
    public var autoAnswer: Bool?

    /// Capability flags mirrored from `DeviceProfile` once a device is connected.
    public var supportsLiveNoise: Bool
    public var supportsProfiles: Bool

    /// Set when an intent's write or post-write reconcile read fails. This is distinct from
    /// `status`: the connection is still live, so `status` stays `.connected` — only a
    /// connection-level failure (in `start()`) sets `status = .error`. Cleared on the next
    /// successful intent write.
    public var lastError: String?

    public init(
        status: ConnectionStatus = .disconnected,
        battery: Int? = nil,
        firmware: String? = nil,
        name: String? = nil,
        currentModeIndex: Int? = nil,
        modeNames: [Int: String]? = nil,
        eq: [EQBand]? = nil,
        sidetone: Int? = nil,
        multipoint: Bool? = nil,
        autoPause: Bool? = nil,
        autoAnswer: Bool? = nil,
        supportsLiveNoise: Bool = false,
        supportsProfiles: Bool = false,
        lastError: String? = nil
    ) {
        self.status = status
        self.battery = battery
        self.firmware = firmware
        self.name = name
        self.currentModeIndex = currentModeIndex
        self.modeNames = modeNames
        self.eq = eq
        self.sidetone = sidetone
        self.multipoint = multipoint
        self.autoPause = autoPause
        self.autoAnswer = autoAnswer
        self.supportsLiveNoise = supportsLiveNoise
        self.supportsProfiles = supportsProfiles
        self.lastError = lastError
    }
}
