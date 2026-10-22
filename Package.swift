// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VPNKeeper",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "VPNKeeper", targets: ["VPNKeeper"])],
    targets: [
        .target(name: "VPNCore"),
        .executableTarget(name: "VPNKeeper", dependencies: ["VPNCore"]),
        .testTarget(name: "VPNCoreTests", dependencies: ["VPNCore"]),
    ]
)
