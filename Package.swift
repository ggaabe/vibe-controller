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
        .executable(name: "VirtualHIDExperiment", targets: ["VirtualHIDExperiment"]),
        .executable(name: "VibeVirtualHIDBridge", targets: ["VibeVirtualHIDBridge"]),
    ],
    targets: [
        .executableTarget(
            name: "VibeController",
            resources: [.copy("Resources/Controllers")]
        ),
        .executableTarget(
            name: "ControllerProbe"
        ),
        .executableTarget(
            name: "VirtualHIDExperiment"
        ),
        .executableTarget(
            name: "VibeVirtualHIDBridge",
            cSettings: [
                .unsafeFlags(["-Wall", "-Wextra", "-Werror"]),
            ],
            linkerSettings: [
                .linkedFramework("CoreFoundation"),
                .linkedFramework("Security"),
            ]
        ),
        .testTarget(
            name: "VibeControllerTests",
            dependencies: ["VibeController"]
        ),
    ]
)
