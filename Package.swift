// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SmartShadow",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "smart-shadow-mac-core", targets: ["SmartShadowMacCore"]),
        .executable(name: "smart-shadow-menu", targets: ["SmartShadowMenu"])
    ],
    targets: [
        .executableTarget(
            name: "SmartShadowMacCore",
            path: "Sources/SmartShadowMacCore",
            linkerSettings: [
                .linkedFramework("EventKit")
            ]
        ),
        .target(
            name: "SmartShadowMenuCore",
            path: "Sources/SmartShadowMenuCore"
        ),
        .executableTarget(
            name: "SmartShadowMenu",
            dependencies: ["SmartShadowMenuCore"],
            path: "Sources/SmartShadowMenu",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .testTarget(
            name: "SmartShadowMenuCoreTests",
            dependencies: ["SmartShadowMenuCore"],
            path: "tests/SmartShadowMenuCoreTests"
        )
    ]
)
