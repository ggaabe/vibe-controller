// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "VibeController",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "VibeController", targets: ["VibeController"]),
        .executable(name: "ControllerProbe", targets: ["ControllerProbe"]),
    ],
    targets: [
        .executableTarget(
            name: "VibeController"
        ),
        .executableTarget(
            name: "ControllerProbe"
        ),
        .testTarget(
            name: "VibeControllerTests",
            dependencies: ["VibeController"]
        ),
    ]
)
