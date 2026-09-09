import Testing
@testable import BoseKit

@Test func buildsGet() {
    #expect(Array(BMAPBuild.get(Addr.battery).encoded) == [0x02,0x02,0x01,0x00])
}

@Test func buildsSetName() {
    #expect(Array(BMAPBuild.setName("Fargo").encoded) == [0x01,0x02,0x02,0x05,0x46,0x61,0x72,0x67,0x6f])
}

@Test func buildsSetModeAware() {
    #expect(Array(BMAPBuild.setMode(index: 1, announce: false).encoded) == [0x1f,0x03,0x05,0x02,0x01,0x00])
}

@Test func buildsToggleMultipointOff() {
    #expect(Array(BMAPBuild.toggle(Addr.multipoint, on: false).encoded) == [0x01,0x0a,0x02,0x01,0x00])
}

@Test func buildsSidetoneMedium() {
    #expect(Array(BMAPBuild.setSidetone(level: 2).encoded) == [0x01,0x0b,0x02,0x02,0x01,0x02])
}
