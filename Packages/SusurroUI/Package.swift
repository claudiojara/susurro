// swift-tools-version: 6.4

import PackageDescription

let package = Package(
    name: "SusurroUI",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SusurroUI", targets: ["SusurroUI"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing.git", exact: "1.19.6")
    ],
    targets: [
        .target(
            name: "DesignSystem",
            resources: [.process("Resources")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .target(
            name: "SusurroUI",
            dependencies: ["DesignSystem"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        // Renders views the same way on every machine and asserts snapshots of them. Only test targets use it.
        .target(
            name: "UITestSupport",
            dependencies: [
                "DesignSystem",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem", "UITestSupport"], exclude: ["Fixtures"]),
        .testTarget(name: "SusurroUITests", dependencies: ["SusurroUI", "DesignSystem", "UITestSupport"]),
    ],
    swiftLanguageModes: [.v6]
)
