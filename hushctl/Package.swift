// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "hushctl",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../BoseKit")],
    targets: [.executableTarget(name: "hushctl", dependencies: ["BoseKit"])]
)
