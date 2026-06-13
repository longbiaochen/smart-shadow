// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SmartShadow",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "SmartShadowGitHubAPI", targets: ["SmartShadowGitHubAPI"]),
        .library(name: "SmartShadowShared", targets: ["SmartShadowShared"]),
        .executable(name: "shadowd", targets: ["ShadowD"]),
        .executable(name: "smart-shadow-menu", targets: ["SmartShadowMenu"]),
        .executable(name: "smart-shadow-companion-mac", targets: ["SmartShadowCompanionMac"])
    ],
    targets: [
        .executableTarget(
            name: "ShadowD",
            dependencies: ["SmartShadowShared"],
            path: "Sources/SmartShadowMacCore",
            linkerSettings: [
                .linkedFramework("Contacts"),
                .linkedFramework("EventKit"),
                .linkedFramework("Security")
            ]
        ),
        .target(
            name: "SmartShadowGitHubAPI",
            path: "Sources/SmartShadowGitHubAPI"
        ),
        .target(
            name: "SmartShadowShared",
            path: "Sources/SmartShadowShared",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("Security"),
                .linkedFramework("SwiftUI")
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
        .executableTarget(
            name: "SmartShadowCompanionMac",
            dependencies: ["SmartShadowGitHubAPI", "SmartShadowShared"],
            path: "Sources/SmartShadowCompanionMac",
            exclude: ["Assets.xcassets"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("Speech"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .testTarget(
            name: "SmartShadowMenuCoreTests",
            dependencies: ["SmartShadowMenuCore"],
            path: "tests/SmartShadowMenuCoreTests"
        ),
        .testTarget(
            name: "SmartShadowSharedTests",
            dependencies: ["SmartShadowGitHubAPI", "SmartShadowShared"],
            path: "tests/SmartShadowSharedTests"
        ),
        .testTarget(
            name: "SmartShadowCompanionMacTests",
            dependencies: ["SmartShadowCompanionMac"],
            path: "tests/SmartShadowCompanionMacTests"
        )
    ]
)
