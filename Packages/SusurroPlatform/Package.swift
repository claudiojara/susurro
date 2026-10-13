// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "SusurroPlatform",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SusurroPlatform", targets: ["Permissions", "Hotkeys", "AudioIO"])
    ],
    dependencies: [
        .package(path: "../SusurroCore"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", exact: "1.10.0"),
    ],
    targets: [
        .target(name: "Permissions"),
        .target(
            name: "Hotkeys",
            dependencies: [
                .product(name: "SusurroCore", package: "SusurroCore"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ]
        ),
        .target(
            name: "AudioIO",
            dependencies: [.product(name: "SusurroCore", package: "SusurroCore")]
        ),
        .testTarget(name: "PermissionsTests", dependencies: ["Permissions"]),
        .testTarget(
            name: "HotkeysTests",
            dependencies: [
                "Hotkeys",
                .product(name: "SusurroCore", package: "SusurroCore"),
                .product(name: "CoreTestSupport", package: "SusurroCore"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
