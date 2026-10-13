// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "SusurroUI",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SusurroUI", targets: ["SusurroUI"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
    ],
    targets: [
        .target(
            name: "DesignSystem",
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .target(
            name: "SusurroUI",
            dependencies: ["DesignSystem"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "SusurroUITests", dependencies: ["SusurroUI"]),
    ],
    swiftLanguageModes: [.v6]
)
