import BoseKit
import Testing
@testable import Hush

/// Test double for `DeviceProviding`. An `actor` so it's trivially `Sendable`; canned values
/// are `var`s the test sets before `start()`, calls are recorded for assertions.
actor MockDevice: DeviceProviding {
    nonisolated let profile: DeviceProfile

    var batteryValue = 80
    var firmwareValue = "1.2.3"
    var nameValue = "QC Ultra"
    var currentModeValue = 0
    var eqValue: [EQBand] = [EQBand(band: 0, value: -2), EQBand(band: 1, value: 0), EQBand(band: 2, value: 4)]
    var sidetoneValue = 2
    var multipointValue = true
    var autoPauseValue = true
    var autoAnswerValue = false
    var modesValue: [ModeConfig] = [
        ModeConfig(index: 0, name: "Quiet", editable: false, configured: true,
                   cnc: 0, autoCNC: 0, spatial: 0, wind: 0, anc: 1),
    ]

    private(set) var setModeCalls: [(index: Int, announce: Bool)] = []
    private(set) var setEQCalls: [(band: Int, value: Int)] = []
    private(set) var setSidetoneCalls: [Int] = []
    private(set) var setAutoPauseCalls: [Bool] = []
    private(set) var setAutoAnswerCalls: [Bool] = []
    private(set) var setNameCalls: [String] = []

    /// When set, every *write* method (not the getters) throws this instead of succeeding —
    /// lets tests simulate a transient BLE write failure.
    private var writeError: Error?

    init(profile: DeviceProfile = .wolverine) {
        self.profile = profile
    }

    func setWriteError(_ error: Error?) {
        writeError = error
    }

    func battery() async throws -> Int { batteryValue }
    func firmware() async throws -> String { firmwareValue }
    func name() async throws -> String { nameValue }
    func setName(_ name: String) async throws {
        if let writeError { throw writeError }
        setNameCalls.append(name)
        nameValue = name
    }

    func currentMode() async throws -> Int { currentModeValue }
    func setMode(index: Int, announce: Bool) async throws {
        if let writeError { throw writeError }
        setModeCalls.append((index, announce))
        currentModeValue = index
    }

    func eq() async throws -> [EQBand] { eqValue }
    func setEQ(band: Int, value: Int) async throws {
        if let writeError { throw writeError }
        setEQCalls.append((band, value))
        if let idx = eqValue.firstIndex(where: { $0.band == band }) {
            eqValue[idx].value = value
        } else {
            eqValue.append(EQBand(band: band, value: value))
        }
    }

    func sidetone() async throws -> Int { sidetoneValue }
    func setSidetone(_ level: Int) async throws {
        if let writeError { throw writeError }
        setSidetoneCalls.append(level)
        sidetoneValue = level
    }

    func multipoint() async throws -> Bool { multipointValue }

    func autoPause() async throws -> Bool { autoPauseValue }
    func setAutoPause(_ on: Bool) async throws {
        if let writeError { throw writeError }
        setAutoPauseCalls.append(on)
        autoPauseValue = on
    }

    func autoAnswer() async throws -> Bool { autoAnswerValue }
    func setAutoAnswer(_ on: Bool) async throws {
        if let writeError { throw writeError }
        setAutoAnswerCalls.append(on)
        autoAnswerValue = on
    }

    func modes() async throws -> [ModeConfig] {
        guard profile.supportsCustomProfiles else { throw BMAPError.unsupported }
        return modesValue
    }
}

private struct DiscoveryError: Error {}
private struct WriteError: Error {}

@MainActor
@Suite("BoseController")
struct BoseControllerTests {

    @Test("start() connects and populates state from the provider")
    func startPopulatesState() async {
        let mock = MockDevice(profile: .wolverine)
        let controller = BoseController(makeProvider: { mock })

        await controller.start()

        #expect(controller.state.status == .connected)
        #expect(controller.state.battery == 80)
        #expect(controller.state.firmware == "1.2.3")
        #expect(controller.state.name == "QC Ultra")
        #expect(controller.state.currentModeIndex == 0)
        #expect(controller.state.eq == [EQBand(band: 0, value: -2), EQBand(band: 1, value: 0), EQBand(band: 2, value: 4)])
        #expect(controller.state.sidetone == 2)
        #expect(controller.state.multipoint == true)
        #expect(controller.state.autoPause == true)
        #expect(controller.state.autoAnswer == false)
        #expect(controller.state.modeNames == [0: "Quiet"])
    }

    @Test("capability flags mirror the injected profile")
    func capabilityFlagsMirrorProfile() async {
        let mock = MockDevice(profile: .lonestarr)
        let controller = BoseController(makeProvider: { mock })

        await controller.start()

        #expect(controller.state.status == .connected)
        #expect(controller.state.supportsLiveNoise == false)
        #expect(controller.state.supportsProfiles == false)
        // modes() is unsupported on lonestarr; start() must not have called it.
        #expect(controller.state.modeNames == nil)
    }

    @Test("capability flags reflect a gen-2 profile")
    func capabilityFlagsGen2() async {
        let mock = MockDevice(profile: .wolverine)
        let controller = BoseController(makeProvider: { mock })

        await controller.start()

        #expect(controller.state.supportsLiveNoise == true)
        #expect(controller.state.supportsProfiles == true)
    }

    @Test("switchMode calls the provider, reconciles state from a fresh read")
    func switchModeUpdatesState() async {
        let mock = MockDevice(profile: .wolverine)
        let controller = BoseController(makeProvider: { mock })
        await controller.start()

        await controller.switchMode(index: 1)

        #expect(controller.state.currentModeIndex == 1)
        #expect(controller.state.lastError == nil)
        let calls = await mock.setModeCalls
        #expect(calls.count == 1)
        #expect(calls.first?.index == 1)
        #expect(calls.first?.announce == false)
    }

    @Test("setEQ updates state optimistically, debounces the write, then reconciles from the device")
    func setEQDebouncesToProvider() async throws {
        let mock = MockDevice(profile: .wolverine)
        let controller = BoseController(makeProvider: { mock })
        await controller.start()

        controller.setEQ(band: 0, value: 6)
        // A rapid follow-up call should coalesce onto a single provider write.
        controller.setEQ(band: 0, value: 6)

        // Optimistic update happens synchronously, before the debounce fires.
        #expect(controller.state.eq?.first(where: { $0.band == 0 })?.value == 6)
        #expect(await mock.setEQCalls.isEmpty)

        try await Task.sleep(nanoseconds: 400_000_000)

        let calls = await mock.setEQCalls
        #expect(calls.count == 1)
        #expect(calls.first?.band == 0)
        #expect(calls.first?.value == 6)
        // Reconciled from a fresh eq() read after the write succeeded.
        #expect(controller.state.eq?.first(where: { $0.band == 0 })?.value == 6)
        #expect(controller.state.lastError == nil)
    }

    @Test("setSidetone calls the provider with the right value and reconciles state")
    func setSidetoneCallsProvider() async throws {
        let mock = MockDevice(profile: .wolverine)
        let controller = BoseController(makeProvider: { mock })
        await controller.start()

        controller.setSidetone(4)
        try await Task.sleep(nanoseconds: 400_000_000)

        let calls = await mock.setSidetoneCalls
        #expect(calls == [4])
        #expect(controller.state.sidetone == 4)
        #expect(controller.state.lastError == nil)
    }

    @Test("setAutoPause calls the provider with the right value and reconciles state")
    func setAutoPauseCallsProvider() async throws {
        let mock = MockDevice(profile: .wolverine)
        let controller = BoseController(makeProvider: { mock })
        await controller.start()

        controller.setAutoPause(false)
        try await Task.sleep(nanoseconds: 400_000_000)

        let calls = await mock.setAutoPauseCalls
        #expect(calls == [false])
        #expect(controller.state.autoPause == false)
        #expect(controller.state.lastError == nil)
    }

    @Test("setAutoAnswer calls the provider with the right value and reconciles state")
    func setAutoAnswerCallsProvider() async throws {
        let mock = MockDevice(profile: .wolverine)
        let controller = BoseController(makeProvider: { mock })
        await controller.start()

        controller.setAutoAnswer(true)
        try await Task.sleep(nanoseconds: 400_000_000)

        let calls = await mock.setAutoAnswerCalls
        #expect(calls == [true])
        #expect(controller.state.autoAnswer == true)
        #expect(controller.state.lastError == nil)
    }

    @Test("setName calls the provider with the right value and reconciles state")
    func setNameCallsProvider() async throws {
        let mock = MockDevice(profile: .wolverine)
        let controller = BoseController(makeProvider: { mock })
        await controller.start()

        controller.setName("Lucas's QC Ultra")
        try await Task.sleep(nanoseconds: 400_000_000)

        let calls = await mock.setNameCalls
        #expect(calls == ["Lucas's QC Ultra"])
        #expect(controller.state.name == "Lucas's QC Ultra")
        #expect(controller.state.lastError == nil)
    }

    @Test("an intent write failure sets lastError but leaves status connected")
    func intentWriteFailureSetsLastErrorNotStatus() async throws {
        let mock = MockDevice(profile: .wolverine)
        let controller = BoseController(makeProvider: { mock })
        await controller.start()
        await mock.setWriteError(WriteError())

        controller.setSidetone(9)
        try await Task.sleep(nanoseconds: 400_000_000)

        #expect(controller.state.status == .connected)
        #expect(controller.state.lastError != nil)
        // The write threw, so the provider never recorded the call and never
        // updated its backing value.
        #expect(await mock.setSidetoneCalls.isEmpty)

        // A subsequent successful intent clears lastError.
        await mock.setWriteError(nil)
        controller.setSidetone(5)
        try await Task.sleep(nanoseconds: 400_000_000)

        #expect(controller.state.status == .connected)
        #expect(controller.state.lastError == nil)
        #expect(controller.state.sidetone == 5)
    }

    @Test("a provider that throws on start() yields .error")
    func startFailureYieldsError() async {
        let controller = BoseController(makeProvider: { throw DiscoveryError() })

        await controller.start()

        guard case .error = controller.state.status else {
            Issue.record("expected .error status, got \(controller.state.status)")
            return
        }
    }
}
