// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "StickiesMD",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "StickiesCore"),
        .executableTarget(name: "StickiesMD", dependencies: ["StickiesCore"]),
        .testTarget(name: "StickiesCoreTests", dependencies: ["StickiesCore"]),
    ]
)
