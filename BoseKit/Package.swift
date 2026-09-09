// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BoseKit",
    platforms: [.macOS(.v14)],
    products: [.library(name: "BoseKit", targets: ["BoseKit"])],
    targets: [
        .target(name: "BoseKit"),
        .testTarget(name: "BoseKitTests", dependencies: ["BoseKit"]),
    ]
)
