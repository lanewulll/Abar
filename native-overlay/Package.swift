// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AbarNativeOverlay",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "AbarOverlayCore", targets: ["AbarOverlayCore"]),
        .executable(name: "AbarNativeOverlay", targets: ["AbarNativeOverlay"])
    ],
    targets: [
        .target(
            name: "AbarOverlayCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "AbarNativeOverlay",
            dependencies: ["AbarOverlayCore"]
        ),
        .testTarget(
            name: "AbarOverlayCoreTests",
            dependencies: ["AbarOverlayCore"]
        ),
        .testTarget(
            name: "AbarNativeOverlayTests",
            dependencies: ["AbarNativeOverlay", "AbarOverlayCore"]
        )
    ]
)
