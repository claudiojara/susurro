// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "SusurroPlatform",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SusurroPlatform", targets: ["Permissions"])
    ],
    targets: [
        .target(name: "Permissions"),
        .testTarget(name: "PermissionsTests", dependencies: ["Permissions"]),
    ],
    swiftLanguageModes: [.v6]
)
