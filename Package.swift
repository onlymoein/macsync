// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacSync",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MacSyncCore", targets: ["MacSyncCore"]),
        .executable(name: "macsync", targets: ["macsync"]),
        .executable(name: "MacSyncApp", targets: ["MacSyncApp"]),
    ],
    targets: [
        .target(name: "MacSyncCore"),
        .executableTarget(name: "macsync", dependencies: ["MacSyncCore"]),
        .executableTarget(name: "MacSyncApp", dependencies: ["MacSyncCore"]),
        .testTarget(name: "MacSyncCoreTests", dependencies: ["MacSyncCore"]),
    ]
)
