import Foundation
import Testing
@testable import BoseKit

actor MockSender: FrameSender {
    var sent: [BMAPFrame] = []
    var replies: [[BMAPFrame]] = []
    func setReplies(_ r: [[BMAPFrame]]) { replies = r }
    func send(_ frame: BMAPFrame, drain: Bool, timeout: TimeInterval) async throws -> [BMAPFrame] {
        sent.append(frame)
        return replies.isEmpty ? [] : replies.removeFirst()
    }
}

/// Builds a 48-byte ModeConfig STATUS payload using the offsets from spec §4.4
/// (mirrors `parses48ByteModeConfig` in ModeConfigTests.swift).
private func modeConfigPayload(index: Int, name: String, editable: Bool, configured: Bool,
                                cnc: Int, autoCNC: Int, spatial: Int, wind: Int, anc: Int) -> [UInt8] {
    var p = [UInt8](repeating: 0, count: 48)
    p[0] = UInt8(index)
    p[3] = editable ? 1 : 0
    p[4] = configured ? 1 : 0
    for (i, b) in Array(name.utf8).enumerated() { p[6 + i] = b }
    p[42] = UInt8(cnc); p[43] = UInt8(autoCNC); p[44] = UInt8(spatial); p[45] = UInt8(wind); p[47] = UInt8(anc)
    return p
}

// MARK: - DeviceProfile

@Test func deviceProfileWolverineValues() {
    #expect(DeviceProfile.wolverine.productID == 0x4082)
    #expect(DeviceProfile.wolverine.codename == "wolverine")
    #expect(DeviceProfile.wolverine.rfcommChannel == 2)
    #expect(DeviceProfile.wolverine.hasAudioSettingsRegister == true)
    #expect(DeviceProfile.wolverine.modeConfigStatusLength == 48)
    #expect(DeviceProfile.wolverine.modeConfigSetLength == 40)
    #expect(DeviceProfile.wolverine.editableSlots == 4...10)
}

@Test func deviceProfileLonestarrValues() {
    // Task 14 hardware verification: RFCOMM channel, ModeConfig lengths, and editable
    // slots match wolverine. Task 15 / 2026-09-09 verification: gen-1 does NOT expose
    // [31.10] (FuncNotSupp), unlike wolverine — this is the one deliberate divergence.
    #expect(DeviceProfile.lonestarr.productID == 0x4066)
    #expect(DeviceProfile.lonestarr.codename == "lonestarr")
    #expect(DeviceProfile.lonestarr.rfcommChannel == DeviceProfile.wolverine.rfcommChannel)
    #expect(DeviceProfile.lonestarr.hasAudioSettingsRegister == false)
    #expect(DeviceProfile.lonestarr.modeConfigStatusLength == DeviceProfile.wolverine.modeConfigStatusLength)
    #expect(DeviceProfile.lonestarr.modeConfigSetLength == DeviceProfile.wolverine.modeConfigSetLength)
    #expect(DeviceProfile.lonestarr.editableSlots == DeviceProfile.wolverine.editableSlots)
}

// MARK: - Battery / Firmware / Name

@Test func readsBatteryThroughDevice() async throws {
    let mock = MockSender()
    await mock.setReplies([[BMAPFrame(fblock: 0x02, function: 0x02, op: .status, payload: [0x50,0xff,0xff,0x00])]])
    let dev = BoseDevice(sender: mock, profile: .wolverine)
    #expect(try await dev.battery() == 80)
    let sent = await mock.sent
    #expect(sent.last == BMAPBuild.get(Addr.battery))
}

@Test func batteryPropagatesDeviceErrorFrame() async throws {
    let mock = MockSender()
    await mock.setReplies([[BMAPFrame(fblock: 0x02, function: 0x02, op: .error, payload: [0x08])]])
    let dev = BoseDevice(sender: mock, profile: .wolverine)
    do {
        _ = try await dev.battery()
        Issue.record("expected battery() to throw")
    } catch let error as BMAPError {
        #expect(error == .device(code: 8))
    }
}

@Test func batteryThrowsUnexpectedResponseOnMismatchedAddress() async throws {
    let mock = MockSender()
    await mock.setReplies([[BMAPFrame(fblock: 0x99, function: 0x99, op: .status, payload: [0x50])]])
    let dev = BoseDevice(sender: mock, profile: .wolverine)
    do {
        _ = try await dev.battery()
        Issue.record("expected battery() to throw")
    } catch let error as BMAPError {
        #expect(error == .unexpectedResponse)
    }
}

@Test func readsFirmwareThroughDevice() async throws {
    let mock = MockSender()
    await mock.setReplies([[BMAPFrame(fblock: 0x00, function: 0x05, op: .status, payload: Array("1.6.7".utf8))]])
    let dev = BoseDevice(sender: mock, profile: .wolverine)
    #expect(try await dev.firmware() == "1.6.7")
    let sent = await mock.sent
    #expect(sent.last == BMAPBuild.get(Addr.firmware))
}

@Test func readsNameThroughDevice() async throws {
    let mock = MockSender()
    await mock.setReplies([[BMAPFrame(fblock: 0x01, function: 0x02, op: .status, payload: [0x00] + Array("Fargo".utf8))]])
    let dev = BoseDevice(sender: mock, profile: .wolverine)
    #expect(try await dev.name() == "Fargo")
    let sent = await mock.sent
    #expect(sent.last == BMAPBuild.get(Addr.name))
}

@Test func setNameSendsRawUTF8WithoutLeadingFlag() async throws {
    let mock = MockSender()
    await mock.setReplies([[BMAPFrame(fblock: 0x01, function: 0x02, op: .status, payload: Array("Fargo".utf8))]])
    let dev = BoseDevice(sender: mock, profile: .wolverine)
    try await dev.setName("Fargo")
    let sent = await mock.sent
    #expect(sent.last == BMAPBuild.setName("Fargo"))
}

// MARK: - Mode

@Test func readsCurrentModeThroughDevice() async throws {
    let mock = MockSender()
    await mock.setReplies([[BMAPFrame(fblock: 0x1f, function: 0x03, op: .status, payload: [0x02])]])
    let dev = BoseDevice(sender: mock, profile: .wolverine)
    #expect(try await dev.currentMode() == 2)
    let sent = await mock.sent
    #expect(sent.last == BMAPBuild.get(Addr.currentMode))
}

@Test func setModeSendsStartWithAnnounceFlag() async throws {
    let mock = MockSender()
    await mock.setReplies([[BMAPFrame(fblock: 0x1f, function: 0x03, op: .result, payload: [])]])
    let dev = BoseDevice(sender: mock, profile: .wolverine)
    try await dev.setMode(1, announce: true)
    let sent = await mock.sent
    #expect(sent.last == BMAPBuild.setMode(index: 1, announce: true))
}

// MARK: - Audio settings register [31.10]

@Test func readsAudioSettingsThroughDevice() async throws {
    let mock = MockSender()
    await mock.setReplies([[BMAPFrame(fblock: 0x1f, function: 0x0a, op: .status, payload: [0x03,0x00,0x02,0x00,0x01])]])
    let dev = BoseDevice(sender: mock, profile: .wolverine)
    let s = try await dev.audioSettings()
    #expect(s == AudioSettings(cnc: 3, autoCNC: 0, spatial: 2, wind: 0, anc: 1))
    let sent = await mock.sent
    #expect(sent.last == BMAPBuild.get(Addr.audioSettings))
}

@Test func setCNCReadModifyWrites() async throws {
    let mock = MockSender()
    await mock.setReplies([
        [BMAPFrame(fblock: 0x1f, function: 0x0a, op: .status, payload: [0x00,0x00,0x00,0x00,0x01])],
        [BMAPFrame(fblock: 0x1f, function: 0x0a, op: .status, payload: [0x05,0x00,0x00,0x00,0x01])],
    ])
    let dev = BoseDevice(sender: mock, profile: .wolverine)
    try await dev.setCNC(5)
    let sent = await mock.sent
    #expect(sent.last?.op == .setGet)
    #expect(sent.last?.payload == [0x05,0x00,0x00,0x00,0x01]) // cnc=5, autoCNC cleared, anc=1 preserved
}

@Test func setCNCPropagatesDeviceErrorOnWrite() async throws {
    // A write's own ERROR reply (e.g. Runtime err 8 for an autoCNC conflict) must
    // surface as a thrown error, not be silently swallowed.
    let mock = MockSender()
    await mock.setReplies([
        [BMAPFrame(fblock: 0x1f, function: 0x0a, op: .status, payload: [0x00,0x00,0x00,0x00,0x01])],
        [BMAPFrame(fblock: 0x1f, function: 0x0a, op: .error, payload: [0x08])],
    ])
    let dev = BoseDevice(sender: mock, profile: .wolverine)
    do {
        try await dev.setCNC(5)
        Issue.record("expected setCNC to throw on a device ERROR reply")
    } catch let error as BMAPError {
        #expect(error == .device(code: 8))
    }
}

@Test func setANCReadModifyWritesPreservingOtherFields() async throws {
    let mock = MockSender()
    await mock.setReplies([
        [BMAPFrame(fblock: 0x1f, function: 0x0a, op: .status, payload: [0x05,0x00,0x00,0x00,0x00])],
        [BMAPFrame(fblock: 0x1f, function: 0x0a, op: .status, payload: [0x05,0x00,0x00,0x00,0x01])],
    ])
    let dev = BoseDevice(sender: mock, profile: .wolverine)
    try await dev.setANC(true)
    let sent = await mock.sent
    #expect(sent.last?.op == .setGet)
    #expect(sent.last?.payload == [0x05,0x00,0x00,0x00,0x01]) // anc turned on, cnc=5 preserved
}

@Test func setWindReadModifyWritesPreservingOtherFields() async throws {
    let mock = MockSender()
    await mock.setReplies([
        [BMAPFrame(fblock: 0x1f, function: 0x0a, op: .status, payload: [0x05,0x00,0x00,0x00,0x01])],
        [BMAPFrame(fblock: 0x1f, function: 0x0a, op: .status, payload: [0x05,0x00,0x00,0x01,0x01])],
    ])
    let dev = BoseDevice(sender: mock, profile: .wolverine)
    try await dev.setWind(true)
    let sent = await mock.sent
    #expect(sent.last?.payload == [0x05,0x00,0x00,0x01,0x01]) // wind on, cnc/anc preserved
}

@Test func setSpatialReadModifyWritesPreservingOtherFields() async throws {
    let mock = MockSender()
    await mock.setReplies([
        [BMAPFrame(fblock: 0x1f, function: 0x0a, op: .status, payload: [0x05,0x00,0x00,0x00,0x01])],
        [BMAPFrame(fblock: 0x1f, function: 0x0a, op: .status, payload: [0x05,0x00,0x02,0x00,0x01])],
    ])
    let dev = BoseDevice(sender: mock, profile: .wolverine)
    try await dev.setSpatial(2) // head
    let sent = await mock.sent
    #expect(sent.last?.payload == [0x05,0x00,0x02,0x00,0x01])
}

// MARK: - Noise control unsupported on devices without [31.10] (lonestarr — Task 16)
//
// v1 scope decision: the Task 15 `[31.6]` ModeConfig fallback was verified broken on real
// hardware (firmware-locked presets + mismatched payload layout), so devices without
// `[31.10]` now throw `.unsupported` immediately for audioSettings/CNC/ANC/Wind/Spatial,
// without sending anything to the device.

@Test func audioSettingsThrowsUnsupportedWhenNoAudioSettingsRegister() async throws {
    let mock = MockSender()
    let dev = BoseDevice(sender: mock, profile: .lonestarr)
    do {
        _ = try await dev.audioSettings()
        Issue.record("expected audioSettings() to throw")
    } catch let error as BMAPError {
        #expect(error == .unsupported)
    }
    let sent = await mock.sent
    #expect(sent.isEmpty) // rejected locally, never round-tripped to the device
}

@Test func setCNCThrowsUnsupportedWhenNoAudioSettingsRegister() async throws {
    let mock = MockSender()
    let dev = BoseDevice(sender: mock, profile: .lonestarr)
    do {
        try await dev.setCNC(5)
        Issue.record("expected setCNC to throw")
    } catch let error as BMAPError {
        #expect(error == .unsupported)
    }
    let sent = await mock.sent
    #expect(sent.isEmpty)
}

@Test func setANCThrowsUnsupportedWhenNoAudioSettingsRegister() async throws {
    let mock = MockSender()
    let dev = BoseDevice(sender: mock, profile: .lonestarr)
    do {
        try await dev.setANC(true)
        Issue.record("expected setANC to throw")
    } catch let error as BMAPError {
        #expect(error == .unsupported)
    }
    let sent = await mock.sent
    #expect(sent.isEmpty)
}

@Test func setWindThrowsUnsupportedWhenNoAudioSettingsRegister() async throws {
    let mock = MockSender()
    let dev = BoseDevice(sender: mock, profile: .lonestarr)
    do {
        try await dev.setWind(true)
        Issue.record("expected setWind to throw")
    } catch let error as BMAPError {
        #expect(error == .unsupported)
    }
    let sent = await mock.sent
    #expect(sent.isEmpty)
}

@Test func setSpatialThrowsUnsupportedWhenNoAudioSettingsRegister() async throws {
    let mock = MockSender()
    let dev = BoseDevice(sender: mock, profile: .lonestarr)
    do {
        try await dev.setSpatial(2)
        Issue.record("expected setSpatial to throw")
    } catch let error as BMAPError {
        #expect(error == .unsupported)
    }
    let sent = await mock.sent
    #expect(sent.isEmpty)
}

// MARK: - EQ

@Test func readsEQFromSingleConcatenatedFrame() async throws {
    let mock = MockSender()
    let payload: [UInt8] = [0xf6,0x0a,0x00,0x00, 0xf6,0x0a,0xfe,0x01, 0xf6,0x0a,0xfa,0x02]
    await mock.setReplies([[BMAPFrame(fblock: 0x01, function: 0x07, op: .status, payload: payload)]])
    let dev = BoseDevice(sender: mock, profile: .wolverine)
    let bands = try await dev.eq()
    #expect(bands == [EQBand(band: 0, value: 0), EQBand(band: 1, value: -2), EQBand(band: 2, value: -6)])
}

@Test func readsEQFromMultipleDrainedStatusFrames() async throws {
    let mock = MockSender()
    await mock.setReplies([[
        BMAPFrame(fblock: 0x01, function: 0x07, op: .status, payload: [0xf6,0x0a,0x00,0x00]),
        BMAPFrame(fblock: 0x01, function: 0x07, op: .status, payload: [0xf6,0x0a,0xfe,0x01]),
        BMAPFrame(fblock: 0x01, function: 0x07, op: .status, payload: [0xf6,0x0a,0xfa,0x02]),
    ]])
    let dev = BoseDevice(sender: mock, profile: .wolverine)
    let bands = try await dev.eq()
    #expect(bands == [EQBand(band: 0, value: 0), EQBand(band: 1, value: -2), EQBand(band: 2, value: -6)])
    let sent = await mock.sent
    #expect(sent.last == BMAPBuild.get(Addr.eq))
}

@Test func setEQSendsPerBandFrame() async throws {
    let mock = MockSender()
    await mock.setReplies([[BMAPFrame(fblock: 0x01, function: 0x07, op: .status, payload: [])]])
    let dev = BoseDevice(sender: mock, profile: .wolverine)
    try await dev.setEQ(band: 0, value: -4)
    let sent = await mock.sent
    #expect(sent.last == BMAPBuild.eqBand(value: -4, band: 0))
}

// MARK: - Sidetone

@Test func readsSidetoneThroughDevice() async throws {
    let mock = MockSender()
    await mock.setReplies([[BMAPFrame(fblock: 0x01, function: 0x0b, op: .status, payload: [0x01,0x02])]])
    let dev = BoseDevice(sender: mock, profile: .wolverine)
    #expect(try await dev.sidetone() == 2)
    let sent = await mock.sent
    #expect(sent.last == BMAPBuild.get(Addr.sidetone))
}

@Test func setSidetoneSendsSETGET() async throws {
    let mock = MockSender()
    await mock.setReplies([[BMAPFrame(fblock: 0x01, function: 0x0b, op: .status, payload: [0x01,0x02])]])
    let dev = BoseDevice(sender: mock, profile: .wolverine)
    try await dev.setSidetone(2)
    let sent = await mock.sent
    #expect(sent.last == BMAPBuild.setSidetone(level: 2))
}

// MARK: - Multipoint

@Test func readsMultipointThroughDevice() async throws {
    let mock = MockSender()
    await mock.setReplies([[BMAPFrame(fblock: 0x01, function: 0x0a, op: .status, payload: [0x02])]])
    let dev = BoseDevice(sender: mock, profile: .wolverine)
    #expect(try await dev.multipoint() == true)
    let sent = await mock.sent
    #expect(sent.last == BMAPBuild.get(Addr.multipoint))
}

@Test func setMultipointSendsPlainBit() async throws {
    let mock = MockSender()
    await mock.setReplies([[BMAPFrame(fblock: 0x01, function: 0x0a, op: .status, payload: [0x00])]])
    let dev = BoseDevice(sender: mock, profile: .wolverine)
    try await dev.setMultipoint(false)
    let sent = await mock.sent
    #expect(sent.last == BMAPBuild.toggle(Addr.multipoint, on: false))
}

// MARK: - Auto-pause / Auto-answer

@Test func readsAutoPauseThroughDevice() async throws {
    let mock = MockSender()
    await mock.setReplies([[BMAPFrame(fblock: 0x01, function: 0x18, op: .status, payload: [0x01])]])
    let dev = BoseDevice(sender: mock, profile: .wolverine)
    #expect(try await dev.autoPause() == true)
    let sent = await mock.sent
    #expect(sent.last == BMAPBuild.get(Addr.autoPause))
}

@Test func setAutoPauseSendsSETGET() async throws {
    let mock = MockSender()
    await mock.setReplies([[BMAPFrame(fblock: 0x01, function: 0x18, op: .status, payload: [0x00])]])
    let dev = BoseDevice(sender: mock, profile: .wolverine)
    try await dev.setAutoPause(false)
    let sent = await mock.sent
    #expect(sent.last == BMAPBuild.toggle(Addr.autoPause, on: false))
}

@Test func readsAutoAnswerThroughDevice() async throws {
    let mock = MockSender()
    await mock.setReplies([[BMAPFrame(fblock: 0x01, function: 0x1b, op: .status, payload: [0x00])]])
    let dev = BoseDevice(sender: mock, profile: .wolverine)
    #expect(try await dev.autoAnswer() == false)
    let sent = await mock.sent
    #expect(sent.last == BMAPBuild.get(Addr.autoAnswer))
}

@Test func setAutoAnswerSendsSETGET() async throws {
    let mock = MockSender()
    await mock.setReplies([[BMAPFrame(fblock: 0x01, function: 0x1b, op: .status, payload: [0x01])]])
    let dev = BoseDevice(sender: mock, profile: .wolverine)
    try await dev.setAutoAnswer(true)
    let sent = await mock.sent
    #expect(sent.last == BMAPBuild.toggle(Addr.autoAnswer, on: true))
}

// MARK: - Voice prompts

@Test func readsVoicePromptsThroughDevice() async throws {
    let mock = MockSender()
    await mock.setReplies([[BMAPFrame(fblock: 0x01, function: 0x03, op: .status, payload: [0x23])]]) // enabled + lang 3
    let dev = BoseDevice(sender: mock, profile: .wolverine)
    let r = try await dev.voicePrompts()
    #expect(r.enabled == true && r.language == 3)
    let sent = await mock.sent
    #expect(sent.last == BMAPBuild.get(Addr.voicePrompts))
}

@Test func setVoicePromptsSendsEncodedByte() async throws {
    let mock = MockSender()
    await mock.setReplies([[BMAPFrame(fblock: 0x01, function: 0x03, op: .status, payload: [0x23])]])
    let dev = BoseDevice(sender: mock, profile: .wolverine)
    try await dev.setVoicePrompts(enabled: true, language: 3)
    let sent = await mock.sent
    #expect(sent.last == BMAPBuild.setVoicePrompts(enabled: true, language: 3))
}

// MARK: - Buttons

@Test func readsButtonMappingThroughDevice() async throws {
    let mock = MockSender()
    await mock.setReplies([[BMAPFrame(fblock: 0x01, function: 0x09, op: .status, payload: [0x01,0x02,0x03])]])
    let dev = BoseDevice(sender: mock, profile: .wolverine)
    let m = try await dev.buttons()
    #expect(m == ButtonMapping(button: 1, event: 2, action: 3))
    let sent = await mock.sent
    #expect(sent.last == BMAPBuild.get(Addr.buttons))
}

@Test func setButtonSendsSETGET() async throws {
    let mock = MockSender()
    await mock.setReplies([[BMAPFrame(fblock: 0x01, function: 0x09, op: .status, payload: [0x01,0x02,0x03])]])
    let dev = BoseDevice(sender: mock, profile: .wolverine)
    try await dev.setButton(ButtonMapping(button: 1, event: 2, action: 3))
    let sent = await mock.sent
    #expect(sent.last == BMAPBuild.setButton(ButtonMapping(button: 1, event: 2, action: 3)))
}

// MARK: - Profiles / ModeConfig

@Test func listsModesThroughDevice() async throws {
    let mock = MockSender()
    let quiet = modeConfigPayload(index: 0, name: "Quiet", editable: false, configured: true,
                                   cnc: 0, autoCNC: 0, spatial: 0, wind: 0, anc: 1)
    let focus = modeConfigPayload(index: 5, name: "Focus", editable: true, configured: true,
                                   cnc: 3, autoCNC: 0, spatial: 1, wind: 0, anc: 1)
    await mock.setReplies([[
        BMAPFrame(fblock: 0x1f, function: 0x06, op: .status, payload: quiet),
        BMAPFrame(fblock: 0x1f, function: 0x06, op: .status, payload: focus),
    ]])
    let dev = BoseDevice(sender: mock, profile: .wolverine)
    let modes = try await dev.modes()
    #expect(modes.count == 2)
    #expect(modes[0].name == "Quiet" && !modes[0].editable)
    #expect(modes[1].name == "Focus" && modes[1].editable && modes[1].cnc == 3)
    let sent = await mock.sent
    #expect(sent.last == BMAPBuild.listProfiles())
}

@Test func saveProfileWritesEditableSlot() async throws {
    let mock = MockSender()
    await mock.setReplies([[BMAPFrame(fblock: 0x1f, function: 0x06, op: .result, payload: [])]])
    let dev = BoseDevice(sender: mock, profile: .wolverine)
    let cfg = ModeConfig(index: 5, name: "Focus", editable: true, configured: true,
                          cnc: 3, autoCNC: 0, spatial: 1, wind: 0, anc: 1)
    try await dev.saveProfile(cfg)
    let sent = await mock.sent
    guard let last = sent.last else { Issue.record("expected a write frame"); return }
    #expect(last.fblock == 0x1f && last.function == 0x06 && last.op == .setGet)
    #expect(last.payload.count == 40)
    #expect(last.payload[0] == 5)
    #expect(Array(last.payload[3..<8]) == Array("Focus".utf8))
    #expect(last.payload[35] == 3 && last.payload[37] == 1 && last.payload[39] == 1)
}

@Test func saveProfileRejectsLockedPresetWithoutSending() async throws {
    let mock = MockSender()
    let dev = BoseDevice(sender: mock, profile: .wolverine)
    let cfg = ModeConfig(index: 0, name: "Quiet", editable: false, configured: true,
                          cnc: 0, autoCNC: 0, spatial: 0, wind: 0, anc: 1)
    do {
        try await dev.saveProfile(cfg)
        Issue.record("expected saveProfile to throw for a locked preset slot")
    } catch let error as BMAPError {
        #expect(error == .unsupported)
    }
    let sent = await mock.sent
    #expect(sent.isEmpty) // rejected locally, never round-tripped to the device
}

@Test func deleteProfileOverwritesSlotWithZeroedNoneConfig() async throws {
    let mock = MockSender()
    let focus = modeConfigPayload(index: 5, name: "Focus", editable: true, configured: true,
                                   cnc: 3, autoCNC: 1, spatial: 1, wind: 1, anc: 1)
    await mock.setReplies([
        [BMAPFrame(fblock: 0x1f, function: 0x06, op: .status, payload: focus)],
        [BMAPFrame(fblock: 0x1f, function: 0x06, op: .result, payload: [])],
    ])
    let dev = BoseDevice(sender: mock, profile: .wolverine)
    try await dev.deleteProfile(name: "Focus")
    let sent = await mock.sent
    guard let last = sent.last else { Issue.record("expected a write frame"); return }
    #expect(last.fblock == 0x1f && last.function == 0x06 && last.op == .setGet)
    #expect(last.payload.count == 40)
    #expect(last.payload[0] == 5) // slot index preserved
    #expect(Array(last.payload[3..<7]) == Array("None".utf8)) // spec §4.4: delete = name "None"
    #expect(last.payload[35] == 0 && last.payload[36] == 0 && last.payload[37] == 0 &&
             last.payload[38] == 0 && last.payload[39] == 0) // ...and zeroed settings
}

@Test func deleteProfileThrowsWhenNameNotFoundAmongEditableModes() async throws {
    let mock = MockSender()
    let quiet = modeConfigPayload(index: 0, name: "Quiet", editable: false, configured: true,
                                   cnc: 0, autoCNC: 0, spatial: 0, wind: 0, anc: 1)
    await mock.setReplies([[BMAPFrame(fblock: 0x1f, function: 0x06, op: .status, payload: quiet)]])
    let dev = BoseDevice(sender: mock, profile: .wolverine)
    do {
        try await dev.deleteProfile(name: "Nope")
        Issue.record("expected deleteProfile to throw when the name isn't found")
    } catch let error as BMAPError {
        #expect(error == .unexpectedResponse)
    }
}
