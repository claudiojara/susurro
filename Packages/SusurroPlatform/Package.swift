// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "SusurroPlatform",
    platforms: [.macOS(.v26)],
    products: [
        .library(
            name: "SusurroPlatform",
            targets: [
                "Permissions", "Hotkeys", "AudioIO", "TextInsertion", "Diagnostics", "Settings", "Persistence",
                "AccessibilityContext",
                "LanguageDetection",
            ]
        )
    ],
    dependencies: [
        .package(path: "../SusurroCore"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", exact: "3.1.0"),
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1"),
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
        .target(name: "Diagnostics", dependencies: [.product(name: "SusurroCore", package: "SusurroCore")]),
        .target(name: "AccessibilityContext", dependencies: [.product(name: "SusurroCore", package: "SusurroCore")]),
        .target(name: "Settings", dependencies: [.product(name: "SusurroCore", package: "SusurroCore")]),
        .target(name: "LanguageDetection", dependencies: [.product(name: "SusurroCore", package: "SusurroCore")]),
        .target(
            name: "Persistence",
            dependencies: [
                .product(name: "SusurroCore", package: "SusurroCore"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
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
            name: "AccessibilityContextTests",
            dependencies: [
                "AccessibilityContext",
                .product(name: "SusurroCore", package: "SusurroCore"),
                .product(name: "CoreTestSupport", package: "SusurroCore"),
            ]
        ),
        .testTarget(
            name: "DiagnosticsTests",
            dependencies: ["Diagnostics", .product(name: "SusurroCore", package: "SusurroCore")]
        ),
        .testTarget(
            name: "SettingsTests",
            dependencies: [
                "Settings",
                .product(name: "SusurroCore", package: "SusurroCore"),
                .product(name: "CoreTestSupport", package: "SusurroCore"),
            ]
        ),
        .testTarget(
            name: "PersistenceTests",
            dependencies: [
                "Persistence",
                .product(name: "SusurroCore", package: "SusurroCore"),
                .product(name: "CoreTestSupport", package: "SusurroCore"),
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(
            name: "LanguageDetectionTests",
            dependencies: [
                "LanguageDetection",
                .product(name: "SusurroCore", package: "SusurroCore"),
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
