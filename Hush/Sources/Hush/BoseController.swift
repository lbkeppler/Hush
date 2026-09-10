import BoseKit
import Foundation
import Observation

/// Thin async wrapper over the subset of `BoseDevice`'s API the UI needs, so tests can
/// substitute a mock without touching Bluetooth. `LiveDevice` is the production
/// implementation; test doubles conform directly.
public protocol DeviceProviding: Sendable {
    var profile: DeviceProfile { get }

    func battery() async throws -> Int
    func firmware() async throws -> String
    func name() async throws -> String
    func setName(_ name: String) async throws

    func currentMode() async throws -> Int
    func setMode(index: Int, announce: Bool) async throws

    func eq() async throws -> [EQBand]
    func setEQ(band: Int, value: Int) async throws

    func sidetone() async throws -> Int
    func setSidetone(_ level: Int) async throws

    func multipoint() async throws -> Bool

    func autoPause() async throws -> Bool
    func setAutoPause(_ on: Bool) async throws

    func autoAnswer() async throws -> Bool
    func setAutoAnswer(_ on: Bool) async throws

    /// Throws `BMAPError.unsupported` when `profile.supportsCustomProfiles == false`.
    func modes() async throws -> [ModeConfig]
}

/// Production `DeviceProviding` implementation — forwards every call to a real `BoseDevice`.
public struct LiveDevice: DeviceProviding {
    private let device: BoseDevice
    public let profile: DeviceProfile

    public init(device: BoseDevice) async {
        self.device = device
        self.profile = await device.profile
    }

    public func battery() async throws -> Int { try await device.battery() }
    public func firmware() async throws -> String { try await device.firmware() }
    public func name() async throws -> String { try await device.name() }
    public func setName(_ name: String) async throws { try await device.setName(name) }

    public func currentMode() async throws -> Int { try await device.currentMode() }
    public func setMode(index: Int, announce: Bool) async throws {
        try await device.setMode(index, announce: announce)
    }

    public func eq() async throws -> [EQBand] { try await device.eq() }
    public func setEQ(band: Int, value: Int) async throws {
        try await device.setEQ(band: band, value: value)
    }

    public func sidetone() async throws -> Int { try await device.sidetone() }
    public func setSidetone(_ level: Int) async throws { try await device.setSidetone(level) }

    public func multipoint() async throws -> Bool { try await device.multipoint() }

    public func autoPause() async throws -> Bool { try await device.autoPause() }
    public func setAutoPause(_ on: Bool) async throws { try await device.setAutoPause(on) }

    public func autoAnswer() async throws -> Bool { try await device.autoAnswer() }
    public func setAutoAnswer(_ on: Bool) async throws { try await device.setAutoAnswer(on) }

    public func modes() async throws -> [ModeConfig] { try await device.modes() }
}

/// The app's observable state + device lifecycle. Views read `state`; nothing else touches
/// `DeviceProviding`/`BoseDevice` directly.
@MainActor
@Observable
public final class BoseController {
    public private(set) var state = DeviceState()

    private let makeProvider: () async throws -> DeviceProviding
    private var provider: DeviceProviding?

    private var batteryPollTask: Task<Void, Never>?
    private var debounceTasks: [String: Task<Void, Never>] = [:]

    private static let batteryPollInterval: UInt64 = 60_000_000_000
    private static let debounceDelay: UInt64 = 150_000_000

    public init(makeProvider: @escaping () async throws -> DeviceProviding) {
        self.makeProvider = makeProvider
    }

    // MARK: - Lifecycle

    /// Discovers/connects the device (via `makeProvider`), reads capability flags and an
    /// initial snapshot of every supported field, then begins battery polling. Any failure —
    /// discovery or an initial read — moves `state.status` to `.error`.
    public func start() async {
        state.status = .connecting
        do {
            let provider = try await makeProvider()
            self.provider = provider

            let profile = provider.profile
            state.supportsLiveNoise = profile.hasAudioSettingsRegister
            state.supportsProfiles = profile.supportsCustomProfiles

            try await readAll(from: provider)

            state.status = .connected
            startBatteryPolling()
        } catch {
            state.status = .error(describe(error))
            provider = nil
        }
    }

    /// Re-reads every supported field from the current provider. No-op if not connected.
    public func refresh() async {
        guard let provider else { return }
        do {
            try await readAll(from: provider)
        } catch {
            state.status = .error(describe(error))
        }
    }

    private func readAll(from provider: DeviceProviding) async throws {
        state.battery = try await provider.battery()
        state.firmware = try await provider.firmware()
        state.name = try await provider.name()
        state.currentModeIndex = try await provider.currentMode()
        state.eq = try await provider.eq()
        state.sidetone = try await provider.sidetone()
        state.multipoint = try await provider.multipoint()
        state.autoPause = try await provider.autoPause()
        state.autoAnswer = try await provider.autoAnswer()

        if state.supportsProfiles {
            let modes = try await provider.modes()
            state.modeNames = Dictionary(uniqueKeysWithValues: modes.map { ($0.index, $0.name) })
        } else {
            state.modeNames = nil
        }
    }

    private func startBatteryPolling() {
        batteryPollTask?.cancel()
        batteryPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.batteryPollInterval)
                guard !Task.isCancelled, let self else { return }
                await self.pollBattery()
            }
        }
    }

    private func pollBattery() async {
        guard let provider else { return }
        if let battery = try? await provider.battery() {
            state.battery = battery
        }
    }

    // MARK: - Intents

    /// Immediate (not debounced) — mode switches are discrete, infrequent actions. Writes,
    /// then reconciles `state.currentModeIndex` from a fresh read (BLE can clamp/reject a
    /// write); a write failure records `lastError` without touching connection `status`.
    public func switchMode(index: Int) async {
        guard let provider else { return }
        state.currentModeIndex = index
        do {
            try await provider.setMode(index: index, announce: false)
            state.lastError = nil
            state.currentModeIndex = (try? await provider.currentMode()) ?? index
        } catch {
            state.lastError = describe(error)
        }
    }

    /// Debounced ~150ms — sliders/steppers fire many updates in quick succession.
    public func setEQ(band: Int, value: Int) {
        guard provider != nil else { return }
        if var eq = state.eq, let idx = eq.firstIndex(where: { $0.band == band }) {
            eq[idx].value = value
            state.eq = eq
        } else {
            state.eq = (state.eq ?? []) + [EQBand(band: band, value: value)]
        }
        debounce(key: "eq-\(band)", write: { provider in
            try await provider.setEQ(band: band, value: value)
        }, reconcile: { [weak self] provider in
            guard let self else { return }
            self.state.eq = (try? await provider.eq()) ?? self.state.eq
        })
    }

    public func setSidetone(_ level: Int) {
        guard provider != nil else { return }
        state.sidetone = level
        debounce(key: "sidetone", write: { provider in
            try await provider.setSidetone(level)
        }, reconcile: { [weak self] provider in
            guard let self else { return }
            self.state.sidetone = (try? await provider.sidetone()) ?? self.state.sidetone
        })
    }

    public func setAutoPause(_ on: Bool) {
        guard provider != nil else { return }
        state.autoPause = on
        debounce(key: "autoPause", write: { provider in
            try await provider.setAutoPause(on)
        }, reconcile: { [weak self] provider in
            guard let self else { return }
            self.state.autoPause = (try? await provider.autoPause()) ?? self.state.autoPause
        })
    }

    public func setAutoAnswer(_ on: Bool) {
        guard provider != nil else { return }
        state.autoAnswer = on
        debounce(key: "autoAnswer", write: { provider in
            try await provider.setAutoAnswer(on)
        }, reconcile: { [weak self] provider in
            guard let self else { return }
            self.state.autoAnswer = (try? await provider.autoAnswer()) ?? self.state.autoAnswer
        })
    }

    public func setName(_ name: String) {
        guard provider != nil else { return }
        state.name = name
        debounce(key: "name", write: { provider in
            try await provider.setName(name)
        }, reconcile: { [weak self] provider in
            guard let self else { return }
            self.state.name = (try? await provider.name()) ?? self.state.name
        })
    }

    /// Cancels any pending write for `key` and schedules a new one after `debounceDelay`, so
    /// rapid successive calls (e.g. a dragged slider) coalesce into a single device write.
    /// On a successful write, `lastError` is cleared and `reconcile` re-reads the single
    /// field from the device (BLE can clamp/reject a write, so the optimistic value isn't
    /// trusted as final). A write failure sets `lastError` and skips reconcile; it never
    /// touches connection `status` — the provider/connection is still live.
    private func debounce(
        key: String,
        write: @escaping (DeviceProviding) async throws -> Void,
        reconcile: @escaping (DeviceProviding) async -> Void
    ) {
        debounceTasks[key]?.cancel()
        debounceTasks[key] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.debounceDelay)
            guard !Task.isCancelled, let self, let provider = self.provider else { return }
            do {
                try await write(provider)
                self.state.lastError = nil
                await reconcile(provider)
            } catch {
                self.state.lastError = self.describe(error)
            }
        }
    }

    private func describe(_ error: Error) -> String {
        if let bmapError = error as? BMAPError {
            return String(describing: bmapError)
        }
        return error.localizedDescription
    }
}
