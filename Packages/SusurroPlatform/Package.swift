// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "SusurroPlatform",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SusurroPlatform", targets: ["Permissions", "Hotkeys", "AudioIO", "TextInsertion"])
    ],
    dependencies: [
        .package(path: "../SusurroCore"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", exact: "3.1.0"),
    ],
    targets: [
        .target(name: "Permissions", dependencies: [.product(name: "SusurroCore", package: "SusurroCore")]),
        .target(
            name: "Hotkeys",
            dependencies: [
                .product(name: "SusurroCore", package: "SusurroCore"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ]
        ),
        .target(name: "AudioIO", dependencies: [.product(name: "SusurroCore", package: "SusurroCore")]),
        .target(name: "TextInsertion", dependencies: [.product(name: "SusurroCore", package: "SusurroCore")]),
        .testTarget(
            name: "PermissionsTests",
            dependencies: ["Permissions", .product(name: "SusurroCore", package: "SusurroCore")]
        ),
        .testTarget(
            name: "AudioIOTests",
            dependencies: [
                "AudioIO",
                .product(name: "SusurroCore", package: "SusurroCore"),
                .product(name: "CoreTestSupport", package: "SusurroCore"),
            ]
        ),
        .testTarget(
            name: "TextInsertionTests",
            dependencies: [
                "TextInsertion",
                .product(name: "SusurroCore", package: "SusurroCore"),
                .product(name: "CoreTestSupport", package: "SusurroCore"),
            ]
        ),
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
