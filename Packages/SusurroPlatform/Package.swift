// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "SusurroPlatform",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SusurroPlatform", targets: ["Permissions", "Hotkeys"])
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
        .testTarget(name: "PermissionsTests", dependencies: ["Permissions"]),
    ],
    swiftLanguageModes: [.v6]
)
